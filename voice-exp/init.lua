local Voice = require('../src/voice')

local VoiceClass = Voice('1027945618347397220', "977148321682575410")

VoiceClass:voiceCredential(
  "7c795d3392c1e39c0a318696e7e8b3eb",
  'hongkong11064.discord.media:443',
  "5c85227721661464"
)

VoiceClass:connect()