-- External library
local class = require('class')
local json = require('json')
local timer = require('timer')
local stream = require('stream')
local dgram = require('dgram')
local ffi = require('ffi')

-- Internal Library
local Emitter = require('./Emitter')
local WebSocket = require('./WebSocket')
local sodium = require('./sodium')

-- Useful functions
local sf = string.format
local setInterval = timer.setInterval
local clearInterval = timer.clearInterval
local NULL = json.NULL

-- Constant variable
local nonce = string.rep("\0", 24)
local OPUS_SAMPLE_RATE = 48000
local OPUS_FRAME_DURATION = 20
local OPUS_FRAME_SIZE = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION / 1000
local TIMESTAMP_INCREMENT = (OPUS_SAMPLE_RATE / 100) * 2
local MAX_NONCE = 2^32
local MAX_TIMESTAMP = 2^32
local MAX_SEQUENCE = 2^16
local UNPADDED_NONCE_LENGTH = 4
local AUTH_TAG_LENGTH = 16
local OPUS_SILENCE_FRAME = string.pack("BBB", 0xf8, 0xff, 0xfe)
local HEADER_EXTENSION_BYTE = string.pack("BB", 0xbe, 0xde)
local DISCORD_CLOSE_CODES = {
  [1006] = { reconnect = true },
  [4014] = { error = false },
  [4015] = { reconnect = true }
}
local HEADER_FMT = '>BBI2I4I4'

-- OP code
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

local Voice = class('Voice', Emitter)

function Voice:__init(options)
  Emitter.__init(self)

  self._udp_first_time = true

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
    and string.rep("\0", 12)
    or string.rep("\0", 24)
  self._packetBuffer = string.rep("\0", 12)

	if self._encryption == 'aead_xchacha20_poly1305_rtpsize' then
		self._crypto = sodium.aead_xchacha20_poly1305
	elseif self._encryption == 'aead_aes256_gcm_rtpsize' then
    assert(sodium.aead_aes256_gcm, 'aead_aes256_gcm is not avaliable on your system')
		self._crypto = sodium.aead_aes256_gcm
	else
		return error('unsupported encryption mode: ' .. self._mode)
	end

  p(sodium)

  self._playTimeout = nil
  self._audioStream = nil
end

-- * Useful methods
function Voice:voiceStateUpdate(obj)
  self._sessionId = obj.session_id
end

function Voice:voiceServerUpdate(endpoint, token)
  self._voiceServer.token = token
  self._voiceServer.endpoint = endpoint
end

function Voice:updateState(state)
  self:emit('stateChange', self._state, state)
  self._state = state
end

function Voice:updatePlayerState(state)
  self:emit('playerStateChange', self._playerState, state)
  self._playerState = state
end

-- * Internal methods
function Voice:ipDiscovery()
	local packet = string.pack('>I2I2I4c64H', 0x1, 70,
    self._udpInfo.ssrc,
    self._udpInfo.ip,
    self._udpInfo.port
  )

  self._udp:send(packet, self._udpInfo.port, self._udpInfo.ip)

  local success, data = self:waitFor('rawudp', 20000)

  assert(success, data)

	return {
    ip = string.unpack('xxxxxxxxz', data),
    port = string.unpack('>I2', data, #data - 1)
  }
end

-- * Main methods
function Voice:connect(cb, reconnect)
  if self._ws then
    self._ws:close(1000, 'Normal close')
  end

  local uri = sf('wss://%s/?v=8', self._voiceServer.endpoint)

  self._ws = WebSocket({
    url = uri,
    headers = {
      { 'User-Agent', 'DiscordBot (https://github.com/LunaticSea/LunaStream)' }
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
    print('[LunaStream / Voice | WS] ' .. data.payload)
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

-- * Handling ws message
function Voice:handleMessage(cb, payload)
  if payload.seq then
		self._seq_ack = payload.seq
	end

  if payload.op == READY then
    return self:handleReady(payload)
  elseif payload.op == DESCRIPTION then
    self._udpInfo.secretKey = self._crypto.key(payload.d.secret_key)
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

-- * Handling udp connection
function Voice:handleReady(ws_payload)
  self._udpInfo.ssrc = ws_payload.d.ssrc
  self._udpInfo.ip = ws_payload.d.ip
  self._udpInfo.port = ws_payload.d.port

  self._udp = dgram.createSocket('udp4')

  self._udp:recvStart()

  self._udp:on('message', function (packet, rinfo, flags)
    self:emit('rawudp', packet, rinfo, flags)

    print('[LunaStream / Voice | UDP]: Received data from UDP server with Discord.')

    if self._udp_first_time then
      self._udp_first_time = false
      return
    end

    if #packet < 12 then return end

    local first_byte, payload_type, sequence, timestamp, ssrc = string.unpack(HEADER_FMT, packet)

    local _, userData = pcall(function() return self._ssrcs[ssrc] end)
    if not userData or not self._udpInfo.secretKey then return end

    local rtp_version = bit.rshift(first_byte, 6)
    local has_padding = bit.band(first_byte, 0x20) == 0x20
    local has_extension = bit.band(first_byte, 0x10) == 0x10
    local num_csrc = bit.band(first_byte, 0x0F)
    if rtp_version ~= 2 then
      print('[LunaStream / Voice | UDP]: invalid RTP version')
      return
    elseif payload_type ~= 0x78 then
      print('[LunaStream / Voice | UDP]: invalid payload type')
      return
    end

    local header_len = 12 + num_csrc * 4
    local extension_len = 0

    if has_extension then
      extension_len = string.unpack('>I2', packet, header_len + 3) * 4
      header_len = header_len + 4
    end

    local payload = ffi.cast('const char *', packet) + header_len
    local payload_len = #packet - header_len - 4

    if payload_len < 0 then
      return nil, 'invalid payload length'
    end

    local nonce_bytes = packet:sub(-4)
    ---@diagnostic disable-next-line: cast-local-type
    nonce = self._crypto.nonce(nonce_bytes)

    local message, message_len = self._crypto.decrypt(
      payload, payload_len, packet, header_len, nonce, self._udpInfo.secretKey
    )
    if not message then
      return nil, message_len -- report error
    end

    if has_padding then
      local padding_len = message[message_len - 1]
      if padding_len > message_len then
        return nil, 'invalid padding length'
      end
      message_len = message_len - padding_len
    end

    if self._udp_first_time then
      self._udp_first_time = false
    end

    local decrypted_packet = ffi.string(message + extension_len, message_len - extension_len)

    if decrypted_packet == OPUS_SILENCE_FRAME then
      if userData.stream._readableState.ended then return end

      self:emit('speakEnd', userData.userId, ssrc)
      userData.stream:push(nil)
      userData.stream._readableState.ended = true
    else
      if userData.stream._readableState.ended then
        userData.stream = stream.PassThrough:new()

        self:emit('speakStart', userData.userId, ssrc)
        userData.stream._readableState.ended = false
      end

      userData.stream:write(decrypted_packet)
    end
  end)

  self._udp:on('error', function (err)
    p('Error: ', err)
  end)

  local res = self:ipDiscovery()

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

end

-- * Heartbeat to keep alive with discord
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

-- * Voice control
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

  if self._udp then
    self._udp:recvStop()
    self._udp:removeAllListeners('message')
    self._udp:removeAllListeners('error')
    self._udp = nil
  end
end

return Voice