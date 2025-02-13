local Readable = require('stream').Readable

local HttpStream = Readable:extend()

function HttpStream:initialize(str, chunk_size)
  Readable.initialize(self)
  self._len = #str
	self._str = str
  self.offset = 0
  self.chunk_size = chunk_size or 65536
end

function HttpStream:_read(n)
  n = self.chunk_size or n
  local i = self._i or 1
	if i + n < self._len then
    self.offset = self.offset + n
		local data = string.sub(self._str, i, self.offset)
		self._i = i + n
    self:push(data)
		return
	end
  self:push()
end

return HttpStream