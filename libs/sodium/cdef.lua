return [[
int sodium_init(void);
uint32_t randombytes_random(void);
void randombytes_buf(void * const buf, const size_t size);

size_t crypto_aead_xchacha20poly1305_ietf_npubbytes(void);
size_t crypto_aead_xchacha20poly1305_ietf_keybytes(void);
size_t crypto_aead_xchacha20poly1305_ietf_abytes(void);

size_t crypto_aead_xchacha20poly1305_ietf_messagebytes_max(void);

int crypto_aead_xchacha20poly1305_ietf_encrypt(unsigned char *c,
											   unsigned long long *clen_p,
											   const unsigned char *m,
											   unsigned long long mlen,
											   const unsigned char *ad,
											   unsigned long long adlen,
											   const unsigned char *nsec,
											   const unsigned char *npub,
											   const unsigned char *k);

int crypto_aead_xchacha20poly1305_ietf_decrypt(unsigned char *m,
											   unsigned long long *mlen_p,
											   unsigned char *nsec,
											   const unsigned char *c,
											   unsigned long long clen,
											   const unsigned char *ad,
											   unsigned long long adlen,
											   const unsigned char *npub,
											   const unsigned char *k);

int crypto_aead_aes256gcm_is_available(void);
size_t crypto_aead_aes256gcm_npubbytes(void);
size_t crypto_aead_aes256gcm_keybytes(void);
size_t crypto_aead_aes256gcm_abytes(void);

size_t crypto_aead_aes256gcm_messagebytes_max(void);


int crypto_aead_aes256gcm_encrypt(unsigned char *c,
								  unsigned long long *clen_p,
								  const unsigned char *m,
								  unsigned long long mlen,
								  const unsigned char *ad,
								  unsigned long long adlen,
								  const unsigned char *nsec,
								  const unsigned char *npub,
								  const unsigned char *k);

int crypto_aead_aes256gcm_decrypt(unsigned char *m,
								  unsigned long long *mlen_p,
								  unsigned char *nsec,
								  const unsigned char *c,
								  unsigned long long clen,
								  const unsigned char *ad,
								  unsigned long long adlen,
								  const unsigned char *npub,
								  const unsigned char *k);

]]