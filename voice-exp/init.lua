-- From https://github.com/SinisterRectus/Discordia
local PCMString = require('voice-exp.xyz')
local Voice = require('../src/voice')
-- {"voice":{"token":"677ca788b33af9e9","endpoint":"india10010.discord.media:443","sessionId":"112235d73f3fb50faca089d2f70d0a6d"}}
local VoiceClass = Voice('813815427892641832', "1120309844117815326")

VoiceClass:voiceCredential(
  "112235d73f3fb50faca089d2f70d0a6d",
  'india10010.discord.media:443',
  "677ca788b33af9e9"
)

VoiceClass:connect()

local timer = require('timer')

timer.setTimeout(15000, coroutine.wrap(function ()
  print("play timeout triggered, playing")

  local file = io.open('sample-1.wav', 'rb')
  if not file then
    print("file not found")
    return
  end
  file:seek('set', 44); -- skip the header
  local pcmSting = PCMString(file:read('*all'))
  print(file.length)
  VoiceClass:play(pcmSting)
end))