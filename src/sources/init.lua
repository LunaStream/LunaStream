local soundcloud = require("../sources/soundcloud.lua")
local config = require("../utils/config")
local avaliable = {}

local class = require('class')

local Sources = class('Sources')

function Sources:__init()
  self._avaliable = {}
  if config.luna.soundcloud then
    p('Hi')
    soundcloud():setup()
    avaliable["scsearch"] = soundcloud
  end
end

function Sources:search(query, source)
  local getSrc = self._avaliable[source]
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
  for _, src in pairs(avaliable) do
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