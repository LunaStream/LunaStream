-- External library
local class = require('class')
local timer = require('timer')

-- Internal Library
local Emitter = require('./Emitter')
local WebSocket = require('./WebSocket')
local UDPController = require('./UDPController')

-- Useful functions
local sf = string.format
local setInterval = timer.setInterval
local clearInterval = timer.clearInterval

-- OP code
local IDENTIFY        = 0
local SELECT_PROTOCOL = 1
local READY           = 2
local HEARTBEAT       = 3
local DESCRIPTION     = 4
local RESUME          = 7
local HELLO           = 8
-- local RESUMED         = 9

-- Vitural enums
local VOICE_STATE = {
  disconnected = 'disconnected',
  connected = 'connected',
}
local PLAYER_STATE = {
  idle = 'idle'
}

local VoiceManager = class('VoiceManager', Emitter)

function VoiceManager:__init(guildId, userId, production_mode)
  Emitter.__init(self)
  -- Basic data
  self._guild_id = guildId
  self._user_id = userId

  -- State
  self._voice_state = VOICE_STATE.disconnected
  self._player_state = PLAYER_STATE.idle

  -- Voice credentials
  self._session_id = nil
  self._endpoint = nil
  self._token = nil

  -- Gateway
  self._ws = nil
  self._seq_ack = -1

  -- UDP
  self._udp = UDPController(production_mode)
  self._encryption = self._udp._crypto._mode
end

function VoiceManager:voiceCredential(session_id, endpoint, token)
  self._session_id = session_id or self._session_id
  self._endpoint = endpoint or self._endpoint
  self._token = token or self._token
end

function VoiceManager:connect(reconnect)
  if self._ws then
    self._ws:close(1000, 'Normal close')
  end

  local uri = sf('wss://%s/', self._endpoint)

  self._ws = WebSocket({
    url = uri,
    path = '/?v=8',
    headers = {
      { 'User-Agent', 'DiscordBot (https://github.com/LunaticSea/LunaStream)' }
    }
  })

  self._ws:on('open', function ()
    if reconnect then
      self._ws:send({
        op = RESUME,
        d = {
          server_id = self._guild_id,
          session_id = self._session_id,
          token = self._token,
          seq_ack = self._seq_ack
        }
      })
    else
      self._ws:send({
        op = IDENTIFY,
        d = {
          server_id = self._guild_id,
          user_id = self._user_id,
          session_id = self._session_id,
          token = self._token
        }
      })
    end
  end)

  self._ws:on('message', function (data)
    print('[LunaStream / Voice | WS] ' .. data.payload)
    self:messageEvent(data.json_payload)
  end)

  self._ws:on('close', function (code, reason)
    p(code, reason)
    if not self._ws then return end
    self:destroyConnection(code, reason)
  end)

  self._ws:connect()
end

function VoiceManager:messageEvent(payload)
  local op = payload.op
  local data = payload.d

  if payload.seq then
		self._seq_ack = payload.seq
	end

  if op == READY then
    self:readyOP(payload)
  elseif op == DESCRIPTION then
    self._udp:updateCredentials(nil, nil, nil, data.secret_key)
    self._voice_state = VOICE_STATE.connected
    self._player_state = PLAYER_STATE.idle
  elseif op == HELLO then
    self:startHeartbeat(data.heartbeat_interval)
  end
end

function VoiceManager:readyOP(ws_payload)
  self._udp:updateCredentials(
    ws_payload.d.ip,
    ws_payload.d.port,
    ws_payload.d.ssrc,
    nil
  )

  local res = self._udp:ipDiscovery()

  self._ws:send({
    op = SELECT_PROTOCOL,
    d = {
      protocol = 'udp',
      data = {
        address = res.ip,
        port = res.port,
        mode = self._encryption,
      }
    }
  })

  self._udp:start()
end

function VoiceManager:startHeartbeat(heartbeat_timeout)
  self._heartbeat = setInterval(heartbeat_timeout - 1000, function ()
    coroutine.wrap(VoiceManager.sendKeepAlive)(self)
  end)
end

function VoiceManager:sendKeepAlive()
  if not self._ws then return end
  self._ws:send({
    op = HEARTBEAT,
    d = {
      t = os.time(),
      seq_ack = self._seq_ack
    }
  })
end

function VoiceManager:destroyConnection(code, reason)
  if self._heartbeat then
    clearInterval(self._heartbeat)
    self._heartbeat = nil
  end

  if self._ws then
    self._ws:close(code, reason)
    self._ws:cleanEvents()
    self._ws = nil
  end

  if self._udp then
    self._udp:stop()
  end
end

return VoiceManager