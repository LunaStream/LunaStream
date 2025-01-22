local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "c5ef4ee3034808daf0b60e622eea6dba" })
VoiceClass:voiceServerUpdate(
  'hongkong11056.discord.media:443',
  "1427cc908270992e"
)

VoiceClass:connect()