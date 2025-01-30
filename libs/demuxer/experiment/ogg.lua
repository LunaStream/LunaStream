local fs = require('fs')


local fileData = fs.readFileSync("../sample/speech_orig.ogg")

local capture_pattern = string.sub(fileData, 1, 4)
local version = string.byte(fileData, 5)
local header_type_flagsion = string.byte(fileData, 6)
local granule_position = string.unpack("<I8", fileData, 7)
local bitstream_serial_number = string.unpack("<I4", fileData, 15)
local page_sequence_number = string.unpack("<I4", fileData, 19)
local CRC_checksum = string.unpack("<I4", fileData, 23)
local number_page_segments = string.byte(fileData, 24)
local page_segments = string.unpack("<I1", fileData, 27)
local header_size = number_page_segments + 28
local seg_table = string.sub(fileData, 28, 28 + page_segments)

local sizes, totalSize = {}, 0

for i = 1, page_segments, 1 do
  local size, x = 0, 255
  while x == 255 do
    if i >= #seg_table then return false end
    x = string.unpack("<I1", i)
    size = size + x
  end
  table.insert(sizes, size)
  totalSize = totalSize + size
end

local template = [[

capture_pattern         | %s
version                 | %s
header_type_flagsion    | %s
granule_position        | %s
bitstream_serial_number | %s
page_sequence_number    | %s
CRC_checksum            | %s
number_page_segments    | %s
page_segments           | %s
header_size             | %s
]]

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

local start = 28 + page_segments
for _, size in pairs(sizes) do
  local segment = string.sub(fileData, start, start + size)
  local header = string.sub(segment, 1, 8)
  p(segment, header)
end

-- local page_size = header_size + sum(lacing_values: 1..number_page_segments)


-- 9. segment_table: number_page_segments Bytes containing the lacing
-- values of all segments in this page.  Each Byte contains one
-- lacing value.

-- The total header size in bytes is given by:
-- header_size = number_page_segments + 27 [Byte]

-- The total page size in Bytes is given by:
-- page_size = header_size + sum(lacing_values: 1..number_page_segments)
-- [Byte]

-- local number_page_segments = string.byte(fileData, 24)
-- p('number_page_segments: ' .. number_page_segments)
-- fs.readFile(filePath, function(err, data)
--   if err then
--     print("Error reading file:", err)
--     return
--   end
--   -- Call the demuxer to process the binary data
--   local packets = demuxer(data)
--   -- Output the number of packets extracted
--   print("Extracted", #packets, "packets.")
--   -- Optionally, process or print the packet data
--   for i, packet in ipairs(packets) do
--     print(string.format("Packet %d (size %d):", i, #packet))
--     print(string.sub(packet, 1, 32))  -- Print the first 32 bytes of the packet (just for demo)
--   end
-- end)