local AbstractSource = require('./abstract')
local http = require("coro-http")
local url = require('url')
local encoder = require("../track/encoder.lua")

local class = require('class')

local HTTPDirectPlay = class('HTTPDirectPlay', AbstractSource)

function HTTPDirectPlay:__init(luna)
  self._luna = luna
  AbstractSource.__init()
  self._already_responded = nil
end

function HTTPDirectPlay:setup()
  return self
end

function HTTPDirectPlay:search(query)
end

-- This one is not optimized
function HTTPDirectPlay:isLinkMatch(query)
  return url.parse(query).path:match("%.%w+$") ~= nil
end

function HTTPDirectPlay:loadForm(query)
  self._luna.logger:debug('HTTPDirectPlay', 'Loading url: %s', query)
  local response, _ = http.request("GET", query)

  if response.code ~= 200 then
    p(response)
    self._luna.logger:error('HTTPDirectPlay', "Server response error: %s | On query: %s", response.code, query)
    return self:buildError("Server response error: " .. response.code, "fault", "SoundCloud Source")
  end

  local content_type = self:getHttpHeaders(response, 'content-type')

  if not content_type or not content_type[2]:match('audio/(.+)') then
    self._luna.logger:debug('HTTPDirectPlay', 'Url is not a playable stream.')
    return self:buildError('Url is not a playable stream.', 'common', 'Invalid URL')
  end

  local track = {
    identifier = 'unknown',
    isSeekable = false,
    author = 'unknown',
    length = -1,
    isStream = false,
    position = 0,
    title = 'unknown',
    uri = query,
    artworkUrl = nil,
    isrc = nil,
    sourceName = 'http',
  }

  self._luna.logger:debug('HTTPDirectPlay', 'Loaded url: %s', query)

  return {
    loadType = 'track',
    data = { encoded = encoder(track), info = track, pluginInfo = {} },
  }
end

function HTTPDirectPlay:getHttpHeaders(res, req)
  for _, header in pairs(res) do
    if type(header) == "table" and header[1]:lower() == req then
      return header
    end
  end
  return nil
end

function HTTPDirectPlay:loadStream(track, additionalData)
  local response, _ = http.request("GET", track.info.uri)

  if response.code ~= 200 then
    self._luna.logger:error('HTTPDirectPlay', "Server response error: %s | On query: %s", response.code, track.info.uri)
    return self:buildError("Server response error: " .. response.code, "fault", "SoundCloud Source")
  end

  local content_type = self:getHttpHeaders(response, 'content-type')

  return {
    url = track.info.uri,
    protocol = 'https',
    format = content_type[2]:match('audio/(.+)'),
    keepAlive = false
  }
end

return HTTPDirectPlay
