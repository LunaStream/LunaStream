local Transform = require('stream').Transform

local WebmBaseDemuxer = Transform:extend()

local TOO_SHORT = 'TOO_SHORT'

local TAGS = { -- value is true if the element has children
  ['1a45dfa3'] = true, -- EBML
  ['18538067'] = true, -- Segment
  ['1f43b675'] = true, -- Cluster
  ['1654ae6b'] = true, -- Tracks
  ['ae'] = true, -- TrackEntry
  ['d7'] = false, -- TrackNumber
  ['83'] = false, -- TrackType
  ['a3'] = false, -- SimpleBlock
  ['63a2'] = false,
};

local function toHex(str)
  return (str:gsub('.', function(c)
    return string.format('%02X', string.byte(c))
  end))
end

-- buffer is a string
local function vintLength(buffer, index)
  if index < 1 or index > #buffer then
    return TOO_SHORT
  end

  local byteValue = string.byte(buffer, index)
  local counter = 0

  for i = 0, 7 do
    if (bit.band(1, bit.lshift(byteValue, 7 - i)) ~= 0) then
      break
    end
    counter = counter + 1
  end

  counter = counter + 1

  if index + counter - 1 > #buffer then
    return TOO_SHORT
  end

  return counter
end

local function bitoper(a, b, oper)
   local r, m, s = 0, 2^31, nil
   repeat
      s,a,b = a+b+m, a%m, b%m
      r,m = r + m*oper%(s-a-b), m/2
   until m < 1
   return r
end

local function expandVint(buffer, start, _end)
  local length = vintLength(buffer, start)
  if _end > #buffer or length == TOO_SHORT then
    return TOO_SHORT
  end

  local mask = (bit.lshift(1, 8 - length)) - 1
  local value = bit.band(string.byte(buffer, start), mask)

  for i = start + 1, _end - 1 do
    value = bit.lshift(value, 8) + string.byte(buffer, i)
  end

  return value
end

function WebmBaseDemuxer:initialize(options)
  options = options or {}
  Transform.initialize(self, options)
  self._remainder = nil;
  self._length = 0;
  self._count = 0;
  self._skipUntil = nil;
  self._track = nil;
  self._incompleteTrack = {};
  self._ebmlFound = false;
end

function WebmBaseDemuxer:_checkHead(data)
  error('Missing check head function')
end

-- chunk is a buffer string
function WebmBaseDemuxer:_transform(chunk, encoding, done)
  self._length = self._length + #chunk

  if self._remainder then
    chunk = table.concat({ self._remainder, chunk })
    self._remainder = nil
  end

  local offset = 0

  if self._skipUntil and self._length > self._skipUntil then
    offset = self._skipUntil - self._count
    self._skipUntil = nil
  elseif self._skipUntil then
    self._count = self._count + #chunk
    done()
    return
  end

  local result
  while result ~= TOO_SHORT do
    local success, readTagData = pcall(self._readTag)(self, chunk, offset)

    if not success then
      done(readTagData)
      return
    end

    result = readTagData

    if result == TOO_SHORT then break end
    if result._skipUntil then
      self._skipUntil = result._skipUntil
      break
    end
    if result.offset then
      offset = result.offset
    else break end
  end

  self._count = self._count + offset
  self._remainder = string.sub(chunk, offset + 1)
  done()
end

-- chunk is a buffer string
function WebmBaseDemuxer:_readTag(chunk, offset)
  local idData = self:_readEBMLId(chunk, offset)
  if idData == TOO_SHORT then return TOO_SHORT end
  local ebmlID = toHex(idData.id)
  if self._ebmlFound then
    if ebmlID == '1a45dfa3' then self._ebmlFound = true
    else error('Did not find the EBML tag at the start of the stream') end
  end
  offset = idData.offset
  local sizeData = self:_readTagDataSize(chunk, offset)
  if sizeData == TOO_SHORT then return TOO_SHORT end
  local dataLength = sizeData.dataLength
  offset = sizeData.offset
  -- If this tag isn't useful, tell the stream to stop processing data until the tag ends
  if type(TAGS[ebmlID]) == "nil" then
    if #chunk > offset + dataLength then
      return { offset = offset + dataLength }
    end
    return { offset = offset, _skipUntil = self._count + offset + dataLength }
  end

  local tagHasChildren = TAGS[ebmlID];
  if (tagHasChildren) then
    return { offset = offset }
  end

  if offset + dataLength > #chunk then return TOO_SHORT end
  local data = string.sub(chunk, offset + 1, offset + dataLength)
  if self._track then
    if ebmlID == 'ae' then self._incompleteTrack = {} end
    if ebmlID == 'd7' then self._incompleteTrack.number = data[1] end
    if ebmlID == '83' then self._incompleteTrack.type = data[1] end
    if self._incompleteTrack.type == 2 and type(self._incompleteTrack.number) == "nil" then
      self._track = self._incompleteTrack;
    end
  end

  if ebmlID == '63a2' then
    self:_checkHead(data);
    self:emit('head', data);
  elseif ebmlID == 'a3' then
    if not self._track then error('No audio track in this webm!') end
    if bitoper(string.byte(data, 1), 0xF, 4) == self._track.number then
      self:push(string.sub(data, 5))
    end
  end
  return { offset = offset + dataLength };
end

function WebmBaseDemuxer:_readEBMLId(chunk, offset)
  local idLength = vintLength(chunk, offset);
  if idLength == TOO_SHORT then return TOO_SHORT end
  return {
    id =  string.sub(chunk, offset, offset + idLength),
    offset = offset + idLength,
  }
end

function WebmBaseDemuxer:_readTagDataSize(chunk, offset)
  local sizeLength = vintLength(chunk, offset);
  if sizeLength == TOO_SHORT then return TOO_SHORT end
  local dataLength = expandVint(chunk, offset, offset + sizeLength);
  return { offset = offset + sizeLength, dataLength, sizeLength };
end

function WebmBaseDemuxer:_destroy(err, cb)
  self:_cleanup()
  return cb and cb(err) or nil
end

function WebmBaseDemuxer:_final(cb)
  self:_cleanup()
  return cb()
end

function WebmBaseDemuxer:_cleanup()
  self._remainder = nil;
  self._incompleteTrack = {};
end

return WebmBaseDemuxer