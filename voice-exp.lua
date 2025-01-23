local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "9f1a6e087e8799d587d9e06216ecf5a4" })
VoiceClass:voiceServerUpdate(
  'hongkong11133.discord.media:443',
  "2a1441dde2087a2f"
)

VoiceClass:connect()