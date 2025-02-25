local timer = require('timer')
local class = require('class')
local voice = require('../voice')
local Player = class('Player')
local decoder = require('../track/decoder')
local audioDecoder = require('audioDecoder')
local json = require('json')

function Player:__init(luna, guildId, sessionId)
  self._luna = luna
  self._stream = nil
  self._sessionId = sessionId
  self._guildId = guildId
  self._userId = self._luna.sessions[sessionId].user_id
  self._write = self._luna.sessions[sessionId].write
  self._state = { time = 0, position = 0, connected = false, ping = -1 }
  self.track = {}
  self.playing = false
  self.position = 0
  self.endTime = 0
  self.volume = 0
  self.paused = false
  self.filters = {}
  self.voiceState = {}
  self.state = {}
  self.voice = voice(self._guildId, self._userId)
  self.update_loop_interval = nil
  self.close_connection_function = nil
end

function Player:new()
  return self
end

function Player:updateVoiceState(voiceState)
  if not voiceState then
    return
  end

  self.voiceState = voiceState

  if not self.voice then
    self.voice = voice(self._guildId, self._userId)
  end

  self.voice:voiceCredential(voiceState.sessionId, voiceState.endpoint, voiceState.token)
  self.voice:connect()
  self._state.connected = true
end

function Player:play(track)
  if self.track.encoded ~= nil and self.playing == true then
    self:stop()
  end

  self.track = decoder(track.encoded)

  if track.userData == nil or next(track.userData) == nil then
    track.userData = nil
  end

  self._luna.logger:info('Player', string.format('Playing track %s', self.track.info.title))

  local stream, format = self._luna.sources:getStream(self.track)

  if not stream then
    self._luna.logger:error('Player', 'Failed to load stream')
    return
  end

  self.close_connection_function = function()
    if stream.connection and stream.connection.socket.close then
      return stream.connection.socket:close()
    end
  end

  if format == "mp3" then
    self._stream = stream
  else
    self._stream = stream:pipe(audioDecoder.opus:new(self.voice._opus))
  end

  if self.voice then
    self.voice:play(self._stream, { encoder = true })

    self._luna.logger:info(
      'Player', string.format('Track %s started for guild %s', self.track.info.title, self._guildId)
    )

    self:sendWsMessage(
      {
        op = "event",
        type = "TrackStartEvent",
        guildId = self._guildId,
        track = self.track,
      }
    )

    self.playing = true

    self:_startUpdateLoop()

    self.voice:once(
      "ended", function()
        self._luna.logger:info(
          'Player', string.format('Track %s ended for guild %s', self.track.info.title, self._guildId)
        )

        self:sendWsMessage(
          {
            op = "event",
            type = "TrackEndEvent",
            guildId = self._guildId,
            track = self.track,
          }
        )

        self.playing = false
        self.state = {
          time = 0,
          position = 0,
          connected = self._state.connected,
          ping = self.voice.ping,
        }

        self:sendWsMessage(
          { op = "playerUpdate", guildId = self._guildId, state = self.state }
        )
        timer.clearInterval(self.update_loop_interval)
        self.update_loop_interval = nil
      end
    )
  end
end

function Player:stop()
  if self.voice then
    self.voice:stop()
    self.close_connection_function()
    self.playing = false
    self._luna.logger:info(
      'Player', string.format('Track %s stopped for guild %s', self.track.info.title, self._guildId)
    )
  end
end

function Player:pause()
  if self.voice then
    self.voice:pause()
    self.paused = true
    self._luna.logger:info(
      'Player', string.format('Track %s paused for guild %s', self.track.info.title, self._guildId)
    )
  end
end

function Player:resume()
  if self.voice then
    self.voice:resume()
    self.paused = false
    self._luna.logger:info(
      'Player', string.format('Track %s resumed for guild %s', self.track.info.title, self._guildId)
    )
  end
end

function Player:seek(position)
  -- //TODO: Implement seeking
end

function Player:setVolume(volume)
  -- //TODO: Implement volume control, wait VolumeTransformer implementation
end

function Player:setFilters(filters)
  -- //TODO: Implement filters
end

function Player:destroy()
  self:stop()
  if self.voice then
    self.voice:destroy()
    self.voice = nil
  end
  if self.update_loop_interval then
    timer.clearInterval(self.update_loop_interval)
    self.update_loop_interval = nil
  end
  self._luna.logger:info('Player', string.format('Player for guild %s destroyed', self._guildId))
  collectgarbage("collect")
end

function Player:sendWsMessage(data)
  local payload = json.encode(data)
  coroutine.wrap(
    function()
      self._write({ opcode = 1, payload = payload })
    end
  )()
end

function Player:_sendPlayerUpdate()
  if not self.playing then
    return
  end

  self.state = {
    time = os.time(),
    position = self.voice.position,
    connected = self._state.connected,
    ping = self.voice.ping,
  }

  self:sendWsMessage(
    { op = "playerUpdate", guildId = self._guildId, state = self.state }
  )
end

function Player:_startUpdateLoop()
  self.update_loop_interval = timer.setInterval(
    5000, function()
      coroutine.wrap(self._sendPlayerUpdate)(self)
    end
  )
end

return Player
