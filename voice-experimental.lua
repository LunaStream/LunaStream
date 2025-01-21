local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "b1cdc96e080db0a875c347d4634d8de1" })
VoiceClass:voiceServerUpdate(
  'hongkong11065.discord.media:443',
  "6c054d7e6cf68e0e"
)

VoiceClass:connect()