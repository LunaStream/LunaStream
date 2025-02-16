local timer = require('timer')
local class = require('class')
local voice = require('../voice')
local Player = class('Player')
local decoder = require('../track/decoder')
local MusicUtils = require('musicutils')
local json = require('json')

local setTimeout = timer.setTimeout
function Player:__init(luna, guildId, sessionId)
  self._luna = luna
  self._stream = nil
  self._sessionId = sessionId
  self._guildId = guildId
  self._userId = self._luna.sessions[sessionId].user_id
  self._write = self._luna.sessions[sessionId].write
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
end

function Player:play(track)
    if self.track.encoded ~= nil and self.playing == true then
        self:stop()
    end

    self.track.info = decoder(track.encoded)
    self.track.encoded = track.encoded
    if track.userData == nil or next(track.userData) == nil then
        track.userData = nil
    end

    self._luna.logger:info('Player', string.format('Playing track %s', self.track.info.title))

    self._stream = self._luna.sources:getStream(decoder(track.encoded)):pipe(MusicUtils.opus.Decoder:new(self.voice._opus))

    if self.voice then
        self.voice:play(self._stream, {
                encoder = true,
        })

        self._luna.logger:info('Player', string.format('Track %s started for guild %s', self.track.info.title, self._guildId))
        self:sendWsMessage({
            op = "event",
            type = "TrackStartEvent",
            guildId = self._guildId,
            track = self.track,
        })

        self.playing = true

        self.voice:on("ended", function()
            self._luna.logger:info('Player', string.format('Track %s ended for guild %s', self.track.info.title, self._guildId))
            self:sendWsMessage({
                op = "event",
                type = "TrackEndEvent",
                guildId = self._guildId,
                track = self.track,
            })

            self.playing = false
        end)
    end
end

function Player:stop()
    if self.voice then
        self.voice:stop()
        self.playing = false
        self._luna.logger:info('Player', string.format('Track %s stopped for guild %s', self.track.info.title, self._guildId))
    end
end

function Player:sendWsMessage(data)
    local payload = json.encode(data)
    coroutine.wrap(function()
        self._write({
            opcode = 1,
            payload = payload
        })
    end)()
  end


return Player
