require('./utils/luaex')

local weblit = require('weblit')
local json = require('json')
local class = require('class')
local timer = require('timer')
local Opus = require('quickmedia').opus.Library

local config = require('./utils/config')
local source = require("./sources")
local generateSessionId = require('./utils/generateSessionId')

local setInterval = timer.setInterval
local clearInterval = timer.clearInterval

local setTimeout = timer.setTimeout
local clearTimeout = timer.clearTimeout

local LunaStream, get = class('LunaStream')

local function requireRoute(target, req, res, luna)
  local answer = function(body, code, headers)
    res.body = body
    res.code = code
    for key, value in pairs(headers) do
      res.headers[key] = value
    end
  end
  require(target)(req, res, answer, luna)
end

function LunaStream:__init(devmode)
  self._initialRunTime = os.time()
  self._devmode = devmode
  self._manifest = require('./utils/manifest.lua')(devmode)
  self:printInitialInfo()
  self._config = config
  self._app = weblit.app
  self._prefix = "/v" .. self._manifest.version.major
  self._sessions = {}
  self._waiting_sessions = {}
  self._logger = require('./utils/logger')(
    5, '!%Y-%m-%dT%TZ', config.logger.logToFile and 'lunastream.log' or '', 20, self
  )
  self._sources = source(self)
  self._services = { statusMonitor = require('./services/statusMonitor')(self) }
  self._opus = Opus(self:getBinaryPath('opus'))
end

---------------------------------------------------------------
-- Function: getBinaryPath
-- Parameters:
--    name (string) - name of the binary/library.
--    production (boolean) - production mode flag.
-- Objective: Returns the binary path for the given library based on the OS and production mode.
---------------------------------------------------------------
function LunaStream:getBinaryPath(name)
  local os_name = require('los').type()
  local arch = os_name == 'darwin' and 'universal' or jit.arch
  local lib_name_list = { win32 = '.dll', linux = '.so', darwin = '.dylib' }
  return string.format('./bin/%s-%s-%s%s', name, os_name, arch, lib_name_list[os_name])
end


function get:sources()
  return self._sources
end

function get:config()
  return self._config
end

function get:logger()
  return self._logger
end

function get:manifest()
  return self._manifest
end

function get:services()
  return self._services
end

function get:sessions()
  return self._sessions
end

function LunaStream:printInitialInfo()
  local table_data = {
    self._manifest.version.semver,
    self._manifest.buildTime,
    os.date('%F %T', self._manifest.buildTime),
    self._manifest.git.branch,
    self._manifest.git.commit,
    os.date('%F %T', tonumber(self._manifest.git.commitTime)),
    self._manifest.runtime.luvit,
    self._manifest.runtime.luvi,
    self._manifest.runtime.libuv,
  }
  local template = string.format(
    [[
                                                               __________________
 _                      ____  _                               / ______________  /
| |   _   _ _ __   __ _/ ___|| |_ _ __ ___  __ _ _ __ ___    / /   _/\__     / /
| |  | | | | '_ \ / _` \___ \| __| '__/ _ \/ _` | '_ ` _ \  / /   \    /    / / 
| |__| |_| | | | | (_| |___) | |_| | |  __/ (_| | | | | | |/ /    /_  _\   / /  
|_____\__,_|_| |_|\__,_|____/ \__|_|  \___|\__,_|_| |_| |_/ /_______\/____/ /
=========================================================/_________________/

    - Version:          %s
    - Build:            %s
    - Build time:       %s
    - Branch:           %s
    - Commit:           %s
    - Commit time:      %s
    - Luvit:            %s
    - Luvi:             %s
    - Libuv:            %s
]], table.unpack(table_data)
  )

  print(template)
end

function LunaStream:setupAddon()
  local count = 0
  -- Load custom addons
  local addons_list = { "./addon/auth.lua", "./addon/req_logger.lua" }

  for _, path in pairs(addons_list) do
    self._app.use(
      function(req, res, go)
        require(path)(req, res, go, self)
      end
    )
    count = count + 1
  end

  -- Load third party addons
  self._app.use(weblit.autoHeaders)
  self._logger:info('LunaStream', 'Registered %s addons', count + 1)
end

function LunaStream:setupRoutes()
  local count = 0
  local route_list = {
    ["./router/version.lua"] = { path = "/version" },
    ["./router/info.lua"] = { path = self._prefix .. "/info" },
    ["./router/stats.lua"] = { path = self._prefix .. "/stats" },
    ["./router/encodetrack.lua"] = {
      path = self._prefix .. "/encodetrack",
      method = "POST",
    },
    ["./router/decodetrack.lua"] = { path = self._prefix .. "/decodetrack" },
    ["./router/trackstream.lua"] = { path = self._prefix .. "/trackstream" },
    ["./router/loadtracks.lua"] = { path = self._prefix .. "/loadtracks" },
    ["./router/sessions/players"] = {
      path = self._prefix .. "/sessions/:sessionId/players/:guildId?",
    },
    ["./router/sessions/update.lua"] = {
      path = self._prefix .. "/sessions/:sessionId",
      method = "PATCH",
    },
  }

  local processed_routes = {}
  for key, value in pairs(route_list) do
    local path = value.path
    local optional_param = path:match(":(%w+)%?")

    if optional_param then
      local required_path = path:gsub(":%w+%?", ":%1"):gsub("::", ":"):gsub("%?$", "")
      table.insert(
        processed_routes, {
          file = key,
          path = required_path,
          method = value.method,
        }
      )

      local optional_path = path:gsub("/:?" .. optional_param .. "%?", ""):gsub("::", ":"):gsub("%?$", "")
      table.insert(
        processed_routes, {
          file = key,
          path = optional_path,
          method = value.method,
        }
      )
    else
      table.insert(
        processed_routes, { file = key, path = path, method = value.method }
      )
    end
  end

  for _, route in ipairs(processed_routes) do
    self._app.route(
      { path = route.path, method = route.method }, function(req, res)
        requireRoute(route.file, req, res, self)
      end
    )
    count = count + 1
  end

  self._logger:info('LunaStream', 'Registered %s routes', count)
end

function LunaStream:setupWebsocket()
  self._app.websocket(
    { path = self._prefix .. "/websocket" }, function(req, read, write)
      -- Getting some infomation
      local user_id = req.headers['User-Id']
      local client_name = req.headers['Client-Name']
      local ws_session_id = req.headers['Session-Id']

      if not client_name then
        self._logger:info('WebSocket', 'Connection closed with unknown client name')
        return write()
      end

      -- Check client name
      local client_name_with_url_match = client_name:match('[^%s]+/[^%s]+ %([^%s]+%)')
      local client_name_match = client_name:match('[^%s]+/[^%s]+')

      if not client_name_with_url_match and not client_name_match then
        self._logger:info('WebSocket', 'Connection closed with %s (Invalid Client-Name)', client_name)
        return write()
      end

      -- Check user Id
      if not user_id then
        self._logger:info('WebSocket', 'Connection closed with %s (Missing userId)', client_name)
        return write()
      end

      -- Register session
      local client_info = string.split(client_name, '%S+')
      local session_id = ""

      -- Check if session have resuming
      if ws_session_id and self._waiting_sessions[ws_session_id] then
        self._waiting_sessions[ws_session_id] = nil
        session_id = ws_session_id
        self._sessions[session_id].write = write
      else
        session_id = generateSessionId(16)
        self._sessions[session_id] = {
          client = {
            name = client_info[1]:match('(.+)/[^%s]+'),
            version = client_info[1]:match('[^%s]+/(.+)'),
            link = client_info[2] and client_info[2]:sub(1, -2):sub(2) or "Unknown",
          },
          write = write,
          user_id = user_id,
          players = {},
          interval = nil,
          resuming = false,
          timeout = 0,
        }
      end

      -- Write session id
      write(
        {
          opcode = 1,
          payload = string.format('{"op": "ready", "resumed": false, "sessionId": "%s"}', session_id),
        }
      )

      -- Write current status
      local currentStats = self._services.statusMonitor:get()
      currentStats.op = "stats"
      write({ opcode = 1, payload = json.encode(currentStats) })

      -- Success logger
      self._logger:info('WebSocket', 'Connection established with %s', client_name)

      -- Setup status monitor
      self._sessions[session_id].interval = setInterval(
        60000, function()
          coroutine.wrap(
            function()
              local currentStatsCoro = self._services.statusMonitor:get()
              currentStatsCoro.op = "stats"
              write({ opcode = 1, payload = json.encode(currentStatsCoro) })
            end
          )()
        end
      )

      -- Keep connection
      for message in read do
      end

      -- End stream
      write()

      -- When disconnected
      clearInterval(self._sessions[session_id].interval)
      self._logger:info('WebSocket', 'Connection closed with %s', client_name)
      
      -- Check is ressuming enabled
      if not self._sessions[session_id].resuming then
        -- Destroy all players in session
        for _, player in pairs(self._sessions[session_id].players) do
          player:destroy()
        end
        
        self._sessions[session_id] = nil
        collectgarbage("collect")
        return
      end

      -- Start timing out resuming
      local timeout = self._sessions[session_id].timeout
      self._logger:info('WebSocket', 'Session %s have resuming, waiting for %s secconds', session_id, timeout / 1000)

      setTimeout(
        timeout, function()
          if type(self._waiting_sessions[session_id]) == "nil" then
            return
          end
          self._sessions[session_id] = nil
          self._waiting_sessions[session_id] = nil
          self._logger:info('WebSocket', 'Timeout! Session %s deleted!', session_id, timeout)
        end
      )

      self._waiting_sessions[session_id] = true

    end
  )
  self._logger:info('LunaStream', 'Registered WebSocket server')
end

function LunaStream:start()
  self._app.bind({ host = config.server.host, port = config.server.port })
  self._app.start()
  self._logger:info('LunaStream', 'Currently running server [%s] at port: %s', config.server.host, config.server.port)
end

return LunaStream
