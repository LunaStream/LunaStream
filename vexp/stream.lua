local timer = require('timer')
local json = require('json')
local fs = require('fs')
local MusicUtils = require('musicutils')
local Voice = require('../src/voice')
local HTTPStream = require('../src/voice/stream/HTTPStream')
local http = require("coro-http")
local stream_link = 'https://raw.githubusercontent.com/LunaStream/LunaStream/add/voice/vexp/videoplayback.weba'

local response, data = http.request("GET", stream_link)
p('HTTP Response: ', response)

local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

VoiceClass:connect()

p('[Voice EXP]: Song will play after 5s')

setTimeout(5000, coroutine.wrap(function()
  p('[Voice EXP]: Now play the song from github stream')
  local audioStream = HTTPStream:new(data)
    :pipe(MusicUtils.opus.WebmDemuxer:new())
    :pipe(MusicUtils.opus.Decoder:new(VoiceClass._opus))
  VoiceClass:play(audioStream, {
    encoder = true,
    -- filters = { Filter() }
  })
end))