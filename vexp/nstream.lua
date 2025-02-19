local timer = require('timer')
local json = require('json')
local fs = require('fs')
local MusicUtils = require('musicutils')
local Voice = require('../src/voice')
local HTTPStream = require('../src/voice/stream/HTTPStream')
local stream_link = 'https://raw.githubusercontent.com/LunaStream/StreamEmulator/refs/heads/main/livetune_decorator.weba'
local large_stream_link = 'https://media.githubusercontent.com/media/LunaStream/StreamEmulator/refs/heads/main/large_audio_100mb.webm'

local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

VoiceClass:connect()

p('[Voice EXP]: Song will play after 5s')

local function playfunction()
  p('[Voice EXP]: Now play the song from github stream ' .. (process.argv[2] and 'large_stream_link' or 'stream_link'))

  local streamClient = HTTPStream:new('GET', process.argv[2] and large_stream_link or stream_link)
  local requestStream = streamClient:setup()

  p('HTTP Response: ', requestStream.reponse)

  local audioStream = requestStream
    :pipe(MusicUtils.opus.WebmDemuxer:new())
    :pipe(MusicUtils.opus.Decoder:new(VoiceClass._opus))

  VoiceClass:play(audioStream, { encoder = true })
end

setTimeout(5000, coroutine.wrap(playfunction))