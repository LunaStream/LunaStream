local json = require("json")
local http = require("coro-http")
local encoder = require("../../../track/encoder.lua")

return function(query, src_type, youtube)
  local videoId = query:match("shorts/([%w%-_]+)")
  if not videoId then
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Invalid Shorts video ID",
        severity = "common",
        domain = "YouTube Source",
      },
    }
  end

  local success, response, data = pcall(http.request,
    "POST", string.format("https://%s/youtubei/v1/player", youtube:baseHostRequest(src_type)), {
      { "User-Agent", youtube._clientManager.ytContext.client.userAgent },
      { "X-GOOG-API-FORMAT-VERSION", "2" },
      { "Content-Type", "application/json" },
    }, json.encode(
      {
        context = youtube._clientManager.ytContext,
        videoId = videoId,
        contentCheckOk = true,
        racyCheckOk = true,
      }
    )
  )

  if not success then
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Internal error: " .. response,
        severity = "fault",
        domain = "YouTube Source",
      },
    }
  end

  if response.code ~= 200 then
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Server response error: " .. response.code,
        severity = "fault",
        domain = "YouTube Source",
      },
    }
  end

  data = json.decode(data)

  if data.error or data.playabilityStatus.status ~= "OK" then
    return {
      loadType = "error",
      data = {},
      error = {
        message = data.error and data.error.message or data.playabilityStatus.reason or "Video is not available",
        severity = "common",
        domain = "YouTube Source",
      },
    }
  end

  local video = data.videoDetails
  local track = {
    identifier = video.videoId,
    isSeekable = true,
    author = video.author or "Unknown author",
    length = tonumber(video.lengthSeconds) * 1000,
    isStream = video.isLive == true,
    position = 0,
    title = video.title or "Unknown title",
    uri = string.format("https://%s/watch?v=%s", youtube:baseHostRequest(src_type), video.videoId),
    artworkUrl = video.thumbnail and video.thumbnail.thumbnails and
      video.thumbnail.thumbnails[#video.thumbnail.thumbnails].url or nil,
    isrc = nil,
    sourceName = src_type == "ytmsearch" and 'youtube_music' or 'youtube',
  }

  return {
    loadType = "short",
    data = { encoded = encoder(track), info = track, pluginInfo = {} },
  }
end
