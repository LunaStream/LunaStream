local class = require('class')
local ffi = require('ffi')

local Sodium = class('Sodium')

function Sodium:__init(production)
  local bin_dir = string.format(
    './bin/sodium/%s/%s%s',
    require('los').type(),
    jit.arch,
    require('los').type() == 'linux' and '.so' or '.dll'
  )

  local loaded, lib = pcall(ffi.load, production and './native/sodium' or bin_dir)

  if not loaded then
    return nil, lib
  end

  self._lib = lib

  ffi.cdef(require('./cdef.lua'))

  self._unsigned_char_array_t = ffi.typeof('unsigned char[?]')

  if lib.sodium_init() < 0 then
    return nil, 'libsodium initialization failed'
  end

  self._mode = (lib.crypto_aead_aes256gcm_is_available() ~= 0)
    and 'aead_aes256_gcm_rtpsize'
    or  'aead_xchacha20_poly1305_rtpsize'

  self._encryption = require('./encryption/' .. self._mode:sub(1, -9))(self)
end

function Sodium:random()
  return self._lib.randombytes_random()
end

function Sodium:key(key)
  return self._encryption.key(key)
end

function Sodium:keygen()
  return self._encryption.keygen()
end

function Sodium:nonce(nonce)
  return self._encryption.nonce(nonce)
end

function Sodium:encrypt(m, m_len, ad, ad_len, npub, k)
  return self._encryption.encrypt(m, m_len, ad, ad_len, npub, k)
end

function Sodium:decrypt(c, c_len, ad, ad_len, npub, k)
  return self._encryption.decrypt(c, c_len, ad, ad_len, npub, k)
end

return Sodium