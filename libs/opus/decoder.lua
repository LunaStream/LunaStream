local ffi = require('ffi')

local new, gc = ffi.new, ffi.gc

return function(opus_main)
  local Decoder = {}
  Decoder.__index = Decoder

  function Decoder:__new(sample_rate, channels) -- luacheck: ignore self

    local err = opus_main._int_ptr_t()
    local state = opus_main.lib.opus_decoder_create(sample_rate, channels, err)
    opus_main:check(err[0])

    opus_main:check(opus_main.lib.opus_decoder_init(state, sample_rate, channels))

    return gc(state, opus_main.lib.opus_decoder_destroy)

  end

  function Decoder:decode(data, len, frame_size, output_len)

    local pcm = new('opus_int16[?]', output_len)

    local ret = opus_main.lib.opus_decode(self, data, len, pcm, frame_size, 0)

    return pcm, opus_main:check(ret)

  end

  function Decoder:get(id)
    local ret = opus_main._opus_int32_ptr_t()
    opus_main.lib.opus_decoder_ctl(self, id, ret)
    return opus_main:check(ret[0])
  end

  function Decoder:set(id, value)
    if type(value) ~= 'number' then
      return opus_main:throw(opus_main.enums.BAD_ARG)
    end
    local ret = opus_main.lib.opus_decoder_ctl(self, id, opus_main._opus_int32_t(value))
    return opus_main:check(ret)
  end

  return ffi.metatype('OpusDecoder', Decoder)
end
