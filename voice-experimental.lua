local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "82308dbbe6a8a4b11684d35f7f4a5d22" })
VoiceClass:voiceServerUpdate(
  'hongkong11049.discord.media:443',
  "b5a5bdf6d365878a"
)

VoiceClass:connect()