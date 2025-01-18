return {
  name = "LunaStream",
  ------ Bot custom props ------
  codename = "IA",
  version = "0.0.1",
  versionExtended = {
    major = "1",
		minor = "0",
		patch = "2",
		preRelease = "demo",
		semver = "1.0.2-demo",
		build = "",
  },
  ------ Bot custom props ------
  description = "A lavalink alternative focus on stability, decent speed and modulize like FrequenC",
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
    "!test*",
    "manifest.json",
    "!make.lua",
    "!dev.lua",
    "!test.lua",
  }
}