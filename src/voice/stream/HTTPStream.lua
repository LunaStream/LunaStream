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
  self.http_read = nil
  self.http_write = nil
  self.connection = nil
  self.started_pushing = false
  self.eos = false
end

local function removeHeader(headers, headerName)
  headerName = headerName:lower()
  for i = #headers, 1, -1 do
    if headers[i][1]:lower() == headerName then
      table.remove(headers, i)
    end
  end
end

local DEFAULT_MAX_REDIRECTS = 10

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

  local req = {
    method = self.method,
    path = uri.path,
  }
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
    req[#req + 1] = {"Host", uri.host}
  end

  if type(self.body) == "string" then
    if not chunked and not contentLength then
      req[#req + 1] = {"Content-Length", #self.body}
    end
  end

  write(req)
  if self.body then write(self.body) end

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

  if options.followRedirects and (res.code == 301 or res.code == 302 or res.code == 303 or res.code == 307 or res.code == 308) then
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

  if res.keepAlive then
    http.saveConnection(connection)
  else
    write()
  end

  self.http_read = read
  self.http_write = write
  self.res = res
  return { response = self.res, parent = self }
end

function HTTPStream:_read(n)
  coroutine.wrap(function ()
    for chunk in self.http_read do
      p('chunks arrives: ', type(chunk) == "string" and #chunk or " not available")
      if type(chunk) == "string" and #chunk == 0 then
        return self:push({})
      elseif type(chunk) == "string" then
        return self:push(chunk)
      end
    end
  end)()
end

function HTTPStream:restore()
  self.method = ''
  self.uri = ''
  self.headers = {}
  self.body = ''
  self.customOptions = {}
  self.res = nil
  self.http_read = nil
  self.http_write = nil
  self.connection = nil
  self.started_pushing = false
  self.push_cache = ''
  self._elapsed = 0
  self.eos = false
  self.start = nil
end

return HTTPStream