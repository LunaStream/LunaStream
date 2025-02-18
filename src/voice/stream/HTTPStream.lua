local http = require('coro-http')
local Readable = require('stream').Readable

local HTTPStream = Readable:extend()

function HTTPStream:initialize(method, url, headers, body, customOptions)
  Readable.initialize(self, { objectMode = true })
  self.method = method
  self.uri = http.parseUrl(url)
  self.headers = headers
  self.body = body
  self.customOptions = customOptions
  self.res = nil
  self.http_read = nil
  self.http_write = nil
  self.connection = nil
  self.started_pushing = false
  self.eos = false
end

function HTTPStream:setup(custom_uri)
  local options = {}
  if type(self.customOptions) == "number" then
    -- Ensure backwards compatibility, where customOptions used to just be timeout
    options.timeout = self.customOptions
  else
    options = self.customOptions or {}
  end
  options.followRedirects = options.followRedirects == nil and true or options.followRedirects -- Follow any redirects, Default: true

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
      return self:setup()
    end
    error("Connection closed")
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
  return { reponse = self.res, parent = self }
end

function HTTPStream:_read(n)
  coroutine.wrap(function ()
    for chunk in self.http_read do
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