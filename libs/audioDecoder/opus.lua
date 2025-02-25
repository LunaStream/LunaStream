local Transform = require('stream').Transform
local ffi = require('ffi')
local Opus = require('opus')
local Decoder = Transform:extend()

local default_options = {
  channels = 2,
  sampleRate = 48000,
  frameSize = 960,
  maxFrameSize = 3840,
}

function Decoder:initialize(opus_path, options)
  Transform.initialize(self, { objectMode = true })
  self.options = options or {}

  for key, value in pairs(default_options) do
    if type(self.options[key]) == "nil" then
      self.options[key] = value
      self.options[key] = value
    end
  end

  if type(opus_path) == "string" then
    local opus = Opus(opus_path)
    self.decoder = opus.decoder(self.options.sampleRate, self.options.channels)
  else
    self.decoder = opus_path.decoder(self.options.sampleRate, self.options.channels)
  end
end

function Decoder:_transform(chunk, done)
  if type(chunk) ~= "string" then
    self:push(chunk)
    done()
    return
  end

  local success, pcm = pcall(
    self.decoder.decode, self.decoder, chunk, #chunk, self.options.frameSize, self.options.maxFrameSize
  )
  if not success then
    return done(pcm)
  end
  self:push(ffi.string(pcm, self.options.maxFrameSize))
  pcm = nil
  return done();
end

return Decoder
