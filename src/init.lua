require('./utils/luaex')

local weblit = require('weblit')
local class = require('class')

local config = require('./utils/config')
local source = require("./sources")
local generateSessionId = require('./functions/generatesessionid')

local LunaStream, get = class('LunaStream')

local function requireRoute(target, req, res, luna)
  local answer = function (body, code, headers)
    res.body = body
    res.code = code
    for key, value in pairs(headers) do
      res.headers[key] = value
    end
  end
  require(target)(req, res, answer, luna)
end

function LunaStream:__init()
  self._sources = source(self)
  self._config = config
  self._app = weblit.app
  self._prefix = "/v" .. require('../package.lua').versionExtended.major
  self._sessions = {}
end

function get:sources()
  return self._sources
end

function get:config()
  return self._config
end

function LunaStream:setupAddon()
  self._app.use(require("./addon/auth.lua"))
  self._app.use(require("./addon/req_logger.lua"))
  self._app.use(weblit.autoHeaders)
  print('[LunaStream]: All addons are ready!')
end

function LunaStream:setupRoutes()
  local route_list = {
    ["./router/version.lua"] = { path = "/version" },
    ["./router/info.lua"] = { path = self._prefix .. "/info" },
    ["./router/encodetrack.lua"] = { path = self._prefix .. "/encodetrack", method = "POST" },
    ["./router/decodetrack.lua"] = { path = self._prefix .. "/decodetrack" },
    ["./router/trackstream.lua"] = { path = self._prefix .. "/trackstream" },
    ["./router/loadtracks.lua"] = { path = self._prefix .. "/loadtracks" },
    ["./router/sessions.lua"] = { path = self._prefix .. "/sessions/:sessionId/players/:guildId?" }
  }

  local processed_routes = {}
  for key, value in pairs(route_list) do
    local path = value.path
    local optional_param = path:match(":(%w+)%?")

    if optional_param then
      local required_path = path:gsub(":%w+%?", ":%1"):gsub("::", ":"):gsub("%?$", "")
      table.insert(processed_routes, { file = key, path = required_path, method = value.method })

      local optional_path = path:gsub("/:?" .. optional_param .. "%?", ""):gsub("::", ":"):gsub("%?$", "")
      table.insert(processed_routes, { file = key, path = optional_path, method = value.method })
    else
      table.insert(processed_routes, { file = key, path = path, method = value.method })
    end
  end

  for _, route in ipairs(processed_routes) do
    self._app.route({ path = route.path, method = route.method }, function (req, res)
      requireRoute(route.file, req, res, self)
    end)
  end

  print('[LunaStream]: All routes are ready!')
end

function LunaStream:setupWebsocket()
  self._app.websocket({
    path = self._prefix .. "/websocket",
  }, function (req, read, write)
    local user_id = req.headers['User-Id']
    local client_name = req.headers['Client-Name']
    local session_id = generateSessionId(16)
    self._sessions[session_id] = { write = write, user_id = user_id, players = {} }

    write({
      opcode = 1,
      payload = string.format('{"op": "ready", "resumed": false, "sessionId": "%s"}', session_id)
    })

    print(string.format('[LunaStream]: Connection established with %s', client_name))
    for message in read do
      write(message)
    end

    write()
    self._sessions[session_id] = nil
    print(string.format('[LunaStream]: Connection closed with %s', client_name))
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
