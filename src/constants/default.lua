return {
  server = {
    host = "127.0.0.1",
    password = "youshallnotpass",
    port = 1337
  },
  luna = {
    soundcloud = true,
    bandcamp = false
  },
  sources = {
    fallbackSearchSource = 'soundcloud',
    maxSearchResults = 25,
    soundcloud = {
      fallbackIfSnipped = false
    }
  },
  logger = {
    request = {
      enable = true,
      withHeader = false
    }
  }
}