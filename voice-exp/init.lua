local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "b6720d8ca28297be83c0a4bd9316e617",
  'hongkong11129.discord.media:443',
  "7d20a9d92bb7e807"
)

VoiceClass:connect()