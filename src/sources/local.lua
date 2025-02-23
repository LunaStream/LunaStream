local AbstractSource = require('./abstract')
local encoder = require("../track/encoder.lua")
local class = require('class')

local LocalFile = class('LocalFile', AbstractSource)

function LocalFile:__init(luna)
  self._luna = luna
  AbstractSource.__init(self)
end

function LocalFile:setup()
  return self
end

function LocalFile:search(query)
  return self:loadForm(query)
end

function LocalFile:isLinkMatch(query)
  local f = io.open(query, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function LocalFile:loadForm(query)
  self._luna.logger:debug('LocalFile', 'Loading file: %s', query)

  local f = io.open(query, "rb")
  if not f then
    self._luna.logger:error('LocalFile', "File not found: %s", query)
    return self:buildError("File not found")
  end
  f:close()

  local track = {
    identifier = query,
    isSeekable = true,
    author = 'unknown',
    length = -1,
    isStream = false,
    position = 0,
    title = "Unknown",
    uri = query,
    artworkUrl = nil,
    isrc = nil,
    sourceName = 'local',
  }

  self._luna.logger:debug('LocalFile', 'File loaded: %s', query)

  return {
    loadType = 'track',
    data = { encoded = encoder(track), info = track, pluginInfo = {} },
  }
end

function LocalFile:loadStream(track, additionalData)
  return {
    url = track.info.uri,
    protocol = 'file',
    format = track.info.uri:match("%.([^.]+)$") or 'unknown',
    keepAlive = false
  }
end

return LocalFile
