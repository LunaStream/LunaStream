local timer = require('timer')

local setTimeout = timer.setTimeout

local Voice = require('../src/voice')
-- {"voice":{"token":"01260145bef85112","endpoint":"japan3174.discord.media:443","sessionId":"a5d3f1dd12dcec7cb7698ec4714c50c3"}}
local VoiceClass = Voice('813815427892641832', "1120309844117815326")

VoiceClass:voiceCredential(
  "a5d3f1dd12dcec7cb7698ec4714c50c3",
  'japan3174.discord.media:443',
  "01260145bef85112"
)

local file = io.open('./libs/prism/results/speech_orig.demuxed.webm', 'rb')

if not file then
  print('File not found')
  return
end

VoiceClass:connect()


setTimeout(12000, coroutine.wrap(function ()
  
  VoiceClass:play(file, false)
end))