local required = {
  "title",
  "author",
  "length",
  "identifier",
  "isStream",
  "uri"
}

local bufferArray = {}

local function writeByte(value)
  table.insert(bufferArray, string.char(value))
end

local function writeUshort(value)
  table.insert(bufferArray, string.char(math.floor(value / 256)) .. string.char(value % 256))
end

local function writeInt(value)
  table.insert(bufferArray, string.char(math.floor(value / (256^3)) % 256) ..
  string.char(math.floor(value / (256^2)) % 256) ..
  string.char(math.floor(value / 256) % 256) ..
  string.char(value % 256))
end

local function writeLong(value)
  table.insert(bufferArray, string.char(math.floor(value / (256^7)) % 256) ..
  string.char(math.floor(value / (256^6)) % 256) ..
  string.char(math.floor(value / (256^5)) % 256) ..
  string.char(math.floor(value / (256^4)) % 256) ..
  string.char(math.floor(value / (256^3)) % 256) ..
  string.char(math.floor(value / (256^2)) % 256) ..
  string.char(math.floor(value / 256) % 256) ..
  string.char(value % 256))
end

local function writeUTF(value)
  local utf8bytes = {}
  for i = 1, #value do
    local byte = string.byte(value, i)
    table.insert(utf8bytes, byte)
  end
  writeUshort(#utf8bytes)
  for _, byte in ipairs(utf8bytes) do
    table.insert(bufferArray, string.char(byte))
  end
end

local function toBase64(input)
  local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local output = {}
  local padding = #input % 3
  local paddingBytes = padding == 0 and 0 or 3 - padding
  input = input .. string.rep("\0", paddingBytes)
  for i = 1, #input, 3 do
    local a = string.byte(input, i)
    local b = string.byte(input, i + 1)
    local c = string.byte(input, i + 2)
    table.insert(output, b64chars:sub(math.floor(a / 4) + 1, math.floor(a / 4) + 1))
    table.insert(output, b64chars:sub(((a % 4) * 16) + math.floor(b / 16) + 1, ((a % 4) * 16) + math.floor(b / 16) + 1))
    table.insert(output, b64chars:sub(((b % 16) * 4) + math.floor(c / 64) + 1, ((b % 16) * 4) + math.floor(c / 64) + 1))
    table.insert(output, b64chars:sub(c % 64 + 1, c % 64 + 1))
  end
  if paddingBytes > 0 then
    for i = 1, paddingBytes do
      output[#output - i + 1] = '='
    end
  end
  return table.concat(output)
end

return function (track)
  if #bufferArray > 0 then bufferArray = {} end

  for _, value in pairs(required) do
    if track[value] == nil then
      return nil, "Missing field: " .. value
    end
  end

  local version = (track.artworkUrl or track.isrc) and 3 or (track.uri and 2 or 1)
  local isVersioned = version > 1 and 1 or 0
  local firstInt = isVersioned * 2^30
  writeInt(firstInt)

  if isVersioned == 1 then
    writeByte(version)
  end

  writeUTF(track.title)
  writeUTF(track.author)
  writeLong(track.length)
  writeUTF(track.identifier)
  writeByte(track.isStream and 1 or 0)

  if version >= 2 then
    writeByte(track.uri and 1 or 0)
    if track.uri then
      writeUTF(track.uri)
    end
  end

  if version == 3 then
    writeByte(track.artworkUrl and 1 or 0)
    if track.artworkUrl then
      writeUTF(track.artworkUrl)
    end
    writeByte(track.isrc and 1 or 0)
    if track.isrc then
      writeUTF(track.isrc)
    end
  end
  
  writeUTF(track.sourceName)
  writeLong(track.position or 0)
  return toBase64(table.concat(bufferArray))
end