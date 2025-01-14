local weblit = require('weblit')
local config = require('./utils/config')
local class = require('class')

local LunaStream = class('LunaStream')

local function requireRoute(target, req, res)
  local answer = function (body, code, headers)
    res.body = body
    res.code = code
    for key, value in pairs(headers) do
      res.headers[key] = value
    end
  end
  require(target)(req, res, answer)
end

function LunaStream:__init()
  self._app = weblit.app
  self._prefix = "/v" .. require('../package.lua').versionExtended.major
end

function LunaStream:setupAddon()
  self._app.use(require("./addon/auth.lua"))
  self._app.use(require("./addon/req_logger.lua"))
  self._app.use(weblit.autoHeaders)
  print('[LunaStream]: All addon are ready!')
end

function LunaStream:setupRoutes()
  local route_list = {
    ["./router/version.lua"] = { path = "/version" },
    ["./router/info.lua"] = { path = self._prefix .. "/info" },
    ["./router/encodetrack.lua"] = { path = self._prefix .. "/encodetrack", method = "POST" },
    ["./router/decodetrack.lua"] = { path = self._prefix .. "/decodetrack" }
  }

  for key, value in pairs(route_list) do
    self._app.route(value, function (req, res)
      requireRoute(key, req, res)
    end)
  end

  local preload_route_loadtracks = require("./router/loadtracks.lua")
  self._app.route({ path = self._prefix .. "/loadtracks" }, function (req, res)
    local answer = function (body, code, headers)
      res.body = body
      res.code = code
      for key, value in pairs(headers) do
        res.headers[key] = value
      end
    end
    preload_route_loadtracks(req, res, answer)
  end)

  print('[LunaStream]: All router are ready!')
end

function LunaStream:setupWebsocket()
  self._app.websocket({
    path = self._prefix .. "/websocket",
  }, function (req, read, write)
    -- Log the request headers
    p(req)
    -- Log and echo all messages
    for message in read do
      write(message)
    end
    -- End the stream
    write()
  end)
  print('[LunaStream]: Websocket is ready!')
end

function LunaStream:start()
  self._app.bind({
    host = config.server.host,
    port = config.server.port
  })
  self._app.start()
  print(string.format(
    '[LunaStream]: Currently running server [%s] at port: %s',
    config.server.host,
    config.server.port
  ))
end

return LunaStream