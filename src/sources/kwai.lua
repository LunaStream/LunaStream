local http = require("coro-http")
local json = require("json")
local urlp = require("url-param")
local AbstractSource = require("./abstract.lua")
local encoder = require("../track/encoder.lua")
local class = require("class")

local Kwai = class("Kwai", AbstractSource)

function decode_unicode_escapes(str)
  if not str then
    return nil
  end
  return str:gsub(
    "\\u(%x%x%x%x)", function(code)
      return utf8.char(tonumber(code, 16))
    end
  )
end

function Kwai:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
end

function Kwai:setup()
  return self
end

function Kwai:isLinkMatch(link)
  return link:match("kwai%.com")
end

function Kwai:getVideoId(url)
  if not url then
    return nil, "Kwai URL not provided"
  end
  local videoId = url:match(".*/video/(%d+)")
  if not videoId then
    return nil, "Kwai video ID not found"
  end
  return videoId
end

function Kwai:getVideoInfo(videoId)
  local url = "https://www.kwai.com/video/" .. videoId .. "?responseType=json"
  local headers = {
    {
      "User-Agent",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3",
    },
    { "Accept", "*/*" },
  }
  local success, response, body = pcall(http.request, "GET", url, headers)

  if not success then
    return nil, "Internal error: " .. response
  end

  if response.code ~= 200 then
    return nil, "Request failed with code " .. response.code
  end

  if not body then
    return nil, "error fetching video info"
  end
  local url = body:match('share_info:c,main_mv_urls:%s*%[(.-)%]')
  local videoInfo = {
    author = body:match('kwai_id%s*:%s*"([^"]+)"'),
    title = string.format("Kwai - %s", body:match('kwai_id%s*:%s*"([^"]+)"')),
    lenght = body:match('duration:%s*([%d]+)'),
    thumbnail = decode_unicode_escapes(body:match('cover_thumbnail_urls%:%[%{cdn%:p%,url:%s*"([^"]+)"')),
    videoUrl = decode_unicode_escapes(url:match('url:%s*"([^"]+)"')),
  }

  return videoInfo
end
function Kwai:search(query)
  return self:buildError("Search not supported for Instagram", "fault", "Instagram Source")
end

function Kwai:loadForm(query)
  local videoId, err = self:getVideoId(query)
  if not videoId then
    return self:buildError(err or "Invalid Kwai URL", "fault", "Kwai Source")
  end

  local videoData, err = self:getVideoInfo(videoId)
  if not videoData then
    return self:buildError(err or "Video not available", "fault", "Kwai Source")
  end

  local track = {
    title = videoData.title,
    author = videoData.author,
    length = videoData.lenght,
    thumbnail = videoData.thumbnail,
    uri = query,
    sourceName = "kwai",
    identifier = videoId,
    isStream = false,
    isSeekable = true,
    isrc = nil,
  }
  return {
    loadType = "track",
    data = { encoded = encoder(track), info = track, pluginInfo = {} },
  }
end

function Kwai:loadStream(track)
  local url = self:getVideoInfo(track.info.identifier).videoUrl

  if not url then
    return self:buildError("Video URL not found", "fault", "Kwai Source")
  end

  return { url = url, format = "mp4", protocol = "http", keepAlive = true }
end

return Kwai
