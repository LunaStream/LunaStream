local class = require('class')
local uv = require('uv')
local PCMReader = require('./PCMReader')

local VoiceStream = class('VoiceStream')

local OPUS_SAMPLE_RATE    = 48000
local OPUS_CHANNELS       = 2
local OPUS_FRAME_DURATION = 20
local OPUS_CHUNK_SIZE     = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION / 1000
local MS_PER_NS = 1 / (1000 * 1000)

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

local function asyncResume(thread)
	local t = uv.new_timer()
	t:start(0, 0, function()
		t:stop()
		t:close()
		return assert(coroutine.resume(thread))
	end)
end

function VoiceStream:__init(voiceManager, filters)
  self._cache = {}
  self._passthrough_class = PCMReader:new()
  self._voiceManager = voiceManager
  self._current_processing = false
  self._elapsed = 0
  self._filters = filters or {}
  self._paused = false
  self._finished_transform = false
  self._stop = false
end

function VoiceStream:setup()
  local start = uv.hrtime()

  self._passthrough_class:on('raw-pcm-data', function (chunk)
    if self._stop then return end
    coroutine.wrap(function ()
      if self._current_processing then
        table.insert(self._cache, chunk)
      else
        if self._paused then
          table.insert(self._cache, chunk)
        else
          self:chunkPass(chunk, start)
          self:intervalHandling(start)
        end
      end
    end)()
  end)

  self._passthrough_class:on('end', function ()
    print('[LunaStream / Voice / ' .. self._voiceManager.guild_id .. ']: Finished transforming, ready for sending silence frame before stopping')
    self._finished_transform = true
  end)

  self._voiceManager._stream:pipe(self._passthrough_class)
  return self
end

function VoiceStream:intervalHandling(start)
  while #self._cache ~= 0 do
    if self._stop then break end
    if self._paused then
      asyncResume(self._paused)
			self._paused = coroutine.running()
			local pause = uv.hrtime()
			coroutine.yield()
			start = start + uv.hrtime() - pause
			asyncResume(self._resumed)
			self._resumed = nil
    end
    local nextChunk = table.remove(self._cache, 1)
    self:chunkPass(nextChunk, start)
  end
  if self._finished_transform then
    self:clear()
    self._voiceManager:stop()
    return
  end
  if not self._paused then
    self._current_processing = false
    return
  end
end

function VoiceStream:addFilter(filterClass)
  self._filters[filterClass.__name] = filterClass
end

function VoiceStream:removeFilter(name)
  self._filters[name] = nil
end

function VoiceStream:chunkMixer(chunk)
  if #self._filters == 0 then return chunk end
  local res = chunk
  for _, filterClass in pairs(self._filters) do
    res = filterClass:convert(chunk)
  end
  return res
end

function VoiceStream:pause()
	-- if not self._speaking then return end
	if self._paused then return end
	self._paused = coroutine.running()
	return coroutine.yield()
end

function VoiceStream:resume()
	if not self._paused then return end
	asyncResume(self._paused)
	self._paused = nil
	self._resumed = coroutine.running()
	return coroutine.yield()
end

function VoiceStream:stop()
  self._passthrough_class:removeAllListeners()
  self._voiceManager._stream:removeAllListeners()
  self._stop = true
end

function VoiceStream:chunkPass(chunk, start)
  self._current_processing = true

  chunk = self:chunkMixer(chunk)

  local pcmLen = OPUS_CHUNK_SIZE * OPUS_CHANNELS

  local audioChuck = { string.unpack(FMT(pcmLen), chunk) }

  table.remove(audioChuck)

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
    self._voiceManager.udp:send(audioPacket, function (err)
      local curr_lost = self._voiceManager._packetStats.lost
      local curr_sent = self._voiceManager._packetStats.sent
      if err then
        print('[LunaStream / Voice / ' .. self._voiceManager.guild_id .. ']: audio packet is nil/lost')
        self._voiceManager._packetStats.lost = curr_lost + 1
      else
        print('[LunaStream / Voice / ' .. self._voiceManager.guild_id .. ']: audio packet sent, elapsed: ', self._elapsed)
        self._voiceManager._packetStats.sent = curr_sent + 1
      end
    end)
  end
  self._elapsed = self._elapsed + OPUS_FRAME_DURATION
  local delay = self._elapsed - (uv.hrtime() - start) * MS_PER_NS
  sleep(math.max(delay, 0))
end

function VoiceStream:clear()
  self._cache = {}
  self._passthrough_class = PCMReader:new()
  self._current_processing = false
  self._elapsed = 0
  self._paused = false
  self._finished_transform = false
  self._stop = false
end

return VoiceStream