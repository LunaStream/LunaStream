local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "6f3c551afec10210b3432f958c8c534f",
  'hongkong11179.discord.media:443',
  "8f1a61002e7467e7"
)

VoiceClass:connect()