local Readable = require('stream').Readable

local HttpStream = Readable:extend()

function HttpStream:initialize(str, chunk_size)
  Readable.initialize(self)
  self._str = str
  self.chunk_size = chunk_size or 65536
  self.runs_out = false
end

function HttpStream:_read(n)
  if self.runs_out then
    self:push()
    return
  end
  n = self.chunk_size
	if n < #self._str then
		local data = string.sub(tostring(self._str), 1, self.chunk_size)
    self:push(data)
    self._str = string.sub(tostring(self._str), self.chunk_size + 1)
    collectgarbage('collect')
		return
  else
    self:push(self._str)
    self._str = nil
    collectgarbage('collect')
    self.runs_out = true
  end
end

return HttpStream