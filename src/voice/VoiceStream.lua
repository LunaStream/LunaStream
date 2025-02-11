local class = require('class')
local uv = require('uv')

local VoiceStream = class('VoiceStream')

local OPUS_SAMPLE_RATE    = 48000
local OPUS_CHANNELS       = 2
local OPUS_FRAME_DURATION = 20
-- Size of chucks to read from the stream at a time
local OPUS_CHUNK_SIZE     = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION / 1000
local MS_PER_NS = 1 / (1000 * 1000)
local cache = nil

function FMT(n)
  return '<' .. string.rep('i2', n)
end

local function sleep(delay)
	local thread = coroutine.running()
	local t = uv.new_timer()
	t:start(delay, 0, function()
		t:stop()
		t:close()
		return assert(coroutine.resume(thread))
	end)
	return coroutine.yield()
end

function VoiceStream:__init(voiceManager, passthrough_class)
  self._cache = {}
  self._passthrough_class = passthrough_class:new()
  self._voiceManager = voiceManager
  self._currentProcessing = false
  self._elapsed = 0
end

function VoiceStream:setup()
  print('[LunaStream w/VoiceStream]: Now using custom stream')
  local start = uv.hrtime()

  self._passthrough_class:on('raw-pcm-data', function (chunk)
    coroutine.wrap(function ()
      if self._currentProcessing then
        table.insert(self._cache, chunk)
      else
        self:chunkPass(chunk, start)
        self:intervalHandling(start)
      end
    end)()
  end)

  self._voiceManager._stream:pipe(self._passthrough_class)
end

function VoiceStream:intervalHandling(start)
  while #self._cache ~= 0 do
    local nextChunk = table.remove(self._cache, 1)
    self:chunkPass(nextChunk, start)
  end
  self._currentProcessing = false
end

function VoiceStream:chunkPass(chunk, start)
  self._currentProcessing = true
  local pcmLen = OPUS_CHUNK_SIZE * OPUS_CHANNELS

  local audioChuck = { string.unpack(FMT(pcmLen), chunk) }

  table.remove(audioChuck)

  print('[LunaStream / Voice / ' .. self._voiceManager.guild_id .. ' / VoiceStream]: Sending voice packet, elapsed: ', self._elapsed)

  local encodedData, encodedLen
  if self._voiceManager._opusEncoder then
    encodedData, encodedLen = self._voiceManager._opusEncoder:encode(audioChuck, pcmLen, OPUS_CHUNK_SIZE, pcmLen * 2)
  else
    encodedData = audioChuck
    encodedLen = #audioChuck
  end
  local audioPacket = coroutine.wrap(self._voiceManager._prepareAudioPacket)(
    self._voiceManager, encodedData, encodedLen,
    self._voiceManager.udp.ssrc, self._voiceManager.udp._sec_key
  )
  if not audioPacket then
    print('[LunaStream / Voice / ' .. self._voiceManager.guild_id .. ']: audio packet is nil/lost')
    self._voiceManager._packetStats.lost = self._voiceManager._packetStats.lost + 1
  else
    self._voiceManager.udp:send(audioPacket)
  end
  self._elapsed = self._elapsed + OPUS_FRAME_DURATION
  local delay = self._elapsed - (uv.hrtime() - start) * MS_PER_NS
  sleep(math.max(delay, 0))
end

return VoiceStream