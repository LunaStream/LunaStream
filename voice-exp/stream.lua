local Voice = require('../src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_xchacha20_poly1305_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "1169ff4ed0c5358b081400f278e562e7" })
VoiceClass:voiceServerUpdate(
  'hongkong11133.discord.media:443',
  "341a56d695ad9640"
)

VoiceClass:connect()