local ffi = require('ffi')

local new, gc = ffi.new, ffi.gc

return function(opus_main)
  local Encoder = {}
  Encoder.__index = Encoder

  function Encoder:__new(sample_rate, channels, app) -- luacheck: ignore self

    app = app or opus_main.enums.APPLICATION_AUDIO -- TODO: test different applications

    local err = opus_main._int_ptr_t()
    local state = opus_main.lib.opus_encoder_create(sample_rate, channels, app, err)
    opus_main:check(err[0])

    opus_main:check(opus_main.lib.opus_encoder_init(state, sample_rate, channels, app))

    return gc(state, opus_main.lib.opus_encoder_destroy)
  end

  function Encoder:encode(input, input_len, frame_size, max_data_bytes)
    local pcm = new('opus_int16[?]', input_len, input)
    local data = new('unsigned char[?]', max_data_bytes)

    local ret = opus_main.lib.opus_encode(self, pcm, frame_size, data, max_data_bytes)

    return data, opus_main:check(ret)

  end

  function Encoder:get(id)
    local ret = opus_main._opus_int32_ptr_t()
    opus_main.lib.opus_encoder_ctl(self, id, ret)
    return opus_main:check(ret[0])
  end

  function Encoder:set(id, value)
    if type(value) ~= 'number' then
      return opus_main:throw(opus_main.enums.BAD_ARG)
    end
    local ret = opus_main.lib.opus_encoder_ctl(self, id, opus_main._opus_int32_t(value))
    return opus_main:check(ret)
  end

  return ffi.metatype('OpusEncoder', Encoder)
end
