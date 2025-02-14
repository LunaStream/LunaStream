local ffi = require('ffi')
local bit = require('bit')

return function (sodium_bind)
  local unsigned_char_array_t = sodium_bind._unsigned_char_array_t
  local lib = sodium_bind._lib
  local typeof = ffi.typeof
  local aead_aes256_gcm = {}

	local NPUBBYTES = tonumber(lib.crypto_aead_aes256gcm_npubbytes())
	local KEYBYTES = tonumber(lib.crypto_aead_aes256gcm_keybytes())
	local ABYTES = tonumber(lib.crypto_aead_aes256gcm_abytes())

	local MAX_MESSAGEBYTES = tonumber(lib.crypto_aead_aes256gcm_messagebytes_max())

	local mut_key_t = typeof('unsigned char[$]', KEYBYTES)
	local key_t = typeof('const unsigned char[$]', KEYBYTES)
	local nonce_t = typeof('const unsigned char[$]', NPUBBYTES)

	function aead_aes256_gcm.key(key)
		assert(#key == KEYBYTES, 'invalid key size')

		return key_t(key)
	end

	function aead_aes256_gcm.keygen()
		local k = mut_key_t()
		lib.randombytes_buf(k, KEYBYTES)
		return k
	end

	function aead_aes256_gcm.nonce(nonce)

		if type(nonce) == 'string' then
			assert(#nonce == 4, 'invalid nonce bytes')

			local a, b, c, d = nonce:byte(1, 4)
			return nonce_t(a, b, c, d)
		end

		assert(nonce <= 0xFFFFFFFF and nonce >= 0, 'invalid nonce')

		-- write u32 nonce as big-endian
		local a = bit.band(bit.rshift(nonce, 24), 0xFF)
		local b = bit.band(bit.rshift(nonce, 16), 0xFF)
		local c = bit.band(bit.rshift(nonce, 8), 0xFF)
		local d = bit.band(nonce, 0xFF)

		return nonce_t(a, b, c, d) -- the rest of the bytes are zero filled

	end

	--- Encrypt a message `m` using the secret key `k` and public nonce `npub` and generate an
	--- authentication tag of both the confidential message and non-confidential additional
	--- data `ad` .
	---@param m ffi.cdata*|string The message to encrypt
	---@param m_len number The length of the message in bytes
	---@param ad ffi.cdata*|string The additional data to encrypt
	---@param ad_len number The length of the additional data in bytes
	---@param npub ffi.cdata* The public nonce
	---@param k ffi.cdata* The secret key
	function aead_aes256_gcm.encrypt(m, m_len, ad, ad_len, npub, k)
		assert(m_len <= MAX_MESSAGEBYTES, 'message too long')
		assert(ffi.istype(nonce_t, npub), 'invalid nonce')
		assert(ffi.istype(key_t, k), 'invalid key')

		local ciphertext_len = m_len + ABYTES
		local ciphertext = unsigned_char_array_t(ciphertext_len)
		local ciphertext_len_p = ffi.new('unsigned long long[1]', ciphertext_len)

		if lib.crypto_aead_aes256gcm_encrypt(ciphertext, ciphertext_len_p, m, m_len, ad, ad_len, nil, npub, k) < 0 then
			return nil, 'libsodium encryption failed'
		end

		return ciphertext, tonumber(ciphertext_len_p[0])

	end

	--- Verifies that `c` includes a valid authentication tag given the secret key `k`, public
	--- nonce `npub`, and optional non-confidential additional data `ad`.
	--- 
	--- If the ciphertext is validated, the message is decrypted and returned.
	---@param c ffi.cdata*|string The ciphertext to decrypt
	---@param c_len number The length of the ciphertext
	---@param ad ffi.cdata*|string The additional data to verify
	---@param ad_len number The length of the additional data
	---@param npub ffi.cdata* The public nonce
	---@param k ffi.cdata* The secret key
	function aead_aes256_gcm.decrypt(c, c_len, ad, ad_len, npub, k)
		assert(ffi.istype(nonce_t, npub), 'invalid nonce')
		assert(ffi.istype(key_t, k), 'invalid key')

		local m_len = c_len - ABYTES
		local m = unsigned_char_array_t(m_len)
		local m_len_p = ffi.new('unsigned long long[1]', m_len)

		if lib.crypto_aead_aes256gcm_decrypt(m, m_len_p, nil, c, c_len, ad, ad_len, npub, k) < 0 then
			return nil, 'libsodium decryption failed'
		end

		return m, tonumber(m_len_p[0])

	end

  return aead_aes256_gcm
end