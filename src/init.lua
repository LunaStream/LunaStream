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
  self._prefix = "/v" .. require('./constants/metadata.lua').version.major
end

function LunaStream:setupAddon()
  self._app.use(require("./addon/auth.lua"))
  self._app.use(require("./addon/req_logger.lua"))
  self._app.use(weblit.autoHeaders)
  print('[lunastream]: All addon are ready!')
end

function LunaStream:setupRoutes()
  self._app.route({ path = "/version" }, function (req, res)
    requireRoute("./router/version.lua", req, res)
  end)

  self._app.route({ path = self._prefix .. "/info" }, function (req, res)
    requireRoute("./router/info.lua", req, res)
  end)

  self._app.route({ path = self._prefix .. "/loadtracks" }, function (req, res)
    requireRoute("./router/loadtracks.lua", req, res)
  end)

  self._app.route({ path = self._prefix .. "/encodetrack", method = "POST" }, function (req, res)
    requireRoute("./router/encodetrack.lua", req, res)
  end)

  self._app.route({ path = self._prefix .. "/decodetrack" }, function (req, res)
    requireRoute("./router/decodetrack.lua", req, res)
  end)

  print('[lunastream]: All router are ready!')
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
  print('[lunastream]: Websocket is ready!')
end

function LunaStream:start()
  self._app.bind({
    host = config.server.host,
    port = config.server.port
  })
  self._app.start()
  print(string.format(
    '[lunastream]: Currently running server [%s] at port: %s',
    config.server.host,
    config.server.port
  ))
end

return LunaStream