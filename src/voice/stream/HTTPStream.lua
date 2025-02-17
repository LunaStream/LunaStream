local http = require('coro-http')
local uv = require('uv')
local Readable = require('stream').Readable

local function sleep(delay)
	local thread = coroutine.running()
	local t = uv.new_timer()
	t:start(delay, 0, function()
		t:stop()
		t:close()
		return assert(coroutine.resume(thread))
	end)
	return coroutine.yield()
end

local HTTPStream = Readable:extend()

function HTTPStream:initialize(method, url, headers, body, customOptions)
  Readable.initialize(self)
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

  self.http_read = read
  self.http_write = write
  self.res = res
  return { reponse = self.res, parent = self }
end

function HTTPStream:_read(n)
  if self.started_pushing then return end

  if self.eos then
    self:push()
    self:restore()
    return
  end

  coroutine.wrap(function ()
    self.started_pushing = true

    for item in self.http_read do
      if not item then
        self.res.keepAlive = false
        break
      end
      if #item == 0 then break end
      self:push(item)
      item = nil
      collectgarbage('collect')
      sleep(1)
    end

    self:push(self.push_cache)
    self.push_cache = nil

    self.eos = true

    if self.res.keepAlive then
      http.saveConnection(self.connection)
    else
      self.http_write()
    end

    collectgarbage('collect')
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