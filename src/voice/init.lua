-- External Libraries
local class = require('class')
local timer = require('timer')
local ffi = require('ffi')
local uv = require('uv')
local prettyPrint = require('pretty-print')

-- Internal Libraries
local Emitter = require('./Emitter')
local WebSocket = require('./WebSocket')
local Opus = require('opus')
local UDPController = require('./UDPController')

-- Useful Functions
local sf = string.format
local setInterval = timer.setInterval
local clearInterval = timer.clearInterval

-- OP Codes
local IDENTIFY = 0
local SELECT_PROTOCOL = 1
local READY = 2
local HEARTBEAT = 3
local DESCRIPTION = 4
local SPEAKING = 5
local HEARTBEAT_ACK = 6
local RESUME = 7
local HELLO = 8
-- local RESUMED      = 9

-- Virtual Enums
local VOICE_STATE = { disconnected = 'disconnected', connected = 'connected' }
local PLAYER_STATE = { idle = 'idle', playing = 'playing' }

-- Constants
local OPUS_SAMPLE_RATE = 48000
local OPUS_CHANNELS = 2
local OPUS_FRAME_DURATION = 20
-- Size of chunks read from the audio stream
local OPUS_CHUNK_SIZE = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION / 1000
local OPUS_CHUNK_STRING_SIZE = OPUS_CHUNK_SIZE * 2 * 2
local OPUS_SILENCE_FRAME = '\248\255\254'
local MS_PER_NS = 1 / (1000 * 1000) -- Conversion from nanoseconds to milliseconds

-- Maximum Values Constants for RTP
local MAX_SEQUENCE = 0xFFFF
local MAX_TIMESTAMP = 0xFFFFFFFF
local MAX_NONCE = 0xFFFFFFFF

---------------------------------------------------------------
-- Function: FMT
-- Parameters: n (number) - number of 2-byte integers to pack.
-- Objective: Returns a format string for packing 'n' 2-byte integers.
---------------------------------------------------------------
function FMT(n)
  return '<' .. string.rep('i2', n)
end

---------------------------------------------------------------
-- Function: sleep
-- Parameters: delay (number) - delay time in milliseconds.
-- Objective: Pauses the current coroutine execution for the specified delay using a uv timer.
---------------------------------------------------------------
local function sleep(delay)
  local thread = coroutine.running()
  local t = uv.new_timer()
  t:start(
    delay, 0, function()
      t:stop()
      t:close()
      return assert(coroutine.resume(thread))
    end
  )
  return coroutine.yield()
end

---------------------------------------------------------------
-- Function: asyncResume
-- Parameters: thread (coroutine) - the coroutine to resume asynchronously.
-- Objective: Resumes the provided coroutine asynchronously using a uv timer.
---------------------------------------------------------------
local function asyncResume(thread)
  local t = uv.new_timer()
  t:start(
    0, 0, function()
      t:stop()
      t:close()
      return assert(coroutine.resume(thread))
    end
  )
end

---------------------------------------------------------------
-- Function: truncate
-- Parameters: num (number) - the number to truncate.
-- Objective: Truncates a number towards zero.
---------------------------------------------------------------
local function truncate(num)
  if num >= 0 then
    return math.floor(num)
  else
    return math.ceil(num)
  end
end

---------------------------------------------------------------
-- Function: round_then_truncate
-- Parameters: num (number) - the number to round and then truncate.
-- Objective: Rounds the number (adding 0.5 then flooring) and then truncates it.
---------------------------------------------------------------
local function round_then_truncate(num)
  local rounded = math.floor(num + 0.5)
  return truncate(rounded)
end

---------------------------------------------------------------
-- Function: splitByChunk
-- Parameters: 
--    text (string) - the text to split,
--    chunkSize (number) - the size of each chunk.
-- Objective: Splits a string into chunks of the specified size and returns them as an array.
---------------------------------------------------------------
local function splitByChunk(text, chunkSize)
  local s = {}
  for i = 1, #text, chunkSize do
    s[#s + 1] = text:sub(i, i + chunkSize - 1)
  end
  return s
end

---------------------------------------------------------------
-- Class Definition: VoiceManager
-- Inherits from: Emitter
-- Objective: Manages voice connections, streaming, and audio packet handling.
---------------------------------------------------------------
local VoiceManager, get = class('VoiceManager', Emitter)

---------------------------------------------------------------
-- Constructor: __init
-- Parameters:
--    guildId (string) - Guild identifier.
--    userId (string) - User identifier.
--    opus_class (table) - Add opus class if exists
--    production_mode (boolean) - Flag to indicate production mode.
-- Objective: Initializes a new VoiceManager instance with basic data, state, and required components.
---------------------------------------------------------------
function VoiceManager:__init(guildId, userId, opus_class, production_mode)
  Emitter.__init(self)
  -- Basic Data
  self._guild_id = guildId
  self._user_id = userId
  self._heartbeat = nil

  -- State
  self._voice_state = VOICE_STATE.disconnected
  self._player_state = PLAYER_STATE.idle

  -- Voice Credentials
  self._session_id = nil
  self._endpoint = nil
  self._token = nil

  -- Gateway
  self._ws = nil
  self._seq_ack = -1
  self._timestamp = -1
  self._lastHeartbeatSent = 0
  self._ping = -1

  -- UDP
  self._udp = UDPController(production_mode)
  self._encryption = self._udp._crypto._mode

  if opus_class then
    p('Use exist')
    self._opus = opus_class
  else
    p('Use new')
    self._opus = Opus(self:getBinaryPath('opus', production_mode))
  end

  self._nonce = 0

  self._packetStats = { sent = 0, lost = 0, expected = 0 }

  self._stream = nil
  self._voiceStream = nil

  -- Challenge
  self._challenge = nil
  self._challenge_timeout = 2000

  -- Audio Stream
  self._elapsed = 0
  self._start = 0
  self._filters = {}
  self._chunk_cache = {} -- Queue of chunks ready to send
  self._buffer = "" -- Buffer to accumulate data that does not yet form a complete chunk
  self._bufferPos = 0 -- Position in the buffer to start reading from
  self._opusEncoder = nil

  -- Memory debug value
  self._mem_before = process.memoryUsage()
end

---------------------------------------------------------------
-- Function: getBinaryPath
-- Parameters:
--    name (string) - name of the binary/library.
--    production (boolean) - production mode flag.
-- Objective: Returns the binary path for the given library based on the OS and production mode.
---------------------------------------------------------------
function VoiceManager:getBinaryPath(name, production)
  local os_name = require('los').type()
  local arch = os_name == 'darwin' and 'universal' or jit.arch
  local lib_name_list = { win32 = '.dll', linux = '.so', darwin = '.dylib' }
  local bin_dir = string.format('./bin/%s/%s/%s%s', name, os_name, arch, lib_name_list[os_name])
  return production and './native/' .. name or bin_dir
end

---------------------------------------------------------------
-- Function: voiceCredential
-- Parameters:
--    session_id (string) - session identifier.
--    endpoint (string) - voice server endpoint.
--    token (string) - authentication token.
-- Objective: Sets the voice credentials for the connection.
---------------------------------------------------------------
function VoiceManager:voiceCredential(session_id, endpoint, token)
  self._session_id = session_id or self.session_id
  self._endpoint = endpoint or self.endpoint
  self._token = token or self.token
end

---------------------------------------------------------------
-- Function: connect
-- Parameters:
--    reconnect (boolean) - flag indicating whether this is a reconnection.
-- Objective: Establishes a WebSocket connection for voice communication, handling reconnection if needed.
---------------------------------------------------------------
function VoiceManager:connect(reconnect)
  if self.ws then
    self.ws:close(1000, 'Normal close')
  end

  local uri = sf('wss://%s/', self.endpoint)

  self._ws = WebSocket(
    {
      url = uri,
      path = '/?v=8',
      headers = { { 'User-Agent', 'DiscordBot (https://github.com/LunaticSea/LunaStream)' } },
    }
  )

  self.ws:on(
    'open', function()
      self.ws:send(
        {
          op = reconnect and RESUME or IDENTIFY,
          d = {
            server_id = self.guild_id,
            session_id = self.session_id,
            token = self.token,
            seq_ack = reconnect and self._seq_ack or nil,
            user_id = reconnect and nil or self._user_id,
          },
        }
      )
    end
  )

  self.ws:on(
    'message', function(data)
      self:emit('debug', 'WebSocket | ' .. data.payload)
      self:messageEvent(data.json_payload)
    end
  )

  self.ws:on(
    'close', function(code, reason)
      --- @diagnostic disable-next-line: undefined-global
      if not self.ws then
        return
      end
      self:destroyConnection(code, reason)
    end
  )

  self.ws:connect()
end

---------------------------------------------------------------
-- Function: messageEvent
-- Parameters:
--    payload (table) - the incoming WebSocket message payload.
-- Objective: Handles incoming messages by dispatching operations based on the opcode.
---------------------------------------------------------------
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
  elseif op == HEARTBEAT_ACK then
    local elapsed_ns = uv.hrtime() - self._lastHeartbeatSent
    self._ping = math.floor(elapsed_ns / 1000000)
    self:emit('debug', 'Heartbeat ACK received, ping: ' .. self.ping .. 'ms')
  end
end

---------------------------------------------------------------
-- Function: readyOP
-- Parameters:
--    ws_payload (table) - payload received from the READY opcode.
-- Objective: Handles the READY operation by updating UDP credentials, performing IP discovery, and selecting the UDP protocol.
---------------------------------------------------------------
function VoiceManager:readyOP(ws_payload)
  self.udp:updateCredentials(ws_payload.d.ip, ws_payload.d.port, ws_payload.d.ssrc, nil)

  local res = self.udp:ipDiscovery()

  self._ws:send(
    {
      op = SELECT_PROTOCOL,
      d = {
        protocol = 'udp',
        data = { address = res.ip, port = res.port, mode = self._encryption },
      },
    }
  )

  self.udp:on('message', function ()
    self:emit('debug', 'UDP       | Received data from UDP server with Discord.')
  end)

  self.udp:on('error', function ()
    self:emit('debug', 'UDP       | Received error from UDP server with Discord.')
  end)

  self.udp:start()
end

---------------------------------------------------------------
-- Function: startHeartbeat
-- Parameters:
--    heartbeat_timeout (number) - time interval for heartbeat in milliseconds.
-- Objective: Starts sending heartbeat messages at regular intervals to maintain the connection.
---------------------------------------------------------------
function VoiceManager:startHeartbeat(heartbeat_timeout)
  self._heartbeat = setInterval(
    heartbeat_timeout, function()
      coroutine.wrap(VoiceManager.sendKeepAlive)(self)
    end
  )
end

---------------------------------------------------------------
-- Function: sendKeepAlive
-- Parameters: None
-- Objective: Sends a heartbeat message to keep the WebSocket connection alive.
---------------------------------------------------------------
function VoiceManager:sendKeepAlive()
  if not self._ws then
    return
  end
  self._lastHeartbeatSent = uv.hrtime()
  self._ws:send({ op = HEARTBEAT, d = { t = os.time(), seq_ack = self.seq_ack } })
end

---------------------------------------------------------------
-- Function: destroyConnection
-- Parameters:
--    code (number) - WebSocket close code.
--    reason (string) - Reason for closing.
-- Objective: Cleans up and destroys the current WebSocket and UDP connection.
---------------------------------------------------------------
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

---------------------------------------------------------------
-- Function: setSpeaking
-- Parameters:
--    speaking (integer) - Speaking mode (0 = not speaking, 1 = microphone, etc).
-- Objective: Sets the "speaking" state by sending a speaking event via the WebSocket.
-- Returns: The speaking parameter.
---------------------------------------------------------------
--- Sets the speaking state.
--- @param speaking integer Speaking mode (0 = not speaking, 1 = microphone, etc)
--- @return integer
function VoiceManager:setSpeaking(speaking)
  self._ws:send(
    {
      op = SPEAKING,
      d = { speaking = speaking, delay = 0, ssrc = self.udp.ssrc },
    }
  )

  return speaking
end

---------------------------------------------------------------
-- Function: play
-- Parameters:
--    stream (any) - the audio stream to play.
--    options (table) - optional parameters (e.g., encoder, filters).
-- Objective: Starts the playback of the audio stream and begins sending audio chunks.
-- Returns: true if playback starts successfully.
---------------------------------------------------------------
--- Starts audio stream playback.
--- @param stream any The audio stream to play.
--- @param options table Optional parameters (e.g., encoder, filters).
function VoiceManager:play(stream, options)
  options = options or {}
  local needs_encoder = options.encoder or true
  self._filters = options.filters or {}

  if not self._ws then
    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Voice connection is not ready')
    return
  end
  if self._stream and self._stream._readableState.ended == false then
    error("Already playing a stream")
  end

  self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Playing audio stream...')

  self._stream = stream
  self:setSpeaking(1)
  if needs_encoder then
    self._opusEncoder = self._opus.encoder(OPUS_SAMPLE_RATE, OPUS_CHANNELS)
  end

  self._player_state = PLAYER_STATE.playing

  -- Starts the timing and continuous flow of chunks within a coroutine
  self._start = uv.hrtime()
  self._elapsed = 0
  coroutine.wrap(
    function()
      self:continuousSend()
    end
  )()

  return true
end

---------------------------------------------------------------
-- Function: continuousSend
-- Parameters: None
-- Objective: Continuously sends audio chunks from the stream. After sending each chunk, it waits for the necessary delay,
--            accumulating data until a complete chunk is available. Stops when there is no more data or when stopped.
---------------------------------------------------------------
--- Continuously sends audio chunks from the stream.
function VoiceManager:continuousSend()
  while true do
    if self._stop then
      self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Stopping continuous chunk flow.')
      break
    end

    if self._paused then
      self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Stream paused, waiting to resume...')
      asyncResume(self._paused)
      self._paused = coroutine.running()
      local pause = uv.hrtime()
      coroutine.yield()
      self._start = self._start + uv.hrtime() - pause
      asyncResume(self._resumed)
      self._resumed = nil
    end

    local data = self:cacheReader()

    if type(data) == 'table' then
      self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Stream ended, no more data to send.')
      self._chunk_cache = {}
      self:clearChallenge()
      self:stop(true)
      break
    end

    -- If the chunk is nil, running a challenge that chunk have to
    -- pass a valid chunk before timeout
    if type(data) == "nil" then
      if self._challenge then goto continue end
      self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Chunk nil detected, setup timeout challenge')
      self._challenge = timer.setTimeout(self._challenge_timeout, coroutine.wrap(function ()
        self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Track stucked, pause the track')
        self:emit('stucked')
        self._challenge = nil
        self:pause()
      end))
      goto continue
    end

    self:clearChallenge()

    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Sending chunk...')
    self:packetSender(data)

    ::continue::

    -- Update elapsed time and calculate delay for the next chunk
    self._elapsed = self._elapsed + OPUS_FRAME_DURATION
    local delay = self._elapsed - (uv.hrtime() - self._start) * MS_PER_NS
    delay = math.max(delay, 0)
    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Next chunk will be sent in ' .. delay .. ' ms.')
    sleep(delay)
  end
end

---------------------------------------------------------------
-- Function: setChallengeTimeout
-- Parameters:
--    timeout (number) - The timeout amount in ms.
-- Objective: Set a challenge timeout when receive nil chunk
---------------------------------------------------------------
function VoiceManager:setChallengeTimeout(timeout)
  self._challenge_timeout = timeout
end

---------------------------------------------------------------
-- Function: clearChallenge
-- Objective: Clear the challenge if chunk valided and still running
---------------------------------------------------------------
function VoiceManager:clearChallenge()
  if self._challenge then
    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Chunk valid, challenge passed')
    timer.clearTimeout(self._challenge)
    self._challenge = nil
  end
end

---------------------------------------------------------------
-- Function: cacheReader
-- Parameters: None
-- Objective: Reads data from the stream and returns a complete chunk for sending.
--            If the data is insufficient for a full chunk, it accumulates data in a buffer until complete.
---------------------------------------------------------------
--- Reads data from the stream and returns a complete chunk for sending.
function VoiceManager:cacheReader()
  local res

  if #self._chunk_cache > 0 then
    res = table.remove(self._chunk_cache, 1)
  else
    local data = self._stream:read()

    if type(data) ~= "string" then
      return data
    end

    if #data == OPUS_CHUNK_STRING_SIZE then
      return data
    else
      local caculation = round_then_truncate(#data / OPUS_CHUNK_STRING_SIZE)
      for _, mini_chunk in pairs(splitByChunk(data, round_then_truncate(#data / caculation))) do
        table.insert(self._chunk_cache, mini_chunk)
      end
    end

    res = table.remove(self._chunk_cache, 1)
  end

  return res
end

---------------------------------------------------------------
-- Function: packetSender
-- Parameters:
--    chunk (string) - the audio data chunk.
-- Objective: Encodes and sends an audio packet derived from the chunk, updating packet statistics.
---------------------------------------------------------------
function VoiceManager:packetSender(chunk)
  chunk = self:chunkMixer(chunk)

  local pcmLen = OPUS_CHUNK_SIZE * OPUS_CHANNELS

  if not chunk or #chunk < pcmLen then
    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Chunk too short')
    return
  end

  self._chunkTooShortCount = 0

  local audioChuck = { string.unpack(FMT(pcmLen), chunk) }
  table.remove(audioChuck)

  local encodedData, encodedLen
  if self._opusEncoder then
    encodedData, encodedLen = self._opusEncoder:encode(audioChuck, pcmLen, OPUS_CHUNK_SIZE, pcmLen * 2)
  else
    encodedData = audioChuck
    encodedLen = #audioChuck
  end

  local audioPacket = coroutine.wrap(self._prepareAudioPacket)(
    self, encodedData, encodedLen, self.udp.ssrc, self.udp._sec_key
  )

  if not audioPacket then
    self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | audio packet is nil/lost')
    self._packetStats.lost = self._packetStats.lost + 1
  else
    self.udp:send(
      audioPacket, function(err)
        local curr_lost = self._packetStats.lost
        local curr_sent = self._packetStats.sent
        if err then
          self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | audio packet is nil/lost')
          self._packetStats.lost = curr_lost + 1
        else
          self._packetStats.sent = curr_sent + 1
        end
      end
    )

    self._bufferPos = self._bufferPos + #chunk
    self:emit('debug', 
      'Stream    | ' .. self._guild_id .. ' | Position in buffer: ' .. string.format(
        "%02d:%02d:%02d", math.floor((self.position / 1000) / 3600), math.floor(((self.position / 1000) % 3600) / 60),
          math.floor((self.position / 1000) % 60)
      )
    )
  end
  encodedData, encodedLen, audioChuck, audioPacket = nil, nil, {}, nil
end

---------------------------------------------------------------
-- Function: addFilter
-- Parameters:
--    filterClass (table) - a filter class to apply.
-- Objective: Adds an audio filter to the VoiceManager.
---------------------------------------------------------------
function VoiceManager:addFilter(filterClass)
  self._filters[filterClass.__name] = filterClass
end

---------------------------------------------------------------
-- Function: removeFilter
-- Parameters:
--    name (string) - the name of the filter to remove.
-- Objective: Removes an audio filter from the VoiceManager.
---------------------------------------------------------------
function VoiceManager:removeFilter(name)
  self._filters[name] = nil
end

---------------------------------------------------------------
-- Function: chunkMixer
-- Parameters:
--    chunk (string) - the audio chunk.
-- Objective: Applies all added filters to the chunk and returns the modified data.
---------------------------------------------------------------
function VoiceManager:chunkMixer(chunk)
  if #self._filters == 0 then
    return chunk
  end
  local res = chunk
  for _, filterClass in pairs(self._filters) do
    res = filterClass:convert(chunk)
  end
  return res
end

---------------------------------------------------------------
-- Function: pause
-- Parameters: None
-- Objective: Pauses the audio streaming process.
---------------------------------------------------------------
function VoiceManager:pause()
  if self._paused then
    return
  end
  self._paused = coroutine.running()
  return coroutine.yield()
end

---------------------------------------------------------------
-- Function: resume
-- Parameters: None
-- Objective: Resumes the audio streaming process after being paused.
---------------------------------------------------------------
function VoiceManager:resume()
  if not self._paused then
    return
  end
  asyncResume(self._paused)
  self._paused = nil
  self._resumed = coroutine.running()
  return coroutine.yield()
end

---------------------------------------------------------------
-- Function: stop
-- Parameters: None
-- Objective: Stops the audio stream, cleans up resources, sends a silent frame, and emits the "ended" event.
---------------------------------------------------------------
function VoiceManager:stop(no_force_stop)
  self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Total stream stats: ', self._packetStats)

  if not no_force_stop then
    self:pause()
    self._stop = true
    self:resume()
  end

  if self._stream then
    self._stream:removeAllListeners()
    setmetatable(self._stream, { __mode = "kv" })
  end
  self._stream = nil

  self._chunk_cache = {}
  self._buffer = ""
  self._bufferPos = 0

  self._filters = {}
  self._opusEncoder = nil

  self._paused = nil
  self._resumed = nil

  self._packetStats = { sent = 0, lost = 0, expected = 0 }
  self._player_state = PLAYER_STATE.idle

  self.udp:send(
    OPUS_SILENCE_FRAME, function(err)
      if err then
        self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Failed to send opus silent frame!')
      else
        self:emit('debug', 'Stream    | ' .. self._guild_id .. ' | Opus silent frame sent!')
      end
    end
  )

  self:setSpeaking(0)
  self:emit("ended")

  self._stop = false

  collectgarbage('collect')
  self:emit('debug', 'Main | Memory before: ' .. prettyPrint.dump(self._mem_before, true, true))
  self:emit('debug', 'Main | Memory after: ' .. prettyPrint.dump(process.memoryUsage(), true, true))
end
---------------------------------------------------------------
-- Function: destroy
-- Parameters: None
-- Objective: Releases all resources associated with the VoiceManager instance,
--            stops the transmission, closes connections, and clears buffers and listeners.
---------------------------------------------------------------
function VoiceManager:destroy()
  self:stop(true)

  if self._heartbeat then
    clearInterval(self._heartbeat)
    self._heartbeat = nil
  end

  if self._ws then
    self._ws:close(1000, "Destroying VoiceManager")
    self._ws:cleanEvents()
    self._ws = nil
  end

  if self._udp then
    self._udp:stop()
    self._udp = nil
  end

  if self._stream then
    self._stream:removeAllListeners()
    self._stream = nil
  end

  self._chunk_cache = {}
  self._buffer = ""
  self._bufferPos = 0
  self._filters = {}
  self._opusEncoder = nil
  self._paused = nil
  self._resumed = nil
  self._packetStats = { sent = 0, lost = 0, expected = 0 }
  self._player_state = PLAYER_STATE.idle

  collectgarbage("collect")

  self:emit("destroy")
end

---------------------------------------------------------------
-- Function: _prepareAudioPacket
-- Parameters:
--    opus_data (string) - the raw opus audio data.
--    opus_length (number) - length of the opus data.
--    ssrc (number) - synchronization source identifier.
--    key (string) - encryption key.
-- Objective: Prepares an audio packet by packing header information, encrypting the audio data,
--            and updating packet statistics.
---------------------------------------------------------------
function VoiceManager:_prepareAudioPacket(opus_data, opus_length, ssrc, key)
  -- TODO: Implement maximum value control
  self._seq_ack = self._seq_ack >= MAX_SEQUENCE and 0 or self._seq_ack + 1
  self._timestamp = self._timestamp >= MAX_TIMESTAMP and 0 or self._timestamp + OPUS_CHUNK_SIZE
  self._nonce = self._nonce >= MAX_NONCE and 0 or self._nonce + 1

  local packetWithBasicInfo = string.pack('>BBI2I4I4', 0x80, 0x78, self._seq_ack, self._timestamp, ssrc)
  local nonce = self._udp._crypto:nonce(self._nonce)
  local nonce_padding = ffi.string(nonce, 4)

  local encryptedAudio, encryptedAudioLen = self._udp._crypto:encrypt(
    opus_data, opus_length, packetWithBasicInfo, #packetWithBasicInfo, nonce, key
  )

  self._packetStats.expected = self._packetStats.expected + 1

  if not encryptedAudio then
    return nil, encryptedAudioLen
  end

  return packetWithBasicInfo .. ffi.string(encryptedAudio, encryptedAudioLen) .. nonce_padding
end

---------------------------------------------------------------
-- Getters
---------------------------------------------------------------

-- Getter: guild_id
-- Returns the guild ID.
function get:guild_id()
  return self._guild_id
end

-- Getter: user_id
-- Returns the user ID.
function get:user_id()
  return self._user_id
end

-- Getter: voice_state
-- Returns the current voice connection state.
function get:voice_state()
  return self._voice_state
end

-- Getter: player_state
-- Returns the current audio player state.
function get:player_state()
  return self._player_state
end

-- Getter: Position
-- Returns the current position in the audio stream.
function get:position()
  if not self._bufferPos and self._bufferPos == 0 then
    return 0
  end
  return (self._bufferPos / OPUS_CHUNK_STRING_SIZE) * OPUS_FRAME_DURATION
end

-- Getter: session_id
-- Returns the session ID.
function get:session_id()
  return self._session_id
end

-- Getter: endpoint
-- Returns the voice server endpoint.
function get:endpoint()
  return self._endpoint
end

-- Getter: token
-- Returns the authentication token.
function get:token()
  return self._token
end

-- Getter: ws
-- Returns the WebSocket instance.
function get:ws()
  return self._ws
end

-- Getter: ping
-- Returns the current ping value.
function get:ping()
  return self._ping
end

-- Getter: seq_ack
-- Returns the current sequence acknowledgment value.
function get:seq_ack()
  return self._seq_ack
end

-- Getter: udp
-- Returns the UDP controller instance.
function get:udp()
  return self._udp
end

-- Getter: encryption
-- Returns the current encryption mode.
function get:encryption()
  return self._encryption
end

-- Getter: heartbeat
-- Returns the heartbeat timer.
function get:heartbeat()
  return self._heartbeat
end

return VoiceManager
