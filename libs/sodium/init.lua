local class = require('class')
local ffi = require('ffi')

local Sodium, get = class('Sodium')

function Sodium:__init(path)
  local os_name = require('los').type()
  ---@diagnostic disable-next-line:undefined-global
  ffi.cdef(require('./cdef.lua'))

  local loaded, lib = pcall(ffi.load, path)

  if not loaded then
    error(lib)
    return nil, lib
  end

  self._lib = lib

  self._unsigned_char_array_t = ffi.typeof('unsigned char[?]')

  if lib.sodium_init() < 0 then
    return nil, 'libsodium initialization failed'
  end

  self._mode = (lib.crypto_aead_aes256gcm_is_available() ~= 0)
    and 'aead_aes256_gcm_rtpsize'
    or  'aead_xchacha20_poly1305_rtpsize'

  self._encryption = require('./encryption/' .. self._mode:sub(1, -9))(self)
end

function get:mode()
  return self._mode
end

function get:encryption()
  return self._encryption
end

function get:unsigned_char_array_t()
  return self._unsigned_char_array_t
end

function get:lib()
  return self._lib
end

function Sodium:random()
  return self.lib.randombytes_random()
end

function Sodium:key(key)
  return self.encryption.key(key)
end

function Sodium:keygen()
  return self.encryption.keygen()
end

function Sodium:nonce(nonce)
  return self.encryption.nonce(nonce)
end

function Sodium:encrypt(m, m_len, ad, ad_len, npub, k)
  return self.encryption.encrypt(m, m_len, ad, ad_len, npub, k)
end

function Sodium:decrypt(c, c_len, ad, ad_len, npub, k)
  return self.encryption.decrypt(c, c_len, ad, ad_len, npub, k)
end

return Sodium