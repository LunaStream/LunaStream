local class = require('class')
local json = require('json')
local websocket = require('coro-websocket')
local Emitter = require('./Emitter')

local WebSocket = class('WebSocket', Emitter)

---WebSocketOptions interface
---@class WebSocketOptions
---@field url string The websocket url
---@field headers '[Headers](https://bilal2453.github.io/coro-docs/docs/coro-websocket.html#headers)' Array of websocket headers

---Modified coro-websocket client based on event system
---@class WebSocket
---<!tag:interface>

---Initial class for WebSocket class
---@param options WebSocketOptions
function WebSocket:__init(options)
	options = options or {}
	Emitter.__init(self)
	self._config = websocket.parseUrl(options.url)
	self._config.headers = options.headers
	self._url = options.url
	self._config.pathname = options.path or self._config.pathname
  self._ws_read = nil
	self._ws_write = nil
	self._close_event_sent = false
end

---Connect to the websocket
---@return boolean
function WebSocket:connect()
	local res, ws_read, ws_write = websocket.connect(self._config)

	if res and res.code == 101 then
		self._ws_write, self._ws_read = ws_write, ws_read
		coroutine.wrap(self._listen_msg)(self)
		self:emit('open', self)
		return true
	else
		self:emit('close', 1006, 'Host not found')
		return false
	end
end

function WebSocket:_listen_msg()
	for data in self._ws_read do
		if data.payload == '\003\233' then
			self:emit('close', 1006, 'Host disconnected')
			return
		elseif string.match(data.payload, '\015\166') then
			self:emit('close', 4006, data.payload:sub(3))
			return
		elseif not data.payload then
			self:emit('error', data.error)
		else
			local json_data = json.decode(data.payload)
			data.json_payload = json_data
			self:emit('message', data)
		end
	end
	if not self._close_event_sent then
		self:emit('close', 1006, 'Host disconnected')
		self._close_event_sent = false
	end
end

---Close the websocket connection
---@param code number
---@param reason string
function WebSocket:close(code, reason)
	code = code or 1000
	reason = reason or 'Self closed'
	self._close_event_sent = true
	self._ws_write({
    opcode = 8,
    payload = '',
    len = 0,
    mask = false,
    fin = true,
    rsv1 = false,
    rsv2 = false,
    rsv3 = false
  })
	self:emit('close', code, reason)
	self._ws = websocket
  self._ws_read = nil
	self._ws_write = nil
end

---Send message to websocket
---@param payload string
---@return boolean
function WebSocket:send(payload)
	if type(payload) ~= "string" then
		payload = json.encode(payload)
	end

	self._ws_write({
    opcode = 1,
    payload = payload,
    len = string.len(payload),
    mask = false,
    fin = true,
    rsv1 = false,
    rsv2 = false,
    rsv3 = false
  })
	return true
end

---Clean all events
---@return nil
function WebSocket:cleanEvents()
	self:removeAllListeners('close')
	self:removeAllListeners('open')
	self:removeAllListeners('message')
end

return WebSocket