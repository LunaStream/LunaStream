local json = require("json")
local http = require("coro-http")
local encoder = require("../../../track/encoder.lua")

return function(query, src_type, youtube)
  local videoId = query:match("v=([%w%-]+)")
  local response, data = http.request(
    "POST",
    string.format("https://%s/youtubei/v1/player", youtube:baseHostRequest(src_type)),
    {
      { "User-Agent", youtube._clientManager.ytContext.client.userAgent },
      { "X-GOOG-API-FORMAT-VERSION", "2" }
    },
    json.encode({
      context = youtube._clientManager.ytContext,
      videoId = videoId,
      contentCheckOk = true,
      racyCheckOk = true
    })
)


  if response.code ~= 200 then
    youtube._luna.logger:error('YouTube', "Server response error: %s | On query: %s", response.code, query)
    return youtube:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
  end

  data = json.decode(data)

  if data.playabilityStatus.status ~= "OK" then
    youtube:buildError(
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

  local video = data.videoDetails
  
  local track = {
    identifier = video.videoId,
    isSeekable = true,
    author = video.author,
    length = tonumber(video.lengthSeconds) * 1000,
    isStream = video.isLive == true,
    position = 0,
    title = video.title,
    uri = string.format("https://%s/watch?v=%s", youtube:baseHostRequest(src_type), video.videoId),
    artworkUrl = video.thumbnail.thumbnails[#video.thumbnail.thumbnails].url,
    isrc = nil,
    sourceName = src_type == "ytmsearch" and 'youtube_music' or 'youtube'
  }

  return {
    loadType = 'track',
    data = {
      encoded = encoder(track),
      info = track,
      pluginInfo = {}
    }
  }
end
