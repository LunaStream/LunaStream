local class = require('class')
local json = require('json')
local timer = require('timer')
local buffer = require('buffer')
local stream = require('stream')
local uv = require('uv')

local Emitter = require('./Emitter')
local WebSocket = require('./WebSocket')

local sf = string.format
local setInterval = timer.setInterval
local clearInterval = timer.clearInterval
local NULL = json.NULL

local IDENTIFY        = 0
local SELECT_PROTOCOL = 1
local READY           = 2
local HEARTBEAT       = 3
local DESCRIPTION     = 4
local SPEAKING        = 5
local HEARTBEAT_ACK   = 6
local RESUME          = 7
local HELLO           = 8
local RESUMED         = 9

local DISCORD_CLOSE_CODES = {
  [1006] = { reconnect = true },
  [4014] = { error = false },
  [4015] = { reconnect = true }
}

local Voice = class('Voice', Emitter)

function Voice:__init(options)
  Emitter.__init(self)

  options = options or {}
  self._guildId = assert(options.guildId, 'Missing guildId field')
  self._userId = assert(options.userId, 'Missing userId field')
  self._encryption = assert(options.encryption, 'Missing encryption field')

  self._ws = nil

  self._state = {
    status = 'disconnected'
  }
  self._playerState = {
    status = 'idle'
  }

  self._sessionId = NULL
  self._voiceServer = {
    guildId = NULL,
    token = NULL,
    endpoint = NULL
  }

  self._hbInterval = nil
  self._seq_ack = -1
  self._udp = nil
  self._udpInfo = {
    ssrc = NULL,
    ip = NULL,
    port = NULL,
    secretKey = NULL
  }
  self._ssrcs = {}

  self._heartbeat_ack = nil
  self._statistics = {
    packetsSent = 0,
    packetsLost = 0,
    packetsExpected = 0
  }

  self._player = {
    sequence = 0,
    timestamp = 0,
    nextPacket = 0
  }

  self._nonce = 0
  self._nonceBuffer = self._encryption == 'aead_aes256_gcm_rtpsize'
    and buffer.Buffer:new(12)
    or buffer.Buffer:new(24)
  self._packetBuffer = buffer.Buffer:new(12)

  self._playTimeout = nil
  self._audioStream = nil
end

function Voice:connect(cb, reconnect)
  if self._ws then
    self._ws:close(1000, 'Normal close')
  end

  local uri = sf('wss://%s/?v=7', self._voiceServer.endpoint)

  self._ws = WebSocket({
    url = uri,
    headers = {
      { 'User-Agent', 'DiscordBot (https://github.com/SinisterRectus/Discordia/tree/master/libs/voice, 2.13.0)' }
    }
  })

  self._ws:on('open', function ()
    if reconnect then
      self._ws:send({
        op = RESUME,
        d = {
          server_id = self._voiceServer.guildId,
          session_id = self._sessionId,
          token = self._voiceServer.token
        }
      })
    else
      self._ws:send({
        op = IDENTIFY,
        d = {
          server_id = self._guildId,
          user_id = self._userId,
          session_id = self._sessionId,
          token = self._voiceServer.token
        }
      })
    end
  end)

  self._ws:on('message', function (data)
    p(data.payload)
    self:handleMessage(cb, data.json_payload)
  end)

  self._ws:on('close', function (code, reason)
    if not self._ws then return end

    local closeCode = DISCORD_CLOSE_CODES[code]

    if closeCode and closeCode.reconnect then
      self:destroyConnection(code, reason)

      self:updatePlayerState({ status = 'idle', reason  'reconnecting' })

      self:connect(function ()
        -- TODO: Dummy
        -- if self._audioStream then self:unpause('reconnected') end
      end, true)
    else
      self:destroy({ status = 'disconnected', reason = 'closed', code, closeReason = reason }, false)
      return;
    end
  end)

  self._ws:on('error', function (err)
    self:emit('error', err)
  end)

  self._ws:connect()
end

function Voice:handleMessage(cb, payload)
  if payload.seq then
		self._seq_ack = payload.seq
	end

  if payload.op == READY then
    return self:handleReady(payload)
  elseif payload.op == DESCRIPTION then
    self._udpInfo.secretKey = payload.d.secret_key
    if cb then cb() end
    self:updateState({ status = 'connected' })
    self:updatePlayerState({ status = 'idle', reason = 'connected' })
  elseif payload.op == HEARTBEAT_ACK then
    self._heartbeat_ack = payload.d
  elseif payload.op == SPEAKING then
    self._ssrcs[payload.d.ssrc] = {
      userId = payload.d.user_id,
      stream = stream.PassThrough:new()
    }
    self:emit('speakStart', payload.d.user_id, payload.d.ssrc)
  elseif payload.op == HELLO then
    self:startHeartbeat(payload.d.heartbeat_interval)
  end

end

function Voice:handleReady(payload)
  self._udpInfo.ssrc = payload.d.ssrc
  self._udpInfo.ip = payload.d.ip
  self._udpInfo.port = payload.d.port
  self:handshake()
end

function Voice:startHeartbeat(interval)
	if self._hbInterval then
		clearInterval(self._hbInterval)
	end
	self._hbInterval = setInterval(interval - 1000, function ()
    coroutine.wrap(function ()
      self._ws:send({
        op = HEARTBEAT,
        d = os.time()
      })
    end)()
  end, self)
end

function Voice:stopHeartbeat()
	if self._hbInterval then
		clearInterval(self._hbInterval)
	end
	self._hbInterval = nil
end

function Voice:updateState(state)
  self:emit('stateChange', self._state, state)
  self._state = state
end

function Voice:updatePlayerState(state)
  self:emit('playerStateChange', self._playerState, state)
  self._playerState = state
end

function Voice:destroy(state, destroyStream)
  self:destroyConnection(1000, 'Normal closure')

  self._udpInfo = nil
  self._voiceServer = nil
  self._sessionId = nil
  if self._audioStream and destroyStream then
    -- TODO: Dummy
    self._audioStream:destroy()
    self._audioStream:removeAllListeners()
    self._audioStream = nil
  end

  self:updateState(state)
  self:updatePlayerState({ status = 'idle', reason = 'destroyed' })
end

function Voice:destroyConnection(code, reason)
  if self._hbInterval then
    clearInterval(self._hbInterval)
    self._hbInterval = nil
  end

  if self._playTimeout then
    self._playTimeout = nil
  end

  self._player = {
    sequence = 0,
    timestamp = 0,
    nextPacket = 0
  }

  if self._ws then
    self._ws:close(code, reason)
    self._ws:cleanEvents()
    self._ws = nil
  end

  -- if self._udp then
  --   self._udp:close()
  --   self._udp:removeAllListeners('message')
  --   self._udp:removeAllListeners('error')
  --   self._udp = nil
  -- end
end

function Voice:handshake()
  self._udp = uv.new_udp()
	self._udp:recv_start(function(err, data)
		assert(not err, err)
		self._udp:recv_stop()
		local client_ip = string.unpack('xxxxxxxxz', data)
		local client_port = string.unpack('<I2', data, -2)
		return coroutine.wrap(self.selectProtocol)(self, client_ip, client_port)
	end)
	local packet = string.pack('>I2I2I4c64H', 0x1, 70,
    self._udpInfo.ssrc,
    self._udpInfo.ip,
    self._udpInfo.port
  )
	return self._udp:send(packet, self._udpInfo.ip, self._udpInfo.port)
end

function Voice:selectProtocol(address, port)
  self._ws:send({
    op = SELECT_PROTOCOL,
    d = {
      protocol = 'udp',
      data = {
        address = address,
        port = port,
        mode = self._encryption,
      }
    }
  })
end

function Voice:voiceStateUpdate(obj)
  self._sessionId = obj.session_id
end

function Voice:voiceServerUpdate(endpoint, token)
  self._voiceServer.token = token
  self._voiceServer.endpoint = endpoint
end

return Voice