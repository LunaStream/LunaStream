local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "89a4715f8b639e6b0d675ba154828e4b",
  'hongkong11070.discord.media:443',
  "d693badca92e7d07"
)

VoiceClass:connect()