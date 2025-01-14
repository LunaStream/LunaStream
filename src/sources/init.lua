local soundcloud = require("../sources/soundcloud.lua")
local bandcamp = require("../sources/bandcamp.lua")
local config = require("../utils/config")
local decoder = require("../track/decoder")

local class = require('class')

local Sources = class('Sources')

function Sources:__init(luna)
  print('[SourceManager]: Setting up all avaliable source...')

  self._luna = luna
  self._search_avaliables = {}
  self._source_avaliables = {}

  if config.luna.soundcloud then
    self._source_avaliables["soundcloud"] = soundcloud():setup()
    self._search_avaliables["scsearch"] = "soundcloud"
  end

  if config.luna.bandcamp then
    self._source_avaliables["bandcamp"] = bandcamp(luna):setup()
    self._search_avaliables["bcsearch"] = "bandcamp"
  end
end

function Sources:loadTracks(query, source)
  print("[SourceManager]: Searching for: " .. query .. " in " .. source)
  local getSourceName = self._search_avaliables[source]
  local getSrc = self._source_avaliables[getSourceName]
  if not getSrc then
    print('[SourceManager] -> [Error]: Source invalid or not avaliable!')
    return {
      loadType = "error",
      tracks = {},
      data = {
        message = getSourceName .. " source not avaliable",
        severity = "common",
        cause = "SourceManager"
      }
    }
  end
  return getSrc:search(query)
end

function Sources:loadForm(link)
  print('[SourceManager]: Loading form for link: ' .. link)
  for _, src in pairs(self._source_avaliables) do
    local isLinkMatch = src:isLinkMatch(link)
    if isLinkMatch then return src:loadForm(link) end
  end

  print('[SourceManager] -> [Error]: Link invalid or not avaliable!')

  return {
    loadType = "error",
    tracks = {},
    data = {
      message = "Link invalid or source not avaliable",
      severity = "common",
      cause = "SourceManager"
    }
  }
end

function Sources:loadStream(encodedTrack)
  local track = decoder(encodedTrack)
  local getSrc = self._source_avaliables[track.info.sourceName]

  if not getSrc then
    print('[SourceManager] -> [Error]: Source invalid or not avaliable!')
    return {
      loadType = "error",
      tracks = {},
      data = {
        message = track.info.sourceName .. " source not avaliable",
        severity = "common",
        cause = "SourceManager"
      }
    }
  end

  return getSrc:loadStream(track, self._luna)
end

return Sources
