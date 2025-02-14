local Readable = require('stream').Readable

local HttpStream = Readable:extend()

function HttpStream:initialize(str, chunk_size)
  Readable.initialize(self)
  self._str = str
  self.chunk_size = chunk_size or 65536
end

function HttpStream:_read(n)
  n = self.chunk_size or n
	if n < #self._str then
		local data = string.sub(tostring(self._str), 1, self.chunk_size)
    self:push(data)
    self._str = string.sub(tostring(self._str), self.chunk_size + 1)
    collectgarbage('collect')
		return
	end
  self:push()
  self._str = nil
  collectgarbage('collect')
end

return HttpStream