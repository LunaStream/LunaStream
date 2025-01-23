local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "8a440a87a9d6a6e8034a4f2f243fd18c",
  'hongkong11135.discord.media:443',
  "6f806c54a2199dea"
)

VoiceClass:connect()