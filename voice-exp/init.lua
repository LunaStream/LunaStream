local timer = require('timer')
local setTimeout = timer.setTimeout
-- PCMString Orignally from https://github.com/SinisterRectus/Discordia/blob/master/libs/voice/streams/PCMString.lua
local PcmString, get = require('class')('PcmStream')

-- NOTE: Uses __index to generate format string for "string.unpack"
local fmt = setmetatable({}, {
  __index = function(self, n)
    self[n] = '<' .. string.rep('i2', n)
    return self[n]
  end
})

function PcmString:__init(str)
  self._str = str
  self._len = #str
  -- Index of last read pcm
  self.i = 1
end

function PcmString:read(n)
  local i = self._i or 1
  -- p(n, i, self.__PCM_SAMPLE_SIZE, i + n * self.__PCM_SAMPLE_SIZE, self._len)
  -- NOTE: Times 2 because each PCM Sample is 2 bytes(16 bits), it would've been 4 bytes(32 bits) if PCM Sample size was 32 bit

  if i + n * self.__PCM_SAMPLE_SIZE < self._len then
    local pcm = { string.unpack(fmt[n], self._str, i) }
    self._i = table.remove(pcm)
    -- p('PCM: ', pcm)
    return pcm
  end
end

function PcmString:close()
  self._str = nil
  self._len = nil
  self._i = 1
end

function get:__PCM_SAMPLE_SIZE()
  return 2
end

local Voice = require('../src/voice')
--{"voice":{"token":"8fcd178a1b687623","endpoint":"japan4479.discord.media:443","sessionId":"a9c85257c7f6fa174f40040a9e906e61"}}
local VoiceClass = Voice('813815427892641832', "1120309844117815326")

VoiceClass:voiceCredential(
  "a9c85257c7f6fa174f40040a9e906e61",
  'japan4479.discord.media:443',
  "8fcd178a1b687623"
)

local file = io.open('./voice-exp/heart_waves_48000_stereo.pcm', 'rb')

if not file then
  print('File not found')
  return
end

local audioStream = PcmString(file:read('*all'))
-- file:close()
VoiceClass:connect()


setTimeout(12000, coroutine.wrap(function()
  VoiceClass:play(audioStream, true)
end))
