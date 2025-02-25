local MusicUtils = require('musicutils')
local audioDecoder = require('audioDecoder')

local HTTPStream = require('../../src/voice/stream/HTTPStream')

local stream_link = 'https://media.githubusercontent.com/media/LunaStream/StreamEmulator/refs/heads/main/large_audio_100mb.webm'

return function (vdk)
  local streamClient = HTTPStream:new('GET', stream_link)
  local requestStream = streamClient:setup()
  local code = requestStream.res and requestStream.res.code or 'nil'
  local reason = requestStream.res and requestStream.res.reason or 'nil'
  local version = requestStream.res and requestStream.res.version or 'nil'
  local keepAlive = requestStream.res and requestStream.res.keepAlive or 'nil'

  vdk:log(false, '[HTTPStream]: HTTP/%s %s %s | keepAlive: %s ', version, code, reason, keepAlive)

  if code ~= 200 then return end

  vdk:log(false, 'Song Infomation: 11h whale sound, mode: stream')

  -- requestStream:on('ECONNREFUSED', function ()
  --   p('[HTTPStream]: Connection terminated')
  -- end)

  local audioStream = requestStream
    :pipe(MusicUtils.opus.WebmDemuxer:new())
    :pipe(audioDecoder.opus:new(vdk._voice._opus))

  return audioStream
end