local class = require('class')
local Buffer = require('buffer').Buffer
local openssl = require('openssl')

local Decoder = class('Decoder')

function Decoder:__init(track)
  self._position = 1
  self._track = track
  self._buffer = Buffer:new(openssl.base64(self._track, false))
end

function Decoder:changeBytes(bytes)
  self._position = self._position + bytes
  return self._position - bytes
end

function Decoder:readByte()
  local byte = self:changeBytes(1)
  return self._buffer[byte]
end

function Decoder:readUnsignedShort()
  local byte = self:changeBytes(2)
  return self._buffer:readUInt16BE(byte)
end

function Decoder:readInt()
  local byte = self:changeBytes(4)
  return self._buffer:readInt32BE(byte)
end

function Decoder:readLong()
  local msb = self:readInt()
  local lsb =  self:readInt()

  return msb * (2 ^ 32) + lsb
end

function Decoder:readUTF()
  local len = self:readUnsignedShort()
  local start = self:changeBytes(len)
  local result = self._buffer:toString(start, start + len - 1)
  return result
end

function Decoder:getTrack()
  local success, result = pcall(Decoder.getTrackUnsafe, self)
  if not success then return nil end
  return result
end

function Decoder:getTrackUnsafe()
  local isVersioned = bit.band(bit.rshift(self:readInt(), 30), 1) ~= 0
  local version = isVersioned and self:readByte() or 1
  if version == 1 then
    return self:trackVersionOne()
  elseif version == 2 then
    return self:trackVersionTwo()
  elseif version == 3 then
    return self:trackVersionThree()
  else
    return nil
  end
end

function Decoder:trackVersionOne()
  local success, result = pcall(function ()
    return {
      encoded = self._track,
      info = {
        title = self:readUTF(),
        author = self:readUTF(),
        length = self:readLong(),
        identifier = self:readUTF(),
        isSeekable = true,
        isStream = self:readByte() ~= 0,
        uri = nil,
        artworkUrl = nil,
        isrc = nil,
        sourceName =  string.lower(self:readUTF()),
        position = self:readLong(),
      },
      pluginInfo = {},
    }
  end)

  if not success then return nil end
  return result
end

function Decoder:trackVersionTwo()
  local success, result = pcall(function ()
    return {
      encoded = self._track,
      info = {
        title = self:readUTF(),
        author = self:readUTF(),
        length = self:readLong(),
        identifier = self:readUTF(),
        isSeekable = true,
        isStream = self:readByte() ~= 0,
        uri = self:readByte() and self:readUTF() or nil,
        artworkUrl = nil,
        isrc = nil,
        sourceName =  string.lower(self:readUTF()),
        position = self:readLong(),
      },
      pluginInfo = {},
    }
  end)

  if not success then return nil end
  return result
end

function Decoder:trackVersionThree()
  local success, result = pcall(function ()
    return {
      encoded = self._track,
      info = {
        title = self:readUTF(),
        author = self:readUTF(),
        length = self:readLong(),
        identifier = self:readUTF(),
        isSeekable = true,
        isStream = self:readByte() ~= 0,
        uri = self:readByte() ~= 0 and self:readUTF() or nil,
        artworkUrl = self:readByte() ~= 0 and self:readUTF() or nil,
        isrc = self:readByte() ~= 0 and self:readUTF() or nil,
        sourceName =  string.lower(self:readUTF()),
        position = self:readLong(),
      },
      pluginInfo = {},
    }
  end)

  if not success then return nil end
  return result
end


return function(input)
  return Decoder(input):getTrack()
end