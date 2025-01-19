local http = require("coro-http")
local urlp = require("url-param")
local url = require("url")
local json = require("json")

local AbstractSource = require('../abstract.lua')
local YouTubeClientManager = require('./ClientManager.lua')
local encoder = require("../../track/encoder.lua")

local class = require('class')

local YouTube = class('YouTube', AbstractSource)

function YouTube:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._clientManager = YouTubeClientManager(luna):setup()
  self._ytContext = self._clientManager.ytContext
end

function YouTube:setup()
  return self
end

function YouTube:getBaseHostRequest(type)
  if string.match(self._ytContext.client.clientName, 'ANDROID') then
    return 'youtubei.googleapis.com'
  end

  return (type == 'ytmsearch' and 'music' or 'www') .. '.youtube.com'
end

function YouTube:getBaseHost(type)
  return (type == 'ytmsearch' and 'music' or 'www') .. '.youtube.com'
end

function YouTube:search(query, type)
  local config = self._luna.config

  self._luna.logger:debug('Youtube', 'Searching: ' .. query)

  if not config.sources.youtube.bypassAgeRestriction then
    self._clientManager:switchClient(type == 'ytmsearch' and 'ANDROID_MUSIC' or 'ANDROID')
  end

  local response, search = http.request(
    "POST",
    string.format('https://%s/youtubei/v1/search', self:getBaseHostRequest(type)),
    {
      { 'User-Agent', self._ytContext.client.userAgent },
      { 'X-GOOG-API-FORMAT-VERSION', 2 },
      table.unpack(self._clientManager.additionalHeaders)
    },
    json.encode({
      context = self._ytContext,
      query = query,
      params = (type == 'ytmsearch' and (not config.sources.youtube.bypassAgeRestriction))
        and 'EgWKAQIIAWoQEAMQBBAJEAoQBRAREBAQFQ%3D%3D' or  'EgIQAQ%3D%3D'
    })
  )

  if response.code ~= 200 then
		self._luna.logger:error('Youtube', "Server response error: %s | On query: %s", response.code, query)
		return self:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
	end

  search = json.decode(search)

  if not search then
    self._luna.logger:error('Youtube', "Failed to load results.")
		return self:buildError(
      "Failed to load results.",
      "common", "YouTube Source"
    )
  end

  if search.error then
    self._luna.logger:error('Youtube', search.error.message)
		return self:buildError(
      search.error.message,
      "fault", "YouTube Source"
    )
  end

  local tracks = {}

  local videos = nil

  if config.sources.youtube.bypassAgeRestriction then
    if type == 'ytmsearch' then
      _, videos = pcall(function ()
        return search.contents.sectionListRenderer.contents[1].itemSectionRenderer.contents
      end)
    else
      _, videos = pcall(function ()
        local lastIndex = #search.contents.sectionListRenderer.contents
        return search.contents.sectionListRenderer.contents[lastIndex].itemSectionRenderer.contents
      end)
    end
  else
    if type == 'ytmsearch' then
      _, videos = pcall(function ()
        local tabs = search.contents.tabbedSearchResultsRenderer.tabs
        return tabs[1].tabRenderer.content.musicSplitViewRenderer.mainContent.sectionListRenderer.contents[1].musicShelfRenderer.contents
      end)
    else
      _, videos = pcall(function ()
        local lastIndex = #search.contents.sectionListRenderer.contents
        return search.contents.sectionListRenderer.contents[lastIndex].itemSectionRenderer.contents
      end)
    end
  end

  if not videos or #videos == 0 then
    self._luna.logger:error('Youtube', 'No matches found.')
		return self:buildError(
      'No matches found.',
      "fault", "YouTube Source"
    )
  end

  if #videos > config.sources.maxSearchResults then
    local i = 0
    videos = table.filter(videos, function (video)
      if (video.compactVideoRenderer or video.musicTwoColumnItemRenderer) and i < config.options.maxSearchResults then
        i = i + 1
        table.insert(filteredVideos, video)
      end
    end)
  end

  for _, video in pairs(videos) do
    video = video.compactVideoRenderer or video.musicTwoColumnItemRenderer

    if not video then goto continue end

    local identifier = type == 'ytmsearch' and video.navigationEndpoint.watchEndpoint.videoId or video.videoId
    local thumbnails = (type == 'ytmsearch' and not config.sources.youtube.bypassAgeRestriction)
      and video.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails or video.thumbnail.thumbnails


    local length
    if type == 'ytmsearch' and not config.sources.youtube.bypassAgeRestriction then
      length = video.subtitle.runs[2].text
    else
      _, length = pcall(function () return video.lengthText.runs[1].text end)
    end

    local parts = {}
    for part in string.gmatch(length, "([^:]+)") do
      table.insert(parts, part)
    end

    local minutes = tonumber(parts[1]) * 60
    local seconds = tonumber(parts[2])

    local totalSeconds = minutes + seconds

    local track = {
      identifier = identifier,
      isSeekabl = true,
      author = video.longBylineText and video.longBylineText.runs[1].text or video.subtitle.runs[1].text,
      length = length and totalSeconds * 1000 or 0,
      isStream = length ~= 0,
      position = 0,
      title = video.title.runs[1].text,
      uri =  string.format('https://%s/watch?v=%s', self:getBaseHost(type), identifier),
      artworkUrl = thumbnails[#thumbnails].url:match("([^?]+)"),
      isrc = nil,
      sourceName = type and 'ytmusic' or 'youtube'
    }

    table.insert(tracks, {
      encoded = encoder(track),
      info = track,
      pluginInfo = {}
    })

    ::continue::
  end

  if (#tracks == 0) then
    self._luna.logger:error('Youtube', 'No matches found.')

    return {
      loadType = 'empty',
      data = {}
    }
  end

	self._luna.logger:debug('YouTube', 'Found results for %s: ' .. #tracks, query)

  return {
    loadType = 'search',
    data = tracks
  }
end

function YouTube:isLinkMatch(query)
end

function YouTube:loadForm(query)
end

function YouTube:loadStream(track, additionalData)
end

return YouTube