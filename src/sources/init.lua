local soundcloud = require("../sources/soundcloud.lua")
local config = require("../utils/config")

local class = require('class')

local Sources = class('Sources')

function Sources:__init()
  print('[SourceManager]: Setting up all avaliable source...')
  self._avaliables = {}
  if config.luna.soundcloud then
    self._avaliables["scsearch"] = soundcloud():setup()
  end
end

function Sources:search(query, source)
  print("[SourceManager]: Searching for: " .. query .. " in " .. source)
  local getSrc = self._avaliables[source]
  if not getSrc then
    return {
			loadType = "error",
			tracks = {},
			message = "Source invalid or not avaliable"
		}
  end
  return getSrc:search(query)
end

function Sources:loadForm(link)
  print('[SourceManager]: Loading form for link: ' .. link)
  for _, src in pairs(self._avaliables) do
    local isLinkMatch = src:isLinkMatch(link)
    if isLinkMatch then return src:loadForm(link) end
  end

  return {
    loadType = "error",
    tracks = {},
    message = "Link invalid or not avaliable"
  }
end

return Sources
