local http = require('coro-http')
local Readable = require('stream').Readable

local HTTPStream = Readable:extend()

function HTTPStream:initialize(method, url, headers, body, customOptions)
  Readable.initialize(self, { objectMode = true })
  self.method = method
  self.uri = http.parseUrl(url)
  self.headers = headers or {}
  self.body = body
  self.customOptions = customOptions
  self.res = nil
  self.connection = nil
  self.content_length = 'not_avaliable'
  self.reconnecting = false
  self.ended = false
  self.read_coro_running = false
end

function HTTPStream:setup(custom_uri, redirect_count)
  redirect_count = redirect_count or 0
  local max_redirects = 5

  local options = {}
  if type(self.customOptions) == "number" then
    options.timeout = self.customOptions
  else
    options = self.customOptions or {}
  end
  options.followRedirects = options.followRedirects == nil and true or options.followRedirects

  local uri = custom_uri and http.parseUrl(custom_uri) or self.uri
  local connection = http.getConnection(uri.hostname, uri.port, uri.tls, options.timeout)
  local read = connection.read
  local write = connection.write
  self.connection = connection

  local req = { method = self.method, path = uri.path }
  local contentLength
  local chunked
  local hasHost = false

  if self.headers then
    for i = 1, #self.headers do
      local key, value = unpack(self.headers[i])
      key = key:lower()
      if key == "content-length" then
        contentLength = value
      elseif key == "content-encoding" and value:lower() == "chunked" then
        chunked = true
      elseif key == "host" then
        hasHost = true
      end
      req[#req + 1] = self.headers[i]
    end
  end
  if not hasHost then
    req[#req + 1] = { "Host", uri.host }
  end

  if type(self.body) == "string" then
    if not chunked and not contentLength then
      req[#req + 1] = { "Content-Length", #self.body }
    end
  end

  write(req)
  if self.body then
    write(self.body)
  end

  local res = read()
  if not res then
    if not connection.socket:is_closing() then
      connection.socket:close()
    end
    if connection.reused then
      return self:setup(nil, redirect_count)
    end
    error("Connection closed")
  end

  if options.followRedirects and
    (res.code == 301 or res.code == 302 or res.code == 303 or res.code == 307 or res.code == 308) then
    if redirect_count >= max_redirects then
      error("Too many redirects")
    end
    local new_location
    for _, header in ipairs(res) do
      if header[1]:lower() == "location" then
        new_location = header[2]
        break
      end
    end
    if new_location then
      return self:setup(new_location, redirect_count + 1)
    end
  end

  if req.method == "HEAD" then
    connection.reset()
  end

  -- Shouldn't save the connection because may cause some trouble with sable stream
  -- If we need this in the future, this function may help: http.saveConnection(connection)
  if res.keepAlive then
    http.saveConnection(connection)
  else
    write()
  end
  self.res = res
  self:emit('response', self)
  local content_length = self:getHeader('content-length')
  if content_length then
    self.content_length = tonumber(content_length)
  end
  return self
end

function HTTPStream:getHeader(inp_key)
  if not self.res or not inp_key then
    return
  end

  for _, value in pairs(self.res) do
    if type(value) == "table" and string.lower(value[1]) == inp_key then
      return value[2]
    end
  end

  return nil
end

function HTTPStream:read(n)
  -- Add _read to request data will fix the buffer lost about 80%
  self:_read()
  local data = Readable.read(self, n)
  -- ECONNREFUSED event is experimental and not handle very well, we know that
  if #self._readableState.buffer == 0 and self.read_coro_running == true and data == nil and not self.ended then
    self:emit('ECONNREFUSED')
  end
  return data
end

function HTTPStream:_read(n)
  if self.ended == true then
    return
  end
  coroutine.wrap(
    function()
      self.read_coro_running = true
      local chunk = self.connection.read()
      self.read_coro_running = false
      if type(chunk) == "string" and #chunk == 0 then
        self.ended = true
        if not self.connection.socket:is_closing() then
          self.connection.socket:close()
        end
        return self:push({})
      elseif type(chunk) == "string" then
        return self:push(chunk)
      end
    end
  )()
end

function HTTPStream:restore()
  self.res = nil
  self.connection = nil
  self._elapsed = 0
  collectgarbage('collect')
end

return HTTPStream
