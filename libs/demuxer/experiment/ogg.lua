local head_detected = nil
local bitstream_serial_signature = nil

local valid_segments = {}
local invalid_segments = {}
local current_offset = 0

--[[
In the ogg file, segment will split into the page
Each page have header to help you know the current bitstream
The target of this code is to valid the segment and push
to valid_segments
]]

local function readTableByTable(buffer)
  -- This will tell if the pattern match
  local capture_pattern = string.sub(buffer, 1, 4)
  -- This tell the version number
  local version = string.byte(buffer, 5)
  -- This will tell the header type flag
  local header_type_flagsion = string.byte(buffer, 6)
  -- This wwill tell the current granule position
  local granule_position = string.unpack("<I8", buffer, 7)
  -- This will tell the bitstream serial number for verification
  local bitstream_serial_number = string.unpack("<I4", buffer, 15)
  -- This will tell the page sequence number
  local page_sequence_number = string.unpack("<I4", buffer, 19)
  -- This will tell the tell the checksum for this bitstream
  local CRC_checksum = string.unpack("<I4", buffer, 23)
  -- This will tell tell the size of the page
  local number_page_segments = string.byte(buffer, 24)
  local page_segments = string.unpack("<I1", buffer, 27)

  local header_size = number_page_segments + 28
  local seg_table = string.sub(buffer, 28, 28 + page_segments)

  local sizes = {}
  local totalSize = 0
  local i = 1 -- Lua uses 1-indexing

  while i <= page_segments do
    local size = 0
    local x = 255

    while x == 255 do
      if i > #seg_table then
        return false
      end
      x = string.byte(seg_table, i)  -- string.byte returns the byte value at position i
      i = i + 1
      size = size + x
    end

    table.insert(sizes, size)
    totalSize = totalSize + size
  end

  local template = [[
-------------------------------------------
Bitstream infomation:
-------------------------------------------
capture_pattern         | %s
version                 | %s
header_type_flagsion    | %s
granule_position        | %s
bitstream_serial_number | %s
page_sequence_number    | %s
CRC_checksum            | %s
number_page_segments    | %s
page_segments           | %s
header_size             | %s]]

  print(string.format(template,
    capture_pattern,
    version,
    header_type_flagsion,
    granule_position,
    bitstream_serial_number,
    page_sequence_number,
    CRC_checksum,
    number_page_segments,
    page_segments,
    header_size,
    seg_table
  ))
  p('Total seg sizes: ', totalSize)
  p('Sizes: ', sizes)

  local start = 28 + page_segments

  p('-------------------------------------------')
  for _, size in pairs(sizes) do
    local segment = string.sub(buffer, start, start + size)
    local header = string.sub(segment, 1, 8)
    p('Preview segment: ', string.sub(segment, 1, 10))
    if head_detected then
      if header == "OpusTags" then p('Hey, this is opus tag :O')
      elseif bitstream_serial_signature == bitstream_serial_number then
        table.insert(valid_segments, segment)
      end
    elseif header == 'OpusHead' then
      head_detected = segment
      bitstream_serial_signature = bitstream_serial_number
    else
      table.insert(invalid_segments, segment)
    end
    start = start + size;
  end
  p('-------------------------------------------')

  p('Preview: ', string.sub(buffer, start, start + 20))
  p('New offset: ', start)
  current_offset = current_offset + start
  return string.sub(buffer, start)
end

local fs = require('fs')
local fileData = fs.readFileSync("../sample/speech_orig.ogg")

local temp = nil
while #fileData > current_offset do
  temp = readTableByTable(temp and temp or fileData)
end

p('Total valid segments: ', #valid_segments)
p('Total invalid segments: ', #invalid_segments)
p('Please check if code missing any content: ', current_offset, #fileData)

fs.writeFileSync('../results/speech_orig.ogg.segment', table.concat(valid_segments, '\n\n'))