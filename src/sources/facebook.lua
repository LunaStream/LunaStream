local http = require("coro-http")
local json = require("json")
local urlp = require("url-param")
local AbstractSource = require("./abstract.lua")
local encoder = require("../track/encoder.lua")
local class = require("class")

local Facebook = class("Facebook", AbstractSource)

function Facebook:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._fbDtsg = "NAcPWRAQL_JK04EqKpK47rWAOHyYkil074n_u9w_hPxxwvZDPf6Y-zQ%3A32%3A1738776640" -- change if it expires (or leave it to config.facebook.fbDtsg - still under analysis if this expires)
end

function Facebook:setup()
  self._luna.logger:info('Facebook', 'Registered [Facebook] video source manager')
  return self
end

function Facebook:search(query)
  return self:buildError("Search not supported for Facebook", "fault", "Facebook Source")
end

function Facebook:getVideoId(url)
  if not url then return nil, "Facebook URL not provided" end
  
  local patterns = {
    "facebook%.com/watch%?v=(%d+)",
    "fb%.watch/(%w+)",
    "facebook%.com/reel/(%d+)",
    "facebook%.com/.+/videos/(%d+)"
  }
  
  for _, pattern in ipairs(patterns) do
    local videoId = url:match(pattern)
    if videoId then return videoId end
  end
  
  return nil, "Facebook video ID not found"
end
function Facebook:encodeGraphQLRequest(videoId)
    local variables = {
      UFI2CommentsProvider_commentsKey = "CometTahoeSidePaneQuery",
      caller = "CHANNEL_VIEW_FROM_PAGE_TIMELINE",
      displayCommentsContextEnableComment = json.null,
      displayCommentsContextIsAdPreview = json.null,
      displayCommentsContextIsAggregatedShare = json.null,
      displayCommentsContextIsStorySet = json.null,
      displayCommentsFeedbackContext = json.null,
      feedbackSource = 41,
      feedLocation = "TAHOE",
      focusCommentID = json.null,
      privacySelectorRenderLocation = "COMET_STREAM",
      renderLocation = "video_channel",
      scale = 1,
      streamChainingSection = false,
      useDefaultActor = false,
      videoChainingContext = json.null,
      videoID = videoId
    }
  
    local params = {
      doc_id = "5279476072161634",
      variables = json.encode(variables),
      fb_dtsg = self._fbDtsg,
      server_timestamps = "true"
    }
  
    local encoded = {}
    for key, value in pairs(params) do
      table.insert(encoded, self:urlEncode(key) .. "=" .. self:urlEncode(value))
    end
    
    return table.concat(encoded, "&")
  end
  
  function Facebook:urlEncode(str)
    if not str then return "" end
    return (str:gsub("([^%w%-%.%_%~ ])", function(c)
      return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
  end

function Facebook:isLinkMatch(link)
  return link:match("facebook%.com") ~= nil or link:match("fb%.watch") ~= nil
end

function Facebook:fetchVideoData(videoId, timeout)
  if not videoId then return nil, "Video ID not provided" end

  local API_URL = "https://www.facebook.com/api/graphql/"
  local headers = {
    { "Accept", "*/*" },
    { "Content-Type", "application/x-www-form-urlencoded" },
    { "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36" },
    { "X-FB-Friendly-Name", "CometTahoeSidePaneQuery" },
    { "Sec-Fetch-Site", "same-origin" },
    { "Sec-Fetch-Mode", "cors" },
    { "Sec-Fetch-Dest", "empty" },
    { "Referer", "https://www.facebook.com/" },
  }

  local body = self:encodeGraphQLRequest(videoId)
  local response, resBody = http.request("POST", API_URL, headers, body)

  if response.code ~= 200 then
    return nil, "Request failed with code " .. response.code
  end

  local data = json.decode(resBody)

  if not data or not data.data or not data.data.video then
    return nil, "Invalid response from Facebook API"
  end

  local videoInfo = data.data.video
  local videoUrl = videoInfo.playable_url_quality_hd or videoInfo.playable_url

  if not videoUrl then
    return nil, "Video URL not found"
  end

  local author = videoInfo.permalink_url:match("facebook%.com/([%w%.]+)/videos/%d+")
    local isStream = false
  if videoInfo.is_live_streaming then
    isStream = true
  end
  return {
    videoUrl = videoUrl,
    author = author or videoInfo.owner.id or "User Unknown",
    length = math.floor(videoInfo.playable_duration_in_ms or 0),
    thumbnail = videoInfo.preferred_thumbnail.image.uri or nil,
    title = videoInfo.title or "Facebook Video",
    isStream = isStream
  }
end

function Facebook:loadForm(query)
  local videoId, err = self:getVideoId(query)
  if not videoId then
    return self:buildError(err or "Invalid Facebook URL", "fault", "Facebook Source")
  end

  local videoData, err = self:fetchVideoData(videoId)
  if not videoData then
    return self:buildError(err or "Video not available", "fault", "Facebook Source")
  end
  
  local trackInfo = {
    identifier = videoId,
    title = videoData.title,
    author = videoData.author,
    length = videoData.length,
    sourceName = "Facebook",
    artworkUrl = videoData.thumbnail,
    uri = query,
    isStream = videoData.isStream,
    isSeekable = videoData.isStream and false or true,
    isrc = nil
  }

  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {}
  }

  return { 
    loadType = "track",
    data = track
  }
end

function Facebook:loadStream(track)
  if track.info.isStream then
    return self:buildError("Live streams are not supported", "fault", "Facebook Source")
  end

  local videoData, err = self:fetchVideoData(track.info.identifier)
  if not videoData then
    return self:buildError(err or "Video not found", "fault", "Facebook Source")
  end

  return {
    url = videoData.videoUrl,
    format = "mp4",
    protocol = "http"
  }
end

return Facebook
