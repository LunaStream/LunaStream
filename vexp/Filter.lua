local class = require('class')

local Filter = class('Filter')

function Filter:__init() end

function Filter:convert(chunk)
  print('[LunaStream / VoiceFilter]: Emulated filter class complete for chunk length: ', #chunk)
  return chunk
end

return Filter