local http = require("coro-http")
local url = require("url")
local json = require("json")

local mod_table = require("../utils/mod_table.lua")
local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")

local class = require('class')

local BandCamp = class('BandCamp', AbstractSource)

function BandCamp:__init(luna)
  self._luna = luna
end

function BandCamp:setup()
  self._luna.logger:info('BandCamp', "Setup complete!")
  return self
end

function BandCamp:search(query)
	local query_link = "https://bandcamp.com/search?q=%s&item_type=t&from=results"
	local _, data = http.request("GET", string.format(query_link, url.encode(query)))


  local names = table.map(
    string.split(data, "<div class=\"heading\">%s+<a.->(.-)</a>"),
    function (str)
      return str:gsub("^%s+", ""):gsub("%s+$", "")
    end
  )

  if #names == 0 then return {
    loadType = "empty",
    tracks = {}
  } end

  local tracks = {}

  if #names > self._luna.config.sources.maxSearchResults then
    names = { table.unpack(names, 1, self._luna.sources.maxSearchResults) }
  end

  for _, name in pairs(names) do
    table.insert(tracks, {
      encoded = nil,
      info = {
        identifier = nil,
        isSeekable = true,
        author = nil,
        length = -1,
        isStream = false,
        position = 0,
        title = name,
        uri = nil,
        artworkUrl = nil,
        isrc = nil,
        sourceName = 'bandcamp'
      },
      pluginInfo = {}
    })
  end

  local authors = table.map(
    string.split(data, '<div class="subhead">%s+(?:from%s+)?[%s\\S]*?by (.-)%s+</div>'),
    function (str)
      return str:gsub("^%s+", ""):gsub("%s+$", "")
    end
  )

  for i, author in pairs(authors) do
    tracks[i].info.author = author
  end

  local artworkUrls = table.map(
    string.split(data, '<div class="art">%s*<img src="(.-)"'),
    function (str)
      return str:gsub("^%s+", ""):gsub("%s+$", "")
    end
  )

  for i, artworkUrl in pairs(artworkUrls) do
    tracks[i].info.artworkUrl = artworkUrl
  end

  for key, value in string.gmatch(data, 'https?://.+%.bandcamp%.com/track/(.+)</a>') do
    p(key, value)
  end

  -- local urls = string.split(data, '%s+$')

  -- for i, track_url in pairs(urls) do
  --   tracks[i].info.uri = track_url
  --   -- local identifier = tracks[i].info.uri.match(/^https?:\/\/([^/]+)\/track\/([^/?]+)/)
  --   -- tracks[i].info.identifier = `${identifier[1]}:${identifier[2]}`

  --   -- tracks[i].encoded = encodeTrack(tracks[i].info)
  --   -- tracks[i].pluginInfo = {}
  -- end

  -- p(urls)

  return {
    loadType = 'search',
    tracks = tracks
  }
end

function BandCamp:isLinkMatch(query)
  local check1 = query:match("https?://www%.bandcamp%.com")
	local check2 = query:match("https?://bandcamp%.com")
	if check1 or check2 then return true end
	return false
end

function BandCamp:loadForm(query, source)
  return {
    loadType = "empty",
    tracks = {}
  }
end

function BandCamp:buildTrack(data)
  return {
    loadType = "empty",
    tracks = {}
  }
end

function BandCamp:loadStream(track, additionalData)
  return {
    loadType = "empty",
    tracks = {}
  }
end

return BandCamp