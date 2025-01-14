return {
  server = {
    host = "127.0.0.1",
    password = "youshallnotpass",
    port = 1337
  },
  luna = {
    soundcloud = true
  },
  sources = {
    fallbackSearchSource = 'soundcloud',
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