local Voice = require('../src/voice')
-- {"voice":{"token":"677ca788b33af9e9","endpoint":"india10010.discord.media:443","sessionId":"112235d73f3fb50faca089d2f70d0a6d"}}
local VoiceClass = Voice('813815427892641832', "1120309844117815326")

VoiceClass:voiceCredential(
  "112235d73f3fb50faca089d2f70d0a6d",
  'india10010.discord.media:443',
  "677ca788b33af9e9"
)

VoiceClass:connect()