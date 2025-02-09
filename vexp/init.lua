local timer = require('timer')
local json = require('json')
local fs = require('fs')
local PcmString = require('./PcmString')
local Voice = require('../src/voice')
local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

local file = io.open('./vexp/heart_waves_48000_stereo.pcm', 'rb')

if not file then
  print('File not found')
  return
end

local audioStream = PcmString(file:read('*all'))
-- file:close()
VoiceClass:connect()

p('[Voice exp SDK]: Song will play after 7s')

setTimeout(7000, coroutine.wrap(function()
  VoiceClass:play(audioStream, true)
end))
