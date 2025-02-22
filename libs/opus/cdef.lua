return [[
typedef int16_t opus_int16;
typedef int32_t opus_int32;
typedef uint16_t opus_uint16;
typedef uint32_t opus_uint32;

typedef struct OpusEncoder OpusEncoder;
typedef struct OpusDecoder OpusDecoder;

const char *opus_strerror(int error);
const char *opus_get_version_string(void);

OpusEncoder *opus_encoder_create(opus_int32 Fs, int channels, int application, int *error);
int opus_encoder_init(OpusEncoder *st, opus_int32 Fs, int channels, int application);
int opus_encoder_get_size(int channels);
int opus_encoder_ctl(OpusEncoder *st, int request, ...);
void opus_encoder_destroy(OpusEncoder *st);

opus_int32 opus_encode(
	OpusEncoder *st,
	const opus_int16 *pcm,
	int frame_size,
	unsigned char *data,
	opus_int32 max_data_bytes
);

opus_int32 opus_encode_float(
	OpusEncoder *st,
	const float *pcm,
	int frame_size,
	unsigned char *data,
	opus_int32 max_data_bytes
);

OpusDecoder *opus_decoder_create(opus_int32 Fs, int channels, int *error);
int opus_decoder_init(OpusDecoder *st, opus_int32 Fs, int channels);
int opus_decoder_get_size(int channels);
int opus_decoder_ctl(OpusDecoder *st, int request, ...);
void opus_decoder_destroy(OpusDecoder *st);

int opus_decode(
	OpusDecoder *st,
	const unsigned char *data,
	opus_int32 len,
	opus_int16 *pcm,
	int frame_size,
	int decode_fec
);

int opus_decode_float(
	OpusDecoder *st,
	const unsigned char *data,
	opus_int32 len,
	float *pcm,
	int frame_size,
	int decode_fec
);
]]
