local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "3e6607188cfa4916955ec6b783f0f663" })
VoiceClass:voiceServerUpdate(
  'hongkong11101.discord.media:443',
  "9ed7b2b5eb232de7"
)

VoiceClass:connect()