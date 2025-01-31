local fs = require('fs')
local file_data = fs.readFileSync('../sample/speech_orig.webm')

local offset = 1

local TAGS = {
  ['1a45dfa3'] = true, -- EBML
  ['18538067'] = true, -- Segment
  ['1f43b675'] = true, -- Cluster
  ['1654ae6b'] = true, -- Tracks
  ['ae'] = true, -- TrackEntry
  ['d7'] = false, -- TrackNumber
  ['83'] = false, -- TrackType
  ['a3'] = false, -- SimpleBlock
  ['63a2'] = false,
}

local function stringToHex(str)
  local hexStr = ""
  for i = 1, #str do
    hexStr = hexStr .. string.format("%02X", string.byte(str, i))
  end
  return hexStr
end

local function vintLength(buffer, index)
  if index < 1 or index > #buffer then
    return "TOO_SHORT"
  end

  local i = 0
  for j = 0, 7 do
    if bit.band(bit.lshift(1, 7 - j), string.byte(buffer, index)) ~= 0 then
      break
    end
    i = i + 1
  end
  i = i + 1

  if index + i - 1 > #buffer then
    return "TOO_SHORT"
  end

  return i
end

-- Bitwise operations for Lua 5.1 (using bit32 library)
-- You can also use other libraries like lua-bitop in Lua 5.1 if needed

local function expandVint(buffer, start, _end)
  local length = vintLength(buffer, start)  -- Assuming vintLength returns the length
  if _end > #buffer or length == "TOO_SHORT" then
      return "TOO_SHORT"
  end

  local mask = (bit.lshift(1, 8 - length)) - 1  -- bit32.lshift for bit shifting
  local value = bit.band(string.byte(buffer, start), mask)  -- band for bitwise AND

  for i = start + 1, _end - 1 do
      value = bit.lshift(value, 8) + string.byte(buffer, i)  -- left shift by 8, then add next byte
  end

  return value
end

local function readEBMLId(data, t_offset)
  local idLength = vintLength(data, t_offset)
  if idLength == "TOO_SHORT" then return "TOO_SHORT" end
  p(idLength)
  return {
    id = string.sub(data, t_offset, t_offset + idLength),
    offset = t_offset + idLength,
  };
end

local function readTagDataSize(data, t_offset)
  local sizeLength = vintLength(data, t_offset);
  if sizeLength == "TOO_SHORT" then return "TOO_SHORT" end
  local dataLength = expandVint(data, t_offset, t_offset + sizeLength);
  return {
    offset = t_offset + sizeLength,
    dataLength = dataLength,
    sizeLength = sizeLength
  };
end

-- Read header
local emblIdHeader = readEBMLId(file_data, offset)
offset = emblIdHeader.offset + offset - 1
p('Response data: ', emblIdHeader)
p('Offset: ', offset)

-- Read header tag data size
local headerSizeData = readTagDataSize(file_data, offset)
offset = headerSizeData.offset + offset - 1
p('Response data: ', headerSizeData)
p('Offset: ', offset)