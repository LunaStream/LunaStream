local http = require("coro-http")
local urlp = require("url-param")
local url = require("url")
local json = require("json")

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
  self._luna.logger:debug('BandCamp', 'Searching: ' .. query)
	local query_link = "https://bandcamp.com/search?q=%s&item_type=t&from=results"
	local _, data = http.request("GET", string.format(query_link, urlp.encode(query)))

  local names = table.map(
    string.split(data, "<div class=\"heading\">%s+<a.->(.-)</a>"),
    function (str)
      return str:gsub("^%s+", ""):gsub("%s+$", "")
    end
  )

  if #names == 0 then return {
    loadType = "empty",
    data = {}
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

  local urls = string.split(data, '<div class="itemurl">%s*<a href="(.-)"')

  for i, track_url in pairs(urls) do
    local parsed = url.parse(track_url)
    local real_track_url = string.format('%s://%s%s', parsed.protocol, parsed.hostname, parsed.pathname)

    local author = real_track_url:match("https?://(.-)%.bandcamp%.com")
    local identifier = parsed.pathname:sub(8)

    tracks[i].info.uri = real_track_url
    tracks[i].info.identifier = author .. ':' .. identifier
    tracks[i].info.author = author

    tracks[i].encoded = encoder(tracks[i].info)
    tracks[i].pluginInfo = {}
  end

	self._luna.logger:debug('BandCamp', 'Found results for %s: ' .. #tracks, query)

  return {
    loadType = 'search',
    data = tracks
  }
end

function BandCamp:isLinkMatch(query)
	return query:match("https?://(.-)%.bandcamp%.com")
end

function BandCamp:loadForm(query)
  self._luna.logger:debug('BandCamp', 'Loading url: ' .. query)
  local _, data = http.request("GET", query)
  local matches = data:match('<script type="application/ld%+json">(.-)</script>'):gsub("^%s+", ""):gsub("%s+$", "")

  if not matches then
    self._luna.logger:debug('BandCamp', 'No matches found.')
    return {
      loadType = 'empty',
      data = {}
    }
  end

  local trackInfo = json.decode(matches)

  self._luna.logger:debug('BandCamp', 'Loaded raw! Type: %s, Query: %s',
    trackInfo['@type'] == 'MusicRecording' and 'track' or 'album',
    query
  )

  if trackInfo['@type'] == 'MusicRecording' then
    local parsed = url.parse(trackInfo['@id'])

    local author = trackInfo['@id']:match("https?://(.-)%.bandcamp%.com")
    local identifier = parsed.pathname:sub(8)

    local hours = tonumber(trackInfo.duration:match("P(%d+)H")) or 0
    local minutes = tonumber(trackInfo.duration:match("H(%d+)M")) or 0
    local seconds = tonumber(trackInfo.duration:match("M(%d+)S")) or 0

    -- Convert to milliseconds
    local totalMilliseconds = (hours * 3600000) + (minutes * 60000) + (seconds * 1000)

    local track = {
      identifier = author .. ':' .. identifier,
      isSeekable = true,
      author = trackInfo.byArtist.name,
      length = totalMilliseconds,
      isStream = false,
      position = 0,
      title = trackInfo.name,
      uri = trackInfo['@id'],
      artworkUrl = trackInfo.image,
      isrc = nil,
      sourceName = 'bandcamp'
    }

    self._luna.logger:debug(
			'BandCamp',
			'Loaded track %s by %s from %s',
			track.title,
			track.author,
			query
		)

    return {
      loadType = 'track',
      data = {
        encoded = encoder(track),
        info = track,
        pluginInfo = {}
      }
    }
  end

  if trackInfo['@type'] == 'MusicAlbum' then
    local tracks = {}

    for _, item in pairs(trackInfo.track.itemListElement) do
      local trackItem = item.item
      local parsed = url.parse(trackItem['@id'])

      local author = trackItem['@id']:match("https?://(.-)%.bandcamp%.com")
      local identifier = parsed.pathname:sub(8)

      local hours = tonumber(trackItem.duration:match("P(%d+)H")) or 0
      local minutes = tonumber(trackItem.duration:match("H(%d+)M")) or 0
      local seconds = tonumber(trackItem.duration:match("M(%d+)S")) or 0

      -- Convert to milliseconds
      local totalMilliseconds = (hours * 3600000) + (minutes * 60000) + (seconds * 1000)

      local track = {
        identifier = author .. ':' .. identifier,
        isSeekable = true,
        author = trackItem.byArtist.name,
        length = totalMilliseconds,
        isStream = false,
        position = 0,
        title = trackItem.name,
        uri = trackItem['@id'],
        artworkUrl = trackItem.image,
        isrc = nil,
        sourceName = 'bandcamp'
      }

      table.insert(tracks, {
        encoded = encoder(track),
        info = track,
        pluginInfo = {}
      })
    end

    self._luna.logger:debug(
			'SoundCloud',
			'Loaded playlist %s from %s',
			trackInfo.name,
			query
		)

    return {
      loadType = 'album',
      data = {
        info = {
          name = trackInfo.name,
          selectedTrack = 0
        },
        tracks = tracks
      }
    }
  end
end

function BandCamp:loadStream(track)
  local _, data = http.request("GET", track.info.uri)
  local streamURL = data:match('https?://t4%.bcbits%.com/stream/[a-zA-Z0-9]+/mp3%-128/%d+?p=%d+%&.-%&quot;')

  if not streamURL then
		self._luna.logger:error('BandCamp', "Failed to get stream")
		return self:buildError(
			"Failed to get stream",
			"fault", "BandCamp Source"
		)
  end

  self._luna.logger:debug('BandCamp', 'Loading stream url success')

  return {
    url = streamURL:sub(1, -7),
    protocol = 'https',
    format = 'mp3'
  }
end

return BandCamp