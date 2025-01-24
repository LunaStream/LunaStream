local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "96bbf22c16b29c82223d6589ac0a4500",
  'hongkong11064.discord.media:443',
  "0df2a3fcc5647e63"
)

VoiceClass:connect()