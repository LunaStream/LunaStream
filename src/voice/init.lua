-- External library
local class = require('class')
local timer = require('timer')
local ffi   = require('ffi')

-- Internal Library
local Emitter = require('./Emitter')
local WebSocket = require('./WebSocket')
local Opus = require('opus')
local UDPController = require('./UDPController')

-- Useful functions
local sf = string.format
local setInterval = timer.setInterval
local clearInterval = timer.clearInterval
local setTimeout = timer.setTimeout
local clearTimeout = timer.clearTimeout

-- OP code
local IDENTIFY        = 0
local SELECT_PROTOCOL = 1
local READY           = 2
local HEARTBEAT       = 3
local DESCRIPTION     = 4
local SPEAKING        = 5
local RESUME          = 7
local HELLO           = 8
-- local RESUMED         = 9

-- Vitural enums
local VOICE_STATE = {
  disconnected = 'disconnected',
  connected = 'connected',
}
local PLAYER_STATE = {
  idle = 'idle',
  playing = 'playing',
}

-- Constants

local OPUS_SAMPLE_RATE    = 48000
local OPUS_CHANNELS       = 2
local OPUS_FRAME_DURATION = 20
-- Size of chucks to read from the stream at a time
local OPUS_CHUNK_SIZE     = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION / 1000


local VoiceManager, get = class('VoiceManager', Emitter)

function VoiceManager:__init(guildId, userId, production_mode)
  Emitter.__init(self)
  -- Basic data
  self._guild_id = guildId
  self._user_id = userId
  self._heartbeat = nil

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
  self._timestamp = -1


  -- UDP
  self._udp = UDPController(production_mode)
  self._encryption = self._udp._crypto._mode
  self._opus = Opus(production_mode)
  self._nonce = 0

  self._packetStats = {
    sent = 0,
    lost = 0,
    expected = 0,
  }

  self._stream = NULL

  self._nextAudioPacketTimestamp = NULL

  self._opusEncoder = NULL
end

function VoiceManager:voiceCredential(session_id, endpoint, token)
  self._session_id = session_id or self.session_id
  self._endpoint = endpoint or self.endpoint
  self._token = token or self.token
end

function VoiceManager:connect(reconnect)
  if self.ws then
    self.ws:close(1000, 'Normal close')
  end

  local uri = sf('wss://%s/', self.endpoint)

  self._ws = WebSocket({
    url = uri,
    path = '/?v=8',
    headers = {
      { 'User-Agent', 'DiscordBot (https://github.com/LunaticSea/LunaStream)' }
    }
  })

  self.ws:on('open', function ()
    self.ws:send({
      op = reconnect and RESUME or IDENTIFY,
      d = {
        server_id = self.guild_id,
        session_id = self.session_id,
        token = self.token,
        seq_ack = reconnect and self._seq_ack or nil,
        user_id = reconnect and nil or self._user_id,
      }
    })
  end)

  self.ws:on('message', function (data)
    print('[LunaStream / Voice | WS ]: ' .. data.payload)
    self:messageEvent(data.json_payload)
  end)

  self.ws:on('close', function (code, reason)
    --- @diagnostic disable-next-line: undefined-global
    p(code, reason)
    if not self.ws then return end
    self:destroyConnection(code, reason)
  end)

  self.ws:connect()
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
    self.udp:updateCredentials(nil, nil, nil, data.secret_key)
    self._voice_state = VOICE_STATE.connected
    self._player_state = PLAYER_STATE.idle
    self._ready = true
    self:emit('ready')
  elseif op == HELLO then
    self:startHeartbeat(data.heartbeat_interval)
  end
end

function VoiceManager:readyOP(ws_payload)
  self.udp:updateCredentials(
    ws_payload.d.ip,
    ws_payload.d.port,
    ws_payload.d.ssrc,
    nil
  )

  local res = self.udp:ipDiscovery()

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

  self.udp:start()
end

function VoiceManager:startHeartbeat(heartbeat_timeout)
  self._heartbeat = setInterval(heartbeat_timeout, function()
    coroutine.wrap(VoiceManager.sendKeepAlive)(self)
  end)
end

function VoiceManager:sendKeepAlive()
  if not self._ws then return end
  self._ws:send({
    op = HEARTBEAT,
    d = {
      t = os.time(),
      seq_ack = self.seq_ack
    }
  })
end

function VoiceManager:destroyConnection(code, reason)
  if self.heartbeat then
    clearInterval(self.heartbeat)
    self._heartbeat = nil
  end

  if self.ws then
    self.ws:cleanEvents()
    self._ws = nil
  end

  self.udp:stop()
end

--- Sets the speaking state
---@param speaking integer speaking mode to set (0 = not speaking, 1(1 << 0) = Microphone, 2(1 << 1) = Soundshare, 4(1 << 2) = Priority)
---@return integer speaking state given to it
function VoiceManager:setSpeaking(speaking)
  self._ws:send({
    op = SPEAKING,
    d = {
      speaking = speaking,
      delay = 0,
      ssrc = self.udp.ssrc,
    }
  })

  return speaking
end

--- Plays a audio stream through the voice connection
---@param stream any
function VoiceManager:play(stream, needs_encoder)
  -- Just in case, play gets triggered when _ws is not present;
  if not self._ws then
    print('[LunaStream / Voice / ' .. self._guild_id .. ']: Voice connection is not ready')

    return
  end;
  if self._stream and self._stream._readableState.ended == false then
    error("Already playing a stream")
  end;

  print('[LunaStream / Voice / ' .. self.guild_id .. ']: Playing audio stream...')

  self._stream = stream

  self:setSpeaking(1)
  if needs_encoder then
    self._opusEncoder = self._opus.encoder(OPUS_SAMPLE_RATE, OPUS_CHANNELS)
  end

  self._nextAudioPacketTimestamp = os.time() + OPUS_FRAME_DURATION
  print('[LunaStream / Voice / ' ..
  self.guild_id .. ']: Next audio packet timestamp: ' .. self._nextAudioPacketTimestamp - os.time())
  self:_startAudioPacketInterval()

  self._player_state = PLAYER_STATE.playing
end

function VoiceManager:_prepareAudioPacket(opus_data, opus_length, ssrc, key)
  -- TODO: Implement max value handle
  self._seq_ack = self._seq_ack + 1
  self._timestamp = self._timestamp + OPUS_CHUNK_SIZE
  self._nonce = self._nonce + 1

  -- print(self._seq_ack, self._timestamp, self._nonce, ssrc, key)
  local packetWithBasicInfo = string.pack('>BBI2I4I4', 0x80, 0x78, self._seq_ack, self._timestamp, ssrc)

  local nonce = self._udp._crypto:nonce(self._nonce)
  local nonce_padding = ffi.string(nonce, 4)

  local encryptedAudio, encryptedAudioLen = self._udp._crypto:encrypt(opus_data, opus_length, packetWithBasicInfo,
    #packetWithBasicInfo, nonce, key)

  self._packetStats.expected = self._packetStats.expected + 1;

  if not encryptedAudio then
    return nil, encryptedAudioLen
  end

  return packetWithBasicInfo .. ffi.string(encryptedAudio, encryptedAudioLen) .. nonce_padding
end

function VoiceManager:_startAudioPacketInterval()
  self._audioPacketTimeout = setTimeout(self._nextAudioPacketTimestamp - os.time(), function()
    print('[LunaStream / Voice / ' ..
    self.guild_id .. ']: running audio Packet Timeout ' .. self._nextAudioPacketTimestamp, self._nextAudioPacketTimestamp - os.time())
    local pcmLen = OPUS_CHUNK_SIZE * OPUS_CHANNELS
    local audioChuck = self._stream:read(pcmLen)

    -- p(audioChuck, pcmLen, OPUS_CHUNK_SIZE, pcmLen * 2, self._opusEncoder)
    local encodedData, encodedLen
    if self._opusEncoder then
      encodedData, encodedLen = self._opusEncoder:encode(audioChuck, pcmLen, OPUS_CHUNK_SIZE, pcmLen * 2)
    else
      encodedData = audioChuck
      encodedLen = #audioChuck
    end

    local audioPacket = coroutine.wrap(self._prepareAudioPacket)(self, encodedData, encodedLen, self.udp.ssrc,
      self.udp._sec_key)
    -- p("audioPacket sent:", "audioChunk: ", audioChuck, "\n AudioPacket: ", audioPacket)
    self._nextAudioPacketTimestamp = os.time() + OPUS_FRAME_DURATION

    if not audioPacket then
      print('[LunaStream / Voice / ' .. self.guild_id .. ']: audio packet is nil/lost')
      self._packetStats.lost = self._packetStats.lost + 1
      self:_startAudioPacketInterval()
      return
    end

    self.udp:send(audioPacket)

    self:_startAudioPacketInterval()
  end)
end

function get:guild_id()
  return self._guild_id
end

function get:user_id()
  return self._user_id
end

function get:voice_state()
  return self._voice_state
end

function get:player_state()
  return self._player_state
end

function get:session_id()
  return self._session_id
end

function get:endpoint()
  return self._endpoint
end

function get:token()
  return self._token
end

function get:ws()
  return self._ws
end

function get:seq_ack()
  return self._seq_ack
end

function get:udp()
  return self._udp
end

function get:encryption()
  return self._encryption
end

function get:heartbeat()
  return self._heartbeat
end

return VoiceManager
