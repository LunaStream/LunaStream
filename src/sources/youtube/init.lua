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
  if src_type == "ytmsearch" then 
    return "music.youtube.com"
  else 
    return "youtubei.googleapis.com"
  end
end
function YouTube:search(query, src_type)
  if src_type == "ytmsearch" then self._clientManager:switchClient('ANDROID_MUSIC') end
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
  if type == "ytmsearch" then
    videos = data.contents.tabbedSearchResultsRenderer.tabs[1].tabRenderer.content.musicSplitViewRenderer.mainContent.sectionListRenderer.contents[0].musicShelfRenderer.contents
  else
    videos = data.contents.sectionListRenderer.contents[#data.contents.sectionListRenderer.contents].itemSectionRenderer.contents
  end
  
  if #videos > config.sources.maxSearchResults then
    videos = { unpack(videos, 1, config.sources.maxSearchResults) }
  end
  if src_type == "ytmsearch" then
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
  
      if type == "ytmsearch" then
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

function YouTube:checkURLType(inp_url, src_type)
  
  local patterns = {
    ytmsearch = {
      video = "https?://music%.youtube%.com/watch%?v=[%w%-]+",
      playlist = "https?://music%.youtube%.com/playlist%?list=[%w%-]+",
      selectedVideo = "https?://music%.youtube%.com/watch%?v=[%w%-]+&list=[%w%-]+"
    },
    default = {
      video = "https?://w?w?w?%.?youtube%.com/watch%?v=[%w%-]+",
      playlist = "https?://w?w?w?%.?youtube%.com/playlist%?list=[%w%-]+",
      selectedVideo = "https?://w?w?w?%.?youtube%.com/watch%?v=[%w%-]+&list=[%w%-]+",
      shorts = "https?://w?w?w?%.?youtube%.com/shorts/[%w%-]+"
    }
  }
  print(src_type)
  local selectedPatterns = patterns[src_type] or patterns.default

  if string.match(inp_url, selectedPatterns.selectedVideo) or string.match(inp_url, selectedPatterns.playlist) then
    return 'playlist'
  elseif src_type ~= 'ytmsearch' and string.match(inp_url, selectedPatterns.shorts) then
    return 'shorts'
  elseif string.match(inp_url, selectedPatterns.video) then
    return 'video'
  else
    return 'invalid'
  end
end


function YouTube:isLinkMatch(query)
  local check_list = {
    ["https?://music%.youtube%.com/watch%?v=[%w%-_]+"] = 'ytmsearch',
    ["https?://music%.youtube%.com/playlist%?list=[%w%-_]+"] = 'ytmsearch',
    ["https?://music%.youtube%.com/watch%?v=[%w%-_]+&list=[%w%-_]+"] = 'ytmsearch',
    ["https?://w?w?w?%.?youtube%.com/watch%?v=[%w%-_]+"] = 'ytsearch',
    ["https?://w?w?w?%.?youtube%.com/playlist%?list=[%w%-_]+"] = 'ytsearch',
    ["https?://w?w?w?%.?youtube%.com/watch%?v=[%w%-_]+&list=[%w%-_]+"] = 'ytsearch',
    ["https?://w?w?w?%.?youtube%.com/shorts/[%w%-_]+"] = 'ytsearch'
}

  for link, additionalData in pairs(check_list) do
    if string.match(query, link) then
      print('Matched link: ' .. link)
      return true, additionalData
    end
  end

  return false, nil
end

function YouTube:loadForm(query, src_type)
  if src_type == "ytmsearch" then self._clientManager:switchClient('ANDROID_MUSIC') end
  if self._clientManager._currentClient ~= "ANDROID" then self._clientManager:switchClient('ANDROID') end

  local urlType = self:checkURLType(query, src_type)

  local formFile = urlType == "video" and "video.lua" or 
                   urlType == "playlist" and "playlist.lua" or 
                   urlType == "shorts" and "shorts.lua"

  if formFile then
    local form = require("./forms/" .. formFile)
    return form(query, src_type, self)
  else
    self:buildError(
      "Unknown URL type",
      "fault", "YouTube Source"
    )

    return {
      loadType = "error",
      data = {},
      error = {
        message = "Unknown URL type",
        severity = "fault",
        source = "YouTube Source"
      }
    }
  end
end


function YouTube:loadStream(track)
  if track.sourceName == "ytmsearch" then self._clientManager:switchClient('ANDROID_MUSIC') end
  if self._clientManager._currentClient ~= "ANDROID" then self._clientManager:switchClient('ANDROID') end

  self._luna.logger:debug('YouTube', 'Loading stream url for ' .. track.info.title)

  local response, data = http.request(
    "POST",
    string.format("https://%s/youtubei/v1/player", self:baseHostRequest(track.info.sourceName)),
    {
      { "User-Agent", self._clientManager.ytContext.client.userAgent },
      { "X-GOOG-API-FORMAT-VERSION", "2" }
    },
    json.encode({
      context = self._clientManager.ytContext,
      videoId = track.info.identifier,
      contentCheckOk = true,
      racyCheckOk = true
    })
)
  if response.code ~= 200 then
    self._luna.logger:error('YouTube', "Server response error: %s | On query: %s", response.code, track.uri)
    return self:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
  end
  
  if not data then
    return {
      exception = {
        message = "No data received from server.",
        severity = "common",
        cause = "Unknown"
      }
    }
  end

  data = json.decode(data)

  if data.playabilityStatus.status ~= "OK" then
    self:buildError(
      "Video is not available",
      "fault", "YouTube Source"
    )

    return {
      loadType = "error",
      data = {},
      error = {
        message = "Video is not available",
        severity = "fault",
        domain = "YouTube Source",
        more = data
      }
    }
  end

  local audio = nil

  local qualityOrder = { "audio/webm; codecs=\"opus\"", "audio/mp4" }
  
  for _, mimeType in ipairs(qualityOrder) do
    for _, format in ipairs(data.streamingData.adaptiveFormats) do
      if format.mimeType == mimeType then
        if not audio or (format.audioQuality and format.audioQuality > (audio.audioQuality or "")) then
          audio = format
        end
      end
    end
  end
  
  if not audio then
    for _, format in ipairs(data.streamingData.adaptiveFormats) do
      if format.mimeType:find("audio/") then
        audio = format
        break
      end
    end
  end
  
  if not audio then
    return {
      exception = {
        message = "No suitable audio format found.",
        severity = "common",
        cause = "Unknown"
      }
    }
  end
  
  local url = audio.url or audio.signatureCipher or audio.cipher
  url = string.format("%s&rn=1&cpn=%s&ratebypass=yes&range=0-", url, string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", math.random(1, 62), math.random(1, 62)))
  
  return {
    url = url,
    format = "webm/opus",
    protocol = "http",
  }
end

return YouTube