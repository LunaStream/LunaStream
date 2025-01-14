local http = require("coro-http")
local url = require("url")
local json = require("json")

local mod_table = require("../utils/mod_table.lua")
local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")

local class = require('class')

local SoundCloud, get = class('SoundCloud', AbstractSource)

function SoundCloud:__init()
  AbstractSource.__init(self)
  self._clientId = nil
	self._baseUrl = "https://api-v2.soundcloud.com"
  self._sourceName = "soundcloud"
end

function get:clientId()
  return self._clientId
end

function get:baseUrl()
  return self._baseUrl
end

function SoundCloud:setup()
	print("[SoundCloud]: Setting up clientId for fetch tracks...")
	local _, mainsite_body = http.request("GET", "https://soundcloud.com/")
	if mainsite_body == nil then return self:fetchFailed() end

	local assetId =
		string.gmatch(
			mainsite_body,
			"https://a%-v2%.sndcdn%.com/assets/[^%s]+%.js"
		)
	if assetId() == nil then return self:fetchFailed() end

	local call_time = 0
	while call_time < 4 do
		assetId()
		call_time = call_time + 1
	end

	local _, data_body = http.request("GET", assetId())
	if data_body == nil then return self:fetchFailed() end

	local matched = data_body:match("client_id=[^%s]+")
	if matched == nil then self:fetchFailed() end
	local clientId = matched:sub(11, 41 - matched:len())
	self["_clientId"] = clientId
	print("[SoundCloud]: Setting up clientId for fetch tracks successfully")
	return self
end

function SoundCloud:fetchFailed()
	print("[SoundCloud] -> [Error]: Failed to fetch clientId.")
end

function SoundCloud:search(query)
	local query_link =
		self._baseUrl
		.. "/search"
		.. "?q=" .. url.encode(query)
		.. "&variant_ids="
		.. "&facet=model"
		.. "&user_id=992000-167630-994991-450103"
		.. "&client_id=" .. self._clientId
		.. "&limit=" .. "20"
		.. "&offset=0"
		.. "&linked_partitioning=1"
		.. "&app_version=1679652891"
		.. "&app_locale=en"

	local response, res_body = http.request("GET", query_link)
	if response.code ~= 200 then
		print(string.format("[SoundCloud] -> [Error]: Server response error: %s | On query: %s", response.code, query))
		return self:buildError(
		"Server response error: " .. response.code,
		"fault", "SoundCloud Source"
	)
	end
	local decoded = json.decode(res_body)

	if #decoded.collection == 0 then
		return {
			loadType = "empty",
			tracks = { nil }
		}
	end

	local res = {}
	local counter = 1

	for _, value in pairs(decoded.collection) do
		if value.kind ~= "track" then
		else
			res[counter] = self:buildTrack(value)
			counter = counter + 1
		end
	end

	return {
		loadType = "search",
		data = res
	}
end

function SoundCloud:loadForm(query)
	local query_link =
		self._baseUrl
		.. "/resolve"
		.. "?url=" .. url.encode(query)
		.. "&client_id=" .. url.encode(self._clientId)

	local response, res_body = http.request("GET", query_link)
	if response.code ~= 200 then
		print(string.format("[SoundCloud] -> [Error]: Server response error: %s | On link: %s", response.code, query))
		return self:buildError(
			"Server response error: " .. response.code,
			"fault", "SoundCloud Source"
		)
	end

	local body = json.decode(res_body)

	if body.kind == "track" then
		return {
			loadType = "track",
			data = self:buildTrack(body),
		}
	elseif body.kind == "playlist" then
		local loaded = {}
		local unloaded = {}

		for _, raw in pairs(body.tracks) do
			if not raw.title then
				unloaded[#unloaded + 1] = tostring(raw.id)
			else
				loaded[#loaded + 1] = self:buildTrack(raw)
			end
		end

		local playlist_stop = false
		local is_one = false

		while playlist_stop == false do
			if is_one then break end
			local notLoadedLimited
			local filtered

			if #unloaded > 50 then
				notLoadedLimited = mod_table.split(unloaded, 1, 50)
				filtered = mod_table.split(unloaded, 50, #unloaded)
			elseif #unloaded == 1 then
				notLoadedLimited = { unloaded[1] }
				filtered = nil
			else
				notLoadedLimited = mod_table.split(unloaded, 1, #unloaded)
				filtered = mod_table.split(unloaded, #unloaded, #unloaded)
			end

			local unloaded_query_link =
				self._baseUrl
				.. "/tracks"
				.. "?ids=" .. self:merge(notLoadedLimited)
				.. "&client_id=" .. url.encode(self._clientId)
			local unloaded_response, unloaded_res_body = http.request("GET", unloaded_query_link)
			if unloaded_response.code == 200 then
				local unloaded_body = json.decode(unloaded_res_body)
				for key, raw in pairs(unloaded_body) do
					loaded[#loaded + 1] = self:buildTrack(raw)
					unloaded_body[key] = nil
				end
			else end
			if filtered == nil then playlist_stop = true
			elseif #filtered == 0 then playlist_stop = true
			else unloaded = filtered end
			if #unloaded == 1 then is_one = true end
		end

		return {
			loadType = 'playlist',
			info = {
				name = body.title,
				selectedTrack = 0,
			},
			data = { tracks = loaded },
		}
	end

	return {
		loadType = "empty",
    tracks = { nil },
  }
end

function SoundCloud:isLinkMatch(query)
	local check1 = query:match("https?://www%.soundcloud%.com/[^%s]+/[^%s]+")
	local check2 = query:match("https?://soundcloud%.com/[^%s]+/[^%s]+")
	local check3 = query:match("https?://m%.soundcloud%.com/[^%s]+/[^%s]+")
	if check1 or check2 or check3 then return true end
	return false
end

function SoundCloud:merge(unloaded)
	local res = ""

	for i = 1, #unloaded do
		res = res .. unloaded[i]
		if i ~= #unloaded then
			res = res .. "%2C"
		end
	end

	return res
end

function SoundCloud:buildTrack(data)
	local isrc = nil
	if type(data.publisher_metadata) == "table" then
		isrc = data.publisher_metadata.isrc
	end

	local info = {
		title = data.title,
		author = data.user.permalink,
		identifier = tostring(data.id),
		uri = data.permalink_url,
		isStream = false,
		isSeekable = true,
		sourceName = self._sourceName,
		isrc = isrc,
		artworkUrl = data.artwork_url,
		length = data.full_duration,
	}

	return {
		encoded = encoder(info),
		info = info
	}
end

function SoundCloud:loadStream(track, luna)
	local template_link = 'https://api-v2.soundcloud.com/resolve?url=https://api.soundcloud.com/tracks/%s&client_id=%s'
	local response, res_body = http.request("GET", string.format(
		template_link,
		url.encode(track.info.identifier),
		url.encode(self._clientId)
	))
	if response.code ~= 200 then
		print(string.format("[SoundCloud] -> [Error]: Server response error: %s | On link: %s", response.code, track.info.uri))
		return self:buildError(
			"Server response error: " .. response.code,
			"fault", "SoundCloud Source"
		)
	end

	local body = json.decode(res_body)

	if body.errors then
		print("[SoundCloud] -> [Error]: " .. body.errors[1].error_message)
		return self:buildError(
			body.errors[1].error_message,
			"fault", "SoundCloud Source"
		)
	end

	local oggOpus = table.find(body.media.transcodings, function (transcoding)
		return transcoding.format.mime_type == 'audio/ogg; codecs="opus"'
	end)

  local transcoding = oggOpus or body.media.transcodings[0]
	local stream_url = string.format("%s?client_id=%s", transcoding.url, url.encode(self._clientId))

  -- if (transcoding.snipped && config.search.sources.soundcloud.fallbackIfSnipped) {
  --   debugLog('retrieveStream', 4, { type: 3, sourceName: 'SoundCloud', query: title, message: `Track is snipped, falling back to: ${config.search.fallbackSearchSource}.` })

  --   const search = await searchWithDefault(title, true)

  --   if (search.loadType === 'search') {
  --     const urlInfo = await sources.getTrackURL(search.data[0].info)

  --     return {
  --       url: urlInfo.url,
  --       protocol: urlInfo.protocol,
  --       format: urlInfo.format,
  --       additionalData: true
  --     }
  --   }
  -- }

  if transcoding.format.protocol == 'hls' then
		p(stream_url)
    local _, stream_res_body = http.request("GET", stream_url)
		local stream_body = json.decode(stream_res_body)
    stream_url = stream_body.url
	end

  return {
    url = stream_url,
    protocol = transcoding.format.protocol == 'hls' and 'hls_segment' or transcoding.format.protocol,
    format = oggOpus and 'ogg/opus' or 'arbitrary'
  }
end

return SoundCloud