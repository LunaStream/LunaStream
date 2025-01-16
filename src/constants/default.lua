return {
  server = {
    host = "127.0.0.1",
    password = "youshallnotpass",
    port = 1337
  },
  luna = {
    soundcloud = true,
    bandcamp = true
  },
  sources = {
    fallbackSearchSource = 'bcsearch',
    maxSearchResults = 25,
    soundcloud = {
      fallbackIfSnipped = false
    }
  },
  logger = {
    logToFile = true,
    request = {
      enable = true,
      withHeader = false
    }
  }
}