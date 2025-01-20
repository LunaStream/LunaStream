local class = require('class')
local json = require('json')
local timer = require('timer')
local dgram = require('dgram')
local buffer = require('buffer')
local stream = require('stream')

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
  self._seq_ack = nil
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

  self._ws = WebSocket({
    url = sf('wss://%s/?v=4', self._voiceServer.endpoint),
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
      self:_destroyConnection(code, reason)

      self:_updatePlayerState({ status = 'idle', reason  'reconnecting' })

      self:connect(function ()
        -- TODO: Dummy
        -- if self._audioStream then self:unpause('reconnected') end
      end, true)
    else
      self:_destroy({ status = 'disconnected', reason = 'closed', code, closeReason = reason }, false)
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
    self:_updateState({ status = 'connected' })
    self:_updatePlayerState({ status = 'idle', reason = 'connected' })
  elseif payload.op == HEARTBEAT_ACK then
    self._heartbeat_ack = payload.d
  elseif payload.op == SPEAKING then
    self._ssrc[payload.d.ssrc] = {
      userId = payload.d.user_id,
      stream = stream.PassThrough:new()
    }
    self:emit('speakStart', payload.d.user_id, payload.d.ssrc)
  elseif payload.op == HELLO then
    self._hbInterval = setInterval(payload.d.heartbeat_interval, function ()
      coroutine.wrap(self._ws.send)(self._ws, {
        op = HEARTBEAT,
        d = {
          t = os.time(),
          seq_ack = self._seq_ack
        }
      })
    end)
  end

end

function Voice:handleReady(payload)
  self._udpInfo.ssrc = payload.d.ssrc
  self._udpInfo.ip = payload.d.ip
  self._udpInfo.port = payload.d.port

  self._udp = dgram.createSocket('udp4')

  self._udp:on('message', function (data)

  end)

  --       if (data.length <= 8) return;

  --       const ssrc = data.readUInt32BE(8)
  --       const userData = ssrcs[ssrc]

  --       if (!userData || !this.udpInfo.secretKey) return;

  --       data.copy(this.nonceBuffer, 0, data.length - UNPADDED_NONCE_LENGTH)

  --       let headerSize = 12
  --       const first = data.readUint8()
  --       if ((first >> 4) & 0x01) headerSize += 4

  --       const header = data.subarray(0, headerSize)

  --       const encrypted = data.subarray(headerSize, data.length - AUTH_TAG_LENGTH - UNPADDED_NONCE_LENGTH)
  --       const authTag = data.subarray(
  --         data.length - AUTH_TAG_LENGTH - UNPADDED_NONCE_LENGTH,
  --         data.length - UNPADDED_NONCE_LENGTH
  --       )

  --       let packet = null
  --       switch (this.encryption) {
  --         case 'aead_aes256_gcm_rtpsize': {
  --           const decipheriv = crypto.createDecipheriv('aes-256-gcm', this.udpInfo.secretKey, this.nonceBuffer)
  --           decipheriv.setAAD(header)
  --           decipheriv.setAuthTag(authTag)
    
  --           packet = Buffer.concat([ decipheriv.update(encrypted), decipheriv.final() ])
  --         }
  --         case 'aead_xchacha20_poly1305_rtpsize': {
  --           packet = Buffer.from(
  --             Sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(
  --               Buffer.concat([ encrypted, authTag ]),
  --               header,
  --               this.nonceBuffer,
  --               this.udpInfo.secretKey
  --             )
  --           )
  --         }
  --       }

  --       if (data.subarray(12, 14).compare(HEADER_EXTENSION_BYTE) === 0) {
  --         const headerExtensionLength = data.subarray(14).readUInt16BE()
  --         packet = packet.subarray(4 * headerExtensionLength)
  --       }

  --       if (packet.compare(OPUS_SILENCE_FRAME) === 0) {
  --         if (userData.stream._readableState.ended) return;

  --         this.emit('speakEnd', userData.userId, ssrc)

  --         userData.stream.push(null)
  --       } else {
  --         if (userData.stream._readableState.ended) {
  --           userData.stream = new PassThrough()

  --           this.emit('speakStart', userData.userId, ssrc)
  --         }

  --         userData.stream.write(packet)
  --       }
  --     })

    -- self._udp.on('error', function (err)
    --   self:emit('error', err)
    -- end)

    -- self._udp.on('close', () => {
    --   if (!this.ws) return;
    --   this._destroy({ status: 'disconnected' })
    -- })

  --     const serverInfo = await this._ipDiscovery()

  -- self._ws:send({
  --   op = SELECT_PROTOCOL,
  --   d = {
  --     protocol = 'udp',
  --     data = {
  --       address = serverInfo.ip,
  --       port = serverInfo.port,
  --       mode = self._encryption
  --     }
  --   }
  -- })
end

function Voice:_updateState(state)
  self:emit('stateChange', self._state, state)
  self._state = state
end

function Voice:_updatePlayerState(state)
  self._emit('playerStateChange', self._playerState, state)
  self._playerState = state
end

function Voice:_destroy(state, destroyStream)
  self:_destroyConnection(1000, 'Normal closure')

  self._udpInfo = nil
  self._voiceServer = nil
  self._sessionId = nil
  if self._audioStream and destroyStream then
    -- TODO: Dummy
    self._audioStream:destroy()
    self._audioStream:removeAllListeners()
    self._audioStream = nil
  end

  self:_updateState(state)
  self:_updatePlayerState({ status = 'idle', reason = 'destroyed' })
end

function Voice:_destroyConnection(code, reason)
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
    self._udp:close()
    self._udp:removeAllListeners('message')
    self._udp:removeAllListeners('error')
    self._udp = nil
  end
end

function Voice:_ipDiscovery()
  return nil
end

function Voice:voiceStateUpdate(obj)
  self._sessionId = obj.session_id
end

function Voice:voiceServerUpdate(endpoint, token)
  self._voiceServer.token = token
  self._voiceServer.endpoint = endpoint
end

return Voice