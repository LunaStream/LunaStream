local http = require("coro-http")
local json = require("json")
local param = require("url-param")
local config = require("../../utils/config")

local AbstractSource = require('../abstract.lua')
local YouTubeClientManager = require('./ClientManager.lua')
local encoder = require("../../track/encoder.lua")

local class = require('class')

local YouTube = class('YouTube', AbstractSource)

function YouTube:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._clientManager = YouTubeClientManager(luna):setup()
end

function YouTube:setup()
  return self
end
function YouTube:baseHostRequest(src_type)
  if src_type == "ytmusic" then 
    return "music.youtube.com"
  else 
    return "youtubei.googleapis.com"
  end
end
function YouTube:search(query, src_type)
  if src_type == "ytmusic" then self._clientManager:switchClient('ANDROID_MUSIC') end
  if self._clientManager._currentClient ~= "ANDROID" then self._clientManager:switchClient('ANDROID') end
  self._luna.logger:debug('YouTube', 'Searching: ' .. query)

  local response, data = http.request(
    "POST",
    string.format("https://%s/youtubei/v1/search", self:baseHostRequest(src_type)),
    {
      { "User-Agent", self._clientManager.ytContext.userAgent },
      { "X-GOOG-API-FORMAT-VERSION", "2" },
      { "Content-Type", "application/json" }
    },
    json.encode({
      context = self._clientManager.ytContext,
      query = query
    })
  )

  if response.code ~= 200 then
    self._luna.logger:error('YouTube', "Server response error: %s | On query: %s", response.code, query)
    return self:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
  end
  local tracks = {}
  data = json.decode(data)
  
  local videos
  local baseUrl
  if type == "ytmusic" then
    videos = data.contents.tabbedSearchResultsRenderer.tabs[1].tabRenderer.content.musicSplitViewRenderer.mainContent.sectionListRenderer.contents[0].musicShelfRenderer.contents
  else
    videos = data.contents.sectionListRenderer.contents[#data.contents.sectionListRenderer.contents].itemSectionRenderer.contents
  end
  
  if #videos > config.sources.maxSearchResults then
    videos = { unpack(videos, 1, config.sources.maxSearchResults) }
  end
  if src_type == "ytmusic" then
    baseUrl = "music.youtube.com"
  else
    baseUrl = "youtube.com"
  end
  for _, video in ipairs(videos) do
    video = video.compactVideoRenderer or video.musicTwoColumnItemRenderer
  
    if video then
      local identifier
      local length
      local thumbnails
  
      if type == "ytmusic" then
        identifier = video.navigationEndpoint.watchEndpoint.videoId
        length = video.subtitle and video.subtitle.runs[3] and video.subtitle.runs[3].text or video.lengthText and video.lengthText.runs[1] and video.lengthText.runs[1].text
        thumbnails = video.thumbnail and video.thumbnail.musicThumbnailRenderer and video.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails or video.thumbnail.thumbnails
      else
        identifier = video.videoId
        length = video.lengthText and video.lengthText.runs[1] and video.lengthText.runs[1].text or nil
        thumbnails = video.thumbnail.thumbnails
      end
      
      local lengthInSeconds = 0
    if length then
      local minutes, seconds = length:match("(%d+):(%d+)")
      if minutes and seconds then
        lengthInSeconds = tonumber(minutes) * 60 + tonumber(seconds)
      end
    end
      print(lengthInSeconds)
      local track = {
        identifier = identifier,
        isSeekable = true,
        author = video.longBylineText and video.longBylineText.runs[1] and video.longBylineText.runs[1].text or video.subtitle.runs[1].text,
        length = lengthInSeconds * 1000 or 0,
        isStream = not length,
        position = 0,
        title = video.title.runs[1] and video.title.runs[1].text or "",
        uri = string.format("https://%s/watch?v=%s", baseUrl, identifier),
        artworkUrl = thumbnails[#thumbnails].url:match("(.-)%?"),
        isrc = nil,
        sourceName = src_type
      }
      for _, v in pairs(track) do
        print(_, v)
      end
      table.insert(tracks, {
        encoded = encoder(track),
        info = track,
        pluginInfo = {}
      })
    end
  end  
  if #tracks == 0 then
    self:buildError(
      "No results found",
      "fault", "YouTube Source"
    )

    return {
      loadType = "empty",
      data = {}
    }

  end

  return {
    loadType = "search",
    data = tracks
  }

end



function YouTube:checkURLType(inp_url) 
end

function YouTube:loadForm(query, src_type)
end

function YouTube:loadStream(track, additionalData)
end

return YouTube