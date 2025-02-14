local Transform = require('stream').Transform

local PCMReader = Transform:extend()

function PCMReader:initialize()
  Transform.initialize(self)
end

function PCMReader:_transform(chunk, done)
  self:emit('raw-pcm-data', chunk)
  done(nil)
end

return PCMReader