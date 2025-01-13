return {
  name = "LunaStream",
  codename = "IA",
  version = "0.0.1",
  versionExtended = {
    major = "1",
		minor = "0",
		patch = "2",
		preRelease = "dev",
		semver = "1.0.2-dev",
		build = "",
  },
  runtime = {
    luvit = "2.18.1",
    luvi = "2.14.0",
  },
  description = "A simple description of my little package.",
  tags = { "lavalink audio" },
  license = "MIT",
  author = { name = "RainyXeon", email = "minh15052008@gmail.com" },
  homepage = "https://github.com/LunaticSea/LunaStream",
  dependencies = {
    "creationix/coro-http@v3.2.3",
    "luvit/luvit@2.2.3",
    "luvit/process@2.1.3",
    "luvit/dns@2.0.4",
    "luvit/secure-socket@1.2.3",
    "creationix/coro-websocket@3.1.1",
    "luvit/json@2.5.2"
  },
  files = {
    "**.lua",
    "!test*"
  }
}