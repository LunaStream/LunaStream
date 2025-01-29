local Transform = require('stream').Transform

local OggDemuxer = Transform:extend()

local OGG_PAGE_HEADER_SIZE = 26;
local STREAM_STRUCTURE_VERSION = 0;
local OGGS_HEADER = 'OggS'
local OPUS_HEAD = 'OpusHead'
local OPUS_TAGS = 'OpusTags'

function OggDemuxer:initialize(options)
  options = options or {}
  Transform.initialize(self, { table.unpack(options), objectMode = true })
  self._remainder = nil
  self._head = nil
  self._bitstream = nil
  self._first_read = true
end

function OggDemuxer:_transform(chunk, done)
  if self._remainder then
    chunk = table.concat({ self._remainder, chunk })
    self._remainder = nil;
  end

  while chunk do
    local success, result = pcall(self._readPage, self, chunk)
    if not success then
      done(result)
      return
    end
    if result then chunk = result
    else break end
  end
  self._remainder = chunk
  done(nil)
end

function OggDemuxer:_readUInt32BE(chunk, offset)
  local byte1 = string.byte(chunk, offset)
  local byte2 = string.byte(chunk, offset + 1)
  local byte3 = string.byte(chunk, offset + 2)
  local byte4 = string.byte(chunk, offset + 3)

  return byte1 * 0x1000000 + byte2 * 0x10000 + byte3 * 0x100 + byte4
end

function OggDemuxer:_readPage(chunk)
  if #chunk < OGG_PAGE_HEADER_SIZE then return false end
  if string.sub(chunk, 1, 4) ~= OGGS_HEADER and self._first_read then
    error('capture_pattern is not ' .. OGGS_HEADER)
  end
  if string.byte(chunk, 5) ~= STREAM_STRUCTURE_VERSION and self._first_read then
    error('stream_structure_version is not ' .. STREAM_STRUCTURE_VERSION)
  end
  self._first_read = false

  if #chunk < 28 then return false end
  local pageSegments = string.byte(chunk, 27)
  if #chunk < 28 + pageSegments then return false end
  local tbl = string.sub(chunk, 27, 27 + pageSegments)
  local bitstream = self:_readUInt32BE(chunk, 15)
  local sizes = {}
  local totalSize = 0

  -- Have no idea but if failed, just + 1
  for i = 1, pageSegments, 1 do
    local size = 0
    local x = 255
    while x == 255 do
      if i >= #tbl then return false end
      x = string.byte(tbl, i + 1)
      size = size + x
    end
    table.insert(sizes, size)
    totalSize = totalSize + size;
  end

  -- Have no idea about 27 is so + 1 if failed
  if #chunk < 27 + pageSegments + totalSize then return false end

  local start = 27 + pageSegments;
  for _, size in pairs(sizes) do
    local segment = string.sub(chunk, start, start + size)
    local header = string.sub(chunk, 1, 9)
    if self._head then
      if header == OPUS_TAGS then self:emit('tags', segment)
      elseif self._bitstream == bitstream then self:push(segment) end
    elseif header == OPUS_HEAD then
      self:emit('head', segment);
      self._head = segment;
      self._bitstream = bitstream;
    else
      self:emit('unknownSegment', segment);
    end
    start = start + size;
  end
  return string.sub(chunk, start)
end

function OggDemuxer:_destroy(err, cb)
  self:_cleanup()
  return cb and cb(err) or nil
end

function OggDemuxer:_final(cb)
  self:_cleanup()
  return cb()
end

function OggDemuxer:_cleanup()
  self._remainder = nil
  self._head = nil
  self._bitstream = nil
end

function OggDemuxer:write(chunk)
  self._readableState.pipes:_write(chunk, function () end)
end

return OggDemuxer