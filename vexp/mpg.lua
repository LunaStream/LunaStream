local timer = require('timer')
local json = require('json')
local fs = require('fs')
local FileStream = require('../src/voice/stream/FileStream')
local mpg123_transform = require('mpg123')
local Voice = require('../src/voice')
local setTimeout = timer.setTimeout

local vcred = json.decode(fs.readFileSync('./vexp/vcred.json'))
if not vcred then error('vcred.json not found or invalid, please check vcred.example.json') end

local VoiceClass = Voice(vcred.guild_id, vcred.user_id)

VoiceClass:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)

VoiceClass:connect()

p('[Voice EXP]: Song will play after 5s')

setTimeout(5000, coroutine.wrap(function()
  p('[Voice EXP]: Now play the song')
  local audioStream = FileStream:new('./vexp/example.mp3')
    :pipe(mpg123_transform:new('./bin/mpg123/win32/x64.dll'))
  VoiceClass:play(audioStream, {
    encoder = true,
  })
end))