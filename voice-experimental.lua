local Voice = require('./src/voice/Voice')

local VoiceClass = Voice({
  guildId = "1027945618347397220",
  userId = "977148321682575410",
  encryption = "aead_aes256_gcm_rtpsize"
})

VoiceClass:voiceStateUpdate({ session_id = "4803f1b88fdaaf69fe6b93b56c981cb4" })
VoiceClass:voiceServerUpdate(
  'hongkong11145.discord.media:443',
  "e00cc593f172f748"
)

VoiceClass:connect()