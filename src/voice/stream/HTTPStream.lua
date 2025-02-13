local Readable = require('stream').Readable

local HttpStream = Readable:extend()

local custom_string_meta = {
  __len = function(self)
    return #self.d
  end,
  __index = function(self, key)
    return self.d[key]
  end,
  __tostring = function(self)
    return self.d
  end
}

function HttpStream:initialize(str, chunk_size)
  Readable.initialize(self)
  self._str = setmetatable({ d = str }, custom_string_meta)
  self._len = #self._str
  self.offset = 0
  self.chunk_size = chunk_size or 65536
end

function HttpStream:_read(n)
  n = self.chunk_size or n
  local i = self._i or 1
	if i + n < self._len then
    self.offset = self.offset + n
		local data = string.sub(tostring(self._str), i, self.offset)
		self._i = i + n
    self:push(data)
		return
	end
  setmetatable(self._str, { __mode = "k" })
  self._len = 0
  self.offset = 0
  self:push()
  collectgarbage()
  self._str = nil
end

return HttpStream