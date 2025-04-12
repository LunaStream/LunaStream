local class = require('class')
local openssl = require('openssl')

local Decoder = class('Decoder')

function Decoder:__init(track)
  self._position = 1
  self._track = track
  self._buffer = openssl.base64(self._track, false)
end

function Decoder:changeBytes(bytes)
  self._position = self._position + bytes
  return self._position - bytes
end

function Decoder:readByte()
  local byte = self:changeBytes(1)
  return string.byte(self._buffer, byte)
end

function Decoder:readUnsignedShort()
  local byte = self:changeBytes(2)
  -- local highOrderByte = self._buffer:readByte(byte)
  -- local lowOrderByte = self._buffer:readByte(byte + 1)
  -- First byte (b1) is multiplied by 256 (2^8) since it represents the high-order byte
  -- Second byte (b2) is added as-is since it represents the low-order byte,
  -- implementing big-endian byte ordering (most significant byte first)
  local b1, b2 = string.byte(self._buffer, byte, byte + 1)
  return b1 * 256 + b2
end

function Decoder:readInt()
  local byte = self:changeBytes(4)
  -- The first byte (b1) is most significant bit (MSB)
  local b1, b2, b3, b4 = string.byte(self._buffer, byte, byte + 3)
  local num = b1 * 256^3 + b2 * 256^2 + b3 * 256 + b4

  -- using this as total bytes are calculated already
  -- instead of MSB sign detection (b1 > 127).
  if num > 2147483647 then
    num = num - 4294967296
  end
  return num
end

function Decoder:readLong()
  local msb = self:readInt()
  local lsb = self:readInt()

  return msb * (2 ^ 32) + lsb
end

function Decoder:readUTF()
  local len = self:readUnsignedShort()
  local start = self:changeBytes(len)
  return string.sub(self._buffer, start, start + len - 1)
end

function Decoder:getTrack()
  local success, result = pcall(Decoder.getTrackUnsafe, self)
  if not success then
    print("Error:", result)
    return nil
  end
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
  local success, result = pcall(
    function()
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
          sourceName = string.lower(self:readUTF()),
          position = self:readLong(),
        },
        pluginInfo = {},
      }
    end
  )

  if not success then
    -- TODO: Use luna's logger
    p('Error while decoding track version 1', result)
    return nil
  end
  return result
end

function Decoder:trackVersionTwo()
  local success, result = pcall(
    function()
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
          sourceName = string.lower(self:readUTF()),
          position = self:readLong(),
        },
        pluginInfo = {},
      }
    end
  )

  if not success then
    -- TODO: Use luna's logger
    p('Error while decoding track version 2', result)
    return nil
  end
  return result
end

function Decoder:trackVersionThree()
  local success, result = pcall(
    function()
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
          sourceName = string.lower(self:readUTF()),
          position = self:readLong(),
        },
        pluginInfo = {},
      }
    end
  )

  if not success then
    -- TODO: Use luna's logger
    p('Error while decoding track version 3', result)
    return nil
  end
  return result
end

return function(input)
  return Decoder(input):getTrack()
end
