local fs = require('fs')
local Readable = require('stream').Readable
local bind = require('utils').bind

local FileStream = fs.ReadStream:extend()

local read_options = {
  flags = "r",
  mode = "0644",
  chunkSize = 65536,
  fd = nil,
  reading = nil,
  length = nil, -- nil means read to EOF
}

local read_meta = { __index = read_options }

function FileStream:initialize(path, options)
  Readable.initialize(self, { objectMode = true })
  if not options then
    options = read_options
  else
    setmetatable(options, read_meta)
  end
  self.fd = options.fd
  self.mode = options.mode
  self.path = path
  self.offset = options.offset
  self.chunkSize = options.chunkSize
  self.length = options.length
  self.bytesRead = 0
  if not self.fd then
    self:open()
  end
  self:on('end', bind(self.close, self))
end

function FileStream:open()
  self.fd = fs.openSync(self.path, self.flags, self.mode)
  if type(self.fd) ~= "number" then
    self:destroy()
    self:emit('error', self.fd)
    self.fd = nil
  end
end

function FileStream:_read(n)
  local to_read = self.chunkSize or n

  if self.length then
    if to_read + self.bytesRead > self.length then
      to_read = self.length - self.bytesRead
    end
  end

  local bytes = fs.readSync(self.fd, to_read, self.offset)
  if type(bytes) ~= "string" then
    return self:destroy(bytes)
  end

  if #bytes > 0 then
    self.bytesRead = self.bytesRead + #bytes
    if self.offset then
      self.offset = self.offset + #bytes
    end
    self:push(bytes)
  else
    self:close()
    self:push({})
  end
end

function FileStream:close()
  self:destroy()
end

function FileStream:destroy(err)
  if err then
    self:emit('error', err)
  end
  if self.fd then
    fs.close(self.fd)
    self.fd = nil
  end
end

return FileStream
