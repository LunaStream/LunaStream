local timer = require('timer')
local json = require('json')
local fs = require('fs')
local MusicUtils = require('musicutils')
local Voice = require('../src/voice')
local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

VoiceClass:connect()

local audioStream = fs.createReadStream('./vexp/videoplayback.weba')
  :pipe(MusicUtils.opus.WebmDemuxer:new())
  :pipe(MusicUtils.opus.Decoder:new(VoiceClass._opus))

setTimeout(7000, coroutine.wrap(function()
  p('Voice EXP: Now play the song')
  VoiceClass:play(audioStream, MusicUtils.core.PCMStream, true)
end))
