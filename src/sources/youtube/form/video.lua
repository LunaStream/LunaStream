local http = require("coro-http")
local json = require("json")

local encoder = require("../../../track/encoder.lua")

return function (source, query, src_type)
  local identifier = query:match("[?&]v=(...........)")
    or query:match("youtu%.be/([^?]+)")

  local response, video = http.request(
    "POST",
    string.format('https://%s/youtubei/v1/player', source:getBaseHostRequest(src_type)), {},
    json.encode({
      context = source._ytContext,
      videoId = identifier,
      contentCheckOk = true,
      racyCheckOk = true
    })
  )

  if response.code ~= 200 then
    source._luna.logger:error('Youtube', "Server response error: %s | On query: %s", response.code, query)
    return source:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
  end

  video = json.decode(video)

  if video.error then
    source._luna.logger:error('Youtube', video.error.message)
    return source:buildError(
      video.error.message,
      "fault", "YouTube Source"
    )
  end

  if video.playabilityStatus.status ~= 'OK' then
    local errorMessage = video.playabilityStatus.reason or video.playabilityStatus.messages[1]
    source._luna.logger:error('Youtube', errorMessage)
    return source:buildError(
      errorMessage,
      "common", "YouTube Source"
    )
  end

  local track = {
    identifier = video.videoDetails.videoId,
    isSeekable = true,
    author = video.videoDetails.author,
    length = tonumber(video.videoDetails.lengthSeconds) * 1000,
    isStream = video.videoDetails.isLive and true or false,
    position = 0,
    title = video.videoDetails.title,
    uri = string.format('https://%s/watch?v=%s', source:getBaseHost(src_type), video.videoDetails.videoId),
    artworkUrl = video.videoDetails.thumbnail.thumbnails[#video.videoDetails.thumbnail.thumbnails].url,
    isrc = nil,
    sourceName = src_type and 'ytmusic' or 'youtube'
  }

  source._luna.logger:debug(
    'YouTube',
    'Loaded track %s by %s from %s',
    track.title,
    track.author,
    query
  )

  return {
    loadType = 'track',
    data = {
      encoded = encoder(track),
      info = track,
      pluginInfo = {}
    }
  }
end
