local soundcloud = require("../sources/soundcloud.lua")
local config = require("../utils/config")
local avaliable = {}

local class = require('class')

local Sources = class('Sources')

function Sources:__init()
  if config.luna.soundcloud then
    avaliable["scsearch"] = soundcloud():setup()
  end
end

function Sources:search(query, source)
  print("Searching for: " .. query .. " in " .. source)
  local getSrc = avaliable[source]
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