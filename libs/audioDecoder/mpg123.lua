local Transform = require('stream').Transform
local ffi = require("ffi")
local uv = require('uv')
local Mpg123Decoder = Transform:extend()

local function setImmediate(fn)
  local timer = uv.new_timer()
  timer:start(0, 0, function()
    timer:stop()
    timer:close()
    fn()
  end)
end

function Mpg123Decoder:initialize(bin_path)
  Transform.initialize(self, { objectMode = true })

  self._max_chunk = 3840
  self._reminder = ''

  ffi.cdef[[ 
    typedef int64_t off_t;
    typedef int size_t;
    
    int mpg123_init(void);
    void mpg123_exit(void);
    typedef struct mpg123_handle_struct mpg123_handle;
    mpg123_handle* mpg123_new(const char *decoder, int *error);
    int mpg123_open_feed(mpg123_handle *mh);
    int mpg123_feed(mpg123_handle *mh, const unsigned char *in, size_t size);
    int mpg123_read(mpg123_handle *mh, unsigned char *outmemory, size_t outmemsize, size_t *done);
    int mpg123_close(mpg123_handle *mh);
    void mpg123_delete(mpg123_handle *mh);
    int mpg123_format_none(mpg123_handle *mh);
    int mpg123_format(mpg123_handle *mh, long rate, int channels, int encoding);
    int mpg123_getformat(mpg123_handle *mh, long *rate, int *channels, int *encoding);
    int mpg123_param(mpg123_handle *mh, int type, long value, double fvalue);
    
    enum {
      MPG123_FORCE_RATE = 8,
      MPG123_ENC_SIGNED_16 = 0x10
    };
  ]]

  local loaded, lib = pcall(ffi.load, bin_path)
  if not loaded then
    error(lib)
  end
  self._lib = lib

  if self._lib.mpg123_init() ~= 0 then
    error("Failed to initialize mpg123")
  end

  self._mh = self._lib.mpg123_new(nil, nil)
  if self._mh == nil then
    error("Failed to create mpg123 handle")
  end

  if self._lib.mpg123_open_feed(self._mh) ~= 0 then
    error("Failed to open mpg123 in feed mode")
  end

  self._config_decoder_yet = false
  self._format_configured = false
end

function Mpg123Decoder:_get_error()
  return "Error unknown"
end

function Mpg123Decoder:_transform(chunk, done)
  if type(chunk) ~= "string" then
    if type(chunk) == "table" then
      self:close()
    end
    self:push(chunk)
    return done()
  end

  local input_buffer = ffi.new("unsigned char[?]", #chunk)
  ffi.copy(input_buffer, chunk, #chunk)

  if not self._config_decoder_yet then
    if self._lib.mpg123_feed(self._mh, input_buffer, #chunk) ~= 0 then
      error("mpg123_feed failed on initial data")
    end

    local temp_out = ffi.new("unsigned char[?]", self._max_chunk)
    local done_char = ffi.new("size_t[1]")
    self._lib.mpg123_read(self._mh, temp_out, self._max_chunk, done_char)

    local rate = ffi.new("long[1]")
    local channels = ffi.new("int[1]")
    local encoding = ffi.new("int[1]")
    self._lib.mpg123_getformat(self._mh, rate, channels, encoding)

    self._config_decoder_yet = true
  else
    local feed_result = self._lib.mpg123_feed(self._mh, input_buffer, #chunk)
    if feed_result ~= 0 then
      error("Erro no feed: " .. self:_get_error())
    end
  end

  local MPG123_NEW_FORMAT = -11

  -- Function to read from mpg123 and push to the next stream
  local function readAndPush()
    local out_buffer = ffi.new("unsigned char[?]", self._max_chunk)
    local done_char = ffi.new("size_t[1]")
    local read_result = self._lib.mpg123_read(self._mh, out_buffer, self._max_chunk, done_char)

    if (not self._format_configured) and read_result == MPG123_NEW_FORMAT then
      local rate_ptr = ffi.new("long[1]")
      local channels_ptr = ffi.new("int[1]")
      local encoding_ptr = ffi.new("int[1]")
      local fmt_res = self._lib.mpg123_getformat(self._mh, rate_ptr, channels_ptr, encoding_ptr)
      if fmt_res ~= 0 then
        error("Error getting format: " .. self:_get_error())
      end
      local native_rate = tonumber(rate_ptr[0])
      local desired_rate = nil
      if native_rate == 48000 or native_rate == 24000 or native_rate == 12000 then
        desired_rate = native_rate
      else
        if native_rate > 24000 then
          desired_rate = 48000
        elseif native_rate > 12000 then
          desired_rate = 24000
        else
          desired_rate = 12000
        end
      end
      self._lib.mpg123_format_none(self._mh)
      local fmtResult = self._lib.mpg123_format(self._mh, desired_rate, 2, 0x10)
      if fmtResult ~= 0 then
        error(string.format("Error setting format to %dHz, 16-bit, stereo: %s", desired_rate, self:_get_error()))
      end
      self._format_configured = true
      -- last read was a format change, so we need to read again
      read_result = self._lib.mpg123_read(self._mh, out_buffer, self._max_chunk, done_char)
    end

    if read_result == 0 then
      local res = ffi.string(out_buffer, done_char[0])
      self:push(res)
      -- schedule next read
      setImmediate(readAndPush)
    else
      return done(nil)
    end
  end

  readAndPush()
end

function Mpg123Decoder:close()
  self._lib.mpg123_close(self._mh)
  self._lib.mpg123_delete(self._mh)
  self._lib.mpg123_exit()
end


return Mpg123Decoder