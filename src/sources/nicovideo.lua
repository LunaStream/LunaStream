local http = require("coro-http")
local urlp = require("url-param")
local json = require("json")

local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")

local class = require('class')

local NicoVideo = class('NicoVideo', AbstractSource)

function NicoVideo:__init(luna)
  self._luna = luna
  self._search_id = 'ncsearch'
end

function NicoVideo:buildOutputData(fulldata)
  local response_json = fulldata.data.response

  local quality = { "1080p", "720p", "480p", "360p", "144p" }
  local outputs = {}
  local top_audio_id = nil
  local top_audio_quality = -1

  for _, audio in pairs(response_json.media.domand.audios) do
    if audio.isAvailable and audio.qualityLevel > top_audio_quality then
      top_audio_id = audio.id
      top_audio_quality = audio.qualityLevel
    end
  end

  if not top_audio_id then
    return outputs
  end

  for _, video in pairs(response_json.media.domand.videos) do
    if not table.includes(quality, video.label) then
      goto continue
    end
    if video.isAvailable then
      table.insert(outputs, { video.id, top_audio_id })
    end
    ::continue::
  end

  return outputs
end

function NicoVideo:buildHeaders(rightKey)
  return {
    { "User-Agent", "LunaStream" },
    { "X-Request-With", "https://www.nicovideo.jp" },
    { "Referer", "https://www.nicovideo.jp/" },
    { "X-Frontend-Id", 6 },
    { "X-Frontend-Version", 0 },
    rightKey and { "x-access-right-key", rightKey } or nil,
  }
end

function NicoVideo:buildParam(params)
  local first_time = true

  local str = ''

  for key, value in pairs(params) do
    local new_key = urlp.encode(tostring(key))
    local new_value = urlp.encode(tostring(value))

    local processed = new_key .. '=' .. new_value
    if first_time then
      str = str .. processed
      first_time = false
    else
      str = str .. '&' .. processed
    end
  end

  return str
end

function NicoVideo:setup()
  return self
end

function NicoVideo:search(query)
  self._luna.logger:debug('NicoVideo', 'Searching: ' .. query)
  local params = {
    keyword = query,
    sortKey = 'hot',
    sortOrder = 'none',
    pageSize = 25,
    page = 1,
    allowFutureContents = true,
    searchByUser = false,
    sensitiveContent = 'mask',
  }

  params = self:buildParam(params)

  local success, search_res, fulldata = pcall(http.request,
    "GET", 'https://nvapi.nicovideo.jp/v2/search/video?' .. params, self:buildHeaders()
  )

  if not success then
    self._luna.logger:error('NicoVideo', "Internal error: %s", search_res)
    return self:buildError("Internal error: " .. search_res, "fault", "NicoVideo Source")
  end

  if search_res.code ~= 200 then
    self._luna.logger:error('NicoVideo', "Server response error: %s | On query: %s", search_res.code, query)
    return self:buildError("Server response error: " .. search_res.code, "fault", "NicoVideo Source")
  end

  fulldata = json.decode(fulldata)

  local tracks = {}

  for _, item in pairs(fulldata.data.items) do
    local track = {
      identifier = item.id,
      isSeekable = true,
      author = item.owner.name,
      length = item.duration * 1000,
      isStream = false,
      position = 0,
      title = item.title,
      uri = 'https://www.nicovideo.jp/watch/' .. item.id,
      artworkUrl = item.thumbnail.url,
      isrc = nil,
      sourceName = 'nicovideo',
    }

    table.insert(
      tracks, { encoded = encoder(track), info = track, pluginInfo = {} }
    )
  end

  self._luna.logger:debug('NicoVideo', 'Found results for %s: ' .. #tracks, query)

  return { loadType = #tracks == 0 and 'empty' or "search", data = tracks }
end

function NicoVideo:isLinkMatch(query)
  return query:match("https?://(.-)%.nicovideo%.jp")
end

function NicoVideo:loadForm(query)
  self._luna.logger:debug('NicoVideo', 'Loading url: ' .. query)

  local success, track_res, fulldata = pcall(http.request, "GET", query .. '?responseType=json', self:buildHeaders())

  if not success then
    self._luna.logger:error('NicoVideo', "Internal error: %s", track_res)
    return self:buildError("Internal error: " .. track_res, "fault", "NicoVideo Source")
  end

  if track_res.code ~= 200 then
    self._luna.logger:error('NicoVideo', "Server response error: %s | On query: %s", track_res.code, query)
    return self:buildError("Server response error: " .. track_res.code, "fault", "NicoVideo Source")
  end

  fulldata = json.decode(fulldata)

  local track_info = table.filter(
                       fulldata.data.metadata.jsonLds, function(data)
      return data['@type'] == "VideoObject"
    end
                     )[1]

  local track = {
    identifier = fulldata.data.response.client.watchId,
    isSeekable = true,
    author = track_info.author.name,
    length = 320948,
    isStream = false,
    position = 0,
    title = track_info.name,
    uri = track_info['@id'],
    artworkUrl = track_info.thumbnail[1].url,
    isrc = nil,
    sourceName = 'nicovideo',
  }

  self._luna.logger:debug('NicoVideo', 'Loaded track %s by %s from %s', track.title, track.author, query)

  return {
    loadType = 'track',
    data = { encoded = encoder(track), info = track, pluginInfo = {} },
  }
end

function NicoVideo:loadStream(track)
  local success, track_res, fulldata = pcall(http.request, "GET", track.info.uri .. '?responseType=json', self:buildHeaders())

  if not success then
    self._luna.logger:error('NicoVideo', "Internal error: %s", track_res)
    return self:buildError("Internal error: " .. track_res, "fault", "NicoVideo Source")
  end

  if track_res.code ~= 200 then
    self._luna.logger:error('NicoVideo', "Server response error: %s | On query: %s", track_res.code, track.info.uri)
    return self:buildError("Server response error: " .. track_res.code, "fault", "NicoVideo Source")
  end

  fulldata = json.decode(fulldata)

  local response = fulldata.data.response

  local request_stream_link = string.format(
    'https://nvapi.nicovideo.jp/v1/watch/%s/access-rights/hls?actionTrackId=%s&__retry=1', track.info.identifier,
      urlp.encode(response.client.watchTrackId)
  )

  local success, stream_res, stream_data = pcall(http.request,
    "POST", request_stream_link, self:buildHeaders(response.media.domand.accessRightKey),
      json.encode({ outputs = self:buildOutputData(fulldata) })
  )

  if not success then
    self._luna.logger:error('NicoVideo', "Internal error: %s", stream_res)
    return self:buildError("Internal error: " .. stream_res, "fault", "NicoVideo Source")
  end

  if stream_res.code ~= 201 then
    self._luna.logger:error('NicoVideo', "Server response error: %s | On query: %s", stream_res.code, track.info.uri)
    return self:buildError("Server response error: " .. stream_res.code, "fault", "NicoVideo Source")
  end

  local stream_res_cookie = table.find(
    stream_res, function(res)
      if type(res) == "table" and string.lower(res[1]) == 'set-cookie' then
        return true
      end
    end
  )

  stream_data = json.decode(stream_data)

  self._luna.logger:debug('NicoVideo', 'Loading stream url success')

  return {
    url = stream_data.data.contentUrl,
    protocol = 'hls',
    type = 'segment',
    format = 'mp4', -- IDK about this format,
    auth = { headers = { { 'cookie', stream_res_cookie[2] } } },
    keepAlive = true
  }
end

return NicoVideo
