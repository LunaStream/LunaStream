local Transform = require('stream').Transform
local ffi = require("ffi")
local Mpg123Decoder = Transform:extend()

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
    MPG123_FORCE_RATE = 8,  // Forces output sample rate
    MPG123_ENC_SIGNED_16 = 0x10  // 16-bit signed output
};
]]

  local loaded, lib = pcall(ffi.load, bin_path)

  self._lib = lib

  if not loaded then
    error(lib)
    return nil, lib
  end

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
end

function Mpg123Decoder:_transform(chunk, done)
  if type(chunk) ~= "string" then
    if type(chunk) == "table" then
      self:close()
    end
    self:push(chunk)
    done()
    return
  end

  local buffer = ffi.new("unsigned char[?]", #chunk * 2)
  local done_char = ffi.new("size_t[1]")

  if not self._config_decoder_yet then
    if self._lib.mpg123_feed(self._mh, chunk, #chunk) ~= 0 then
      error("mpg123_feed failed on initial data")
    end

    self._lib.mpg123_read(self._mh, buffer, #chunk * 2, done_char)
    local rate, channels, encoding = ffi.new("long[1]"), ffi.new("int[1]"), ffi.new("int[1]")
    self._lib.mpg123_getformat(self._mh, rate, channels, encoding)

    self._config_decoder_yet = true
  end

  local result = self._lib.mpg123_feed(self._mh, chunk, #chunk)
  if result ~= 0 then
    error("mpg123_feed failed")
  end

  while true do
    result = self._lib.mpg123_read(self._mh, buffer, #chunk * 2, done_char)
    if result ~= 0 then break end
    local res = ffi.string(buffer, done_char[0])
    self:push(res)
    res = ''
  end

  return done(nil);
end

function Mpg123Decoder:close()
  self._lib.mpg123_close(self._mh)
  self._lib.mpg123_delete(self._mh)
  self._lib.mpg123_exit()
end

return Mpg123Decoder
