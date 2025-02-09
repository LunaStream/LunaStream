-- PCMString Orignally from https://github.com/SinisterRectus/Discordia/blob/master/libs/voice/streams/PCMString.lua
local PcmString, get = require('class')('PcmStream')
table.unpack = unpack or table.unpack

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

return PcmString
