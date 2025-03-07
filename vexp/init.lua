local timer = require('timer')
local json = require('json')
local fs = require('fs')
local MusicUtils = require('musicutils')
local Voice = require('../src/voice')
local Filter = require('./Filter')
local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

VoiceClass:connect()

p('[Voice EXP]: Song will play after 5s')

setTimeout(5000, coroutine.wrap(function()
  p('[Voice EXP]: Now play the song')
  local audioStream = fs.createReadStream('./vexp/videoplayback.weba')
    :pipe(MusicUtils.opus.WebmDemuxer:new())
    :pipe(MusicUtils.opus.Decoder:new(VoiceClass._opus))
  VoiceClass:play(audioStream, {
    encoder = true,
    -- filters = { Filter() }
  })
end))

-- setTimeout(15000, coroutine.wrap(function()
--   p('[Voice EXP]: Now pause the song')
--   VoiceClass:pause()
-- end))

-- setTimeout(20000, coroutine.wrap(function()
--   p('[Voice EXP]: Now resume the song')
--   VoiceClass:resume()
-- end))

-- setTimeout(25000, coroutine.wrap(function()
--   p('[Voice EXP]: Stop fully the song')
--   VoiceClass:stop()
-- end))

-- local newAudioStream = fs.createReadStream('./vexp/videoplayback.weba')
--   :pipe(MusicUtils.opus.WebmDemuxer:new())
--   :pipe(MusicUtils.opus.Decoder:new(VoiceClass._opus))

-- setTimeout(30000, coroutine.wrap(function()
--   p('[Voice EXP]: Now play the song to test stop event')
--   VoiceClass:play(newAudioStream, { encoder = true })
-- end))
