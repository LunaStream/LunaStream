return [[
server:
  host: "127.0.0.1"
  port: 3000
  password: "youshallnotpass"

luna:
  sources:
    - 'bandcamp'
    - 'http'
    - 'local_file'
    - 'nicovideo'
    - 'instagram'
    - 'facebook'
    - 'twitch'
    - 'kwai'
    - 'deezer'
    - 'soundcloud'
    - 'spotify'
    - 'vimeo'
    - 'youtube'
    - 'youtube_music'
  
sources:
  fallbackSearchSource: 'bcsearch'
  maxSearchResults: 25
  maxAlbumPlaylistLength: 50
  soundcloud:
    fallbackIfSnipped: false

logger:
  accept: 'error warn info debug'
  logToFile: true
  request:
    enable: true
    withHeader: false

audio:
  quality: 'high'
  encryption: 'aead_aes256_gcm_rtpsize'
  # best, medium, fastest, zero order holder, linear
  resamplingQuality: 'best'
]]
