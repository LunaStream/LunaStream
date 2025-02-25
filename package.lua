return {
  name = "LunaStream",
  ------ Bot custom props ------
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
  ------ Bot custom props ------
  description = "A lavalink alternative focus on stability, decent speed and modulize like FrequenC",
  tags = { "lavalink audio" },
  license = "MIT",
  author = { name = "RainyXeon", email = "minh15052008@gmail.com" },
  homepage = "https://github.com/LunaticSea/LunaStream",
  dependencies = {
    -- Third party package
    "creationix/mime@2.0.0",
    "creationix/coro-http@v3.2.3",
    -- Local package (install for luvi bundling)
    "luvit/luvit@2.18.1",
    "luvit/secure-socket@1.2.3",
    "luvit/coro-websocket@3.1.1",
    "luvit/json@2.5.2",
    "luvit/querystring@2.0.1",
    "luvit/sha1@1.0.4",
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