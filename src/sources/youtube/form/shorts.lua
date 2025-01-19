local http = require("coro-http")
local json = require("json")

local encoder = require("../../../track/encoder.lua")

return function (source, query, src_type)
  local response, short = http.request(
    "POST",
    string.format('https://%s/youtubei/v1/player', source:getBaseHostRequest(src_type)), {},
    json.encode({
      context = source._ytContext,
      videoId = query:match("shorts/([a-zA-Z0-9_-]+)"),
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

  short = json.decode(short)

  if short.error then
    source._luna.logger:error('Youtube', short.error.message)
    return source:buildError(
      short.error.message,
      "fault", "YouTube Source"
    )
  end

  if short.playabilityStatus.status ~= 'OK' then
    local errorMessage = short.playabilityStatus.reason or short.playabilityStatus.messages[1]
    source._luna.logger:error('Youtube', errorMessage)
    return source:buildError(
      short.error.message,
      "common", errorMessage
    )
  end

  local track = {
    identifier = short.videoDetails.videoId,
    isSeekable = true,
    author = short.videoDetails.author,
    length = tonumber(short.videoDetails.lengthSeconds) * 1000,
    isStream = false,
    position = 0,
    title = short.videoDetails.title,
    uri = string.format('https://%s/watch?v=%s', source:getBaseHost(src_type), short.videoDetails.videoId),
    artworkUrl = short.videoDetails.thumbnail.thumbnails[#short.videoDetails.thumbnail.thumbnails].url,
    isrc = nil,
    sourceName = 'youtube'
  }

  source._luna.logger:debug(
    'YouTube',
    'Loaded short %s by %s from %s',
    track.info.title,
    track.info.author,
    query
  )

  return {
    loadType = 'short',
    data = {
      encoded = encoder(track),
      info = track,
      pluginInfo = {}
    }
  }
end
