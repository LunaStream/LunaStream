local fs = require('fs')
local file_data = fs.readFileSync('../sample/speech_orig.webm')

local ebmlFound = false
local result = nil
local g_offset = 1
local count = 1
local skipUtil = nil
local _track = nil
local _incompleteTrack = {}
local processed = {}

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
  return {
    id = string.sub(data, t_offset, t_offset + idLength - 1),
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

local function _checkHead(data)
  if string.sub(data, 1, 8) ~= "OpusHead" then error('Audio codec is not Opus!') end
end

local function readTag(data, offset)
  local pass = 0
  p('Offset: ', offset)
  local idData = readEBMLId(data, offset)
  if idData == "TOO_SHORT" then return "TOO_SHORT" end
  pass = pass + 1
  local ebmlID = string.lower(stringToHex(idData.id))
  p('Current embl: ', idData, ebmlID)
  if not ebmlFound then
    if ebmlID == "1a45dfa3" then ebmlFound = true
    else error('Did not find the EBML tag at the start of the stream') end
  end

  offset = idData.offset

  -- Read header tag data size
  local sizeData = readTagDataSize(data, offset)
  if sizeData == "TOO_SHORT" then return "TOO_SHORT" end
  p('Size data: ', sizeData)
  pass = pass + 1
  offset = sizeData.offset

  local dataLength = sizeData.dataLength

  if type(TAGS[ebmlID]) == "nil" then
    if #data > offset + dataLength then
      return { offset = offset + dataLength, pass = pass };
    end
    return { offset = offset, skipUntil = count + offset + dataLength, pass = pass };
  end
  pass = pass + 1

  local tagHasChildren = TAGS[ebmlID];
  if tagHasChildren then
    return { offset = offset, pass = pass };
  end
  pass = pass + 1

  if offset + dataLength > #data then return 'TOO_SHORT' end
  pass = pass + 1
  local process_data = string.sub(data, offset, offset + dataLength)
  if not _track then
    if ebmlID == 'ae' then _incompleteTrack = {} end
    if ebmlID == 'd7' then
      -- p('-----[DEBUG]-----', process_data, process_data[1], offset, offset + dataLength, '-----[DEBUG]-----')
      -- p('-----[DEBUG]-----', string.byte(process_data, 1, 1), '-----[DEBUG]-----')
      _incompleteTrack.number = string.byte(process_data, 1, 1)
    end
    if ebmlID == '83' then
      -- p('-----[DEBUG]-----', process_data, process_data[1], offset, offset + dataLength, '-----[DEBUG]-----')
      -- p('-----[DEBUG]-----', string.byte(process_data, 1, 1), '-----[DEBUG]-----')
      _incompleteTrack.type = string.byte(process_data, 1, 1)
    end
    if _incompleteTrack.type == 2 and _incompleteTrack.number then
      _track = _incompleteTrack;
    end
  end

  if ebmlID == '63a2' then
    _checkHead(process_data)
  elseif ebmlID == 'a3' then
    if not _track then error('No audio track in this webm!') end
    if bit.band(string.byte(process_data, 1, 1), 0xF) == _track.number then
      table.insert(processed, string.sub(process_data, 4))
    end
  end
  pass = pass + 1
  return { offset = offset + dataLength, pass = pass };
end

while #file_data > g_offset do
  local success
  success, result = pcall(readTag, file_data, g_offset)
  if not success then
    p('Error: ', result)
    p('Remaining', #file_data - g_offset)
    return
  end
  p('Read done, pass: ', result.pass)
  if result == "TOO_SHORT" then
    p('TOO_SHORT detected! Watch your eyes mf')
    break
  end
  if result.offset then g_offset = result.offset
  -- if result.skipUntil then
  --   skipUtil = result.skipUntil;
  else break end
end

p()
p('ebmlFound', ebmlFound)
p('result', result)
p('g_offset', g_offset)
p('file length', #file_data)
p('count', count)
p('skipUtil', skipUtil)
p('_track', _track)
p('_incompleteTrack', _incompleteTrack)
p('processed: ', #processed)
p()

-- while result ~= "TOO_SHORT" do
--   local success
--   success, result = pcall(readTag, file_data, g_offset)
--   if not success then
--     p('Error: ', result)
--     return
--   end
--   p('Read done, pass: ', result.pass)
--   if result == "TOO_SHORT" then
--     p('TOO_SHORT detected! Watch your eyes mf')
--     break
--   end
--   if result.offset then g_offset = result.offset
--   -- if result.skipUntil then
--   --   skipUtil = result.skipUntil;
--   else break end
-- end