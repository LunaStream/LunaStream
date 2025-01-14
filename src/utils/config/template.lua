return [[
server:
  host: "127.0.0.1"
  port: 3000
  password: "youshallnotpass"

luna:
  soundcloud: true

sources:
  fallbackSearchSource: 'bandcamp'
  soundcloud:
    fallbackIfSnipped: false

logger:
  request:
    enable: true
    withHeader: false
]]