local http = require("coro-http")
local urlp = require("url-param")
local json = require("json")

local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")
local class = require('class')

local Deezer = class('Deezer', AbstractSource)

function Deezer:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._license_token = nil
  self._form_validation = nil
  self._cookie = nil
end

function Deezer:setup()
  local random_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  local api_token = ""
  for i = 1, 16 do
    local rand_index = math.random(1, #random_chars)
    api_token = api_token .. random_chars:sub(rand_index, rand_index)
  end
  local url = string.format(
    "https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token=%s", api_token
  )

  local response, data = http.request("GET", url)

  if response.code ~= 200 then
    self._luna.logger:error('Deezer', 'Failed initializing Deezer source')
    return nil
  end

  data = json.decode(data)

  if data.error == true then
    self._luna.logger:error('Deezer', 'Failed initializing Deezer source')
    return nil
  end

  self._license_token = data.results.USER.OPTIONS.license_token
  self._check_form = data.results.checkForm

  self._cookie = nil
  for _, header in ipairs(response) do
    if header[1] == 'Set-Cookie' then
      if self._cookie then
        self._cookie = self._cookie .. "; " .. header[2]
      else
        self._cookie = header[2]
      end
    end
  end

  if not self._cookie then self._luna.logger:error('Deezer', 'Cookie not found in response headers') end

  return self
end

function Deezer:search(query)
  self._luna.logger:debug('Deezer', 'Searching: ' .. query)
  local query_link = string.format("https://api.deezer.com/2.0/search?q=%s", urlp.encode(query))
  local response, data = http.request("GET", query_link)

  if response.code ~= 200 then
    local error_message = string.format("Server response error: %s | On query: %s", response.code, query)
    self._luna.logger:error('Deezer', error_message)
    return self:buildError(error_message, "fault", "Deezer Source")
  end

  data = json.decode(data)

  if data.error then
    local api_error_message = string.format("API error: %s | On query: %s", data.error.message, query)
    self._luna.logger:error('Deezer', api_error_message)
    return self:buildError(api_error_message, "fault", "Deezer Source")
  end

  if data.total == 0 then
    self._luna.logger:debug('Deezer', string.format("No results found for query: %s", query))
    return { loadType = "empty", data = {} }
  end

  local max_results = self._luna.config.sources.maxSearchResults
  if data.total > max_results then data.data = { table.unpack(data.data, 1, max_results) } end

  local tracks = {}

  for _, track in ipairs(data.data) do
    local trackinfo = {
      identifier = track.id,
      uri = track.link,
      title = track.title,
      author = track.artist.name,
      length = track.duration * 1000,
      isSeekable = true,
      isStream = false,
      isrc = track.isrc,
      artworkUrl = data.cover_xl or data.picture_xl,
      sourceName = "deezer",
    }

    table.insert(
      tracks, { encoded = encoder(trackinfo), info = trackinfo, pluginInfo = {} }
    )
  end

  return { loadType = "search", data = tracks }
end

function Deezer:getLinkType(query)
  local type, id = string.match(query, "/(%a+)/(%d+)$")
  return type, id
end

function Deezer:isLinkMatch(query)
  local valid = string.match(query, "^https?://www%.deezer%.com/") and
                  (string.match(query, "/album/%d+$") or string.match(query, "/track/%d+$") or
                    string.match(query, "/playlist/%d+$"))
  return valid ~= nil
end

function Deezer:loadForm(query)
  local type, id = self:getLinkType(query)
  if not type then
    self._luna.logger:error('Deezer', 'Type not supported')
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Type not supported",
        type = "fault",
        source = "Deezer Source",
      },
    }
  end

  local url = string.format("https://api.deezer.com/%s/%s", type, id)
  local response, data = http.request("GET", url)

  if response.code ~= 200 then
    self._luna.logger:error('Deezer', 'Failed loading form')
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Failed loading form",
        type = "fault",
        source = "Deezer Source",
      },
    }
  end

  data = json.decode(data)

  if data.error then
    self._luna.logger:error('Deezer', 'Failed loading form')
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Failed loading form",
        type = "fault",
        source = "Deezer Source",
      },
    }
  end

  local tracks = {}
  if type == "track" then
    local trackinfo = {
      identifier = data.id,
      uri = data.link,
      title = data.title,
      author = data.artist.name,
      length = data.duration * 1000,
      isSeekable = true,
      isStream = false,
      isrc = data.isrc,
      artworkUrl = data.album.cover_xl or data.album.picture_xl,
      sourceName = "deezer",
    }

    table.insert(
      tracks, { encoded = encoder(trackinfo), info = trackinfo, pluginInfo = {} }
    )

    return {
      loadType = "track",
      data = { info = { name = data.title, selectedTrack = 0 }, tracks = tracks },
    }
  end

  if type == "album" then
    for _, track in ipairs(data.tracks.data) do
      local trackinfo = {
        identifier = track.id,
        uri = track.link,
        title = track.title,
        author = track.artist.name,
        length = track.duration * 1000,
        isSeekable = true,
        isStream = false,
        isrc = track.isrc,
        artworkUrl = data.cover_xl or data.picture_xl,
        sourceName = "deezer",
      }

      table.insert(
        tracks, {
          encoded = encoder(trackinfo),
          info = trackinfo,
          pluginInfo = {},
        }
      )
    end

    return {
      loadType = "playlist",
      data = { info = { name = data.title, selectedTrack = 0 }, tracks = tracks },
    }
  end

  if type == "playlist" then
    for _, track in ipairs(data.tracks.data) do
      local trackinfo = {
        identifier = track.id,
        uri = track.link,
        title = track.title,
        author = track.artist.name,
        length = track.duration * 1000,
        isSeekable = true,
        isStream = false,
        isrc = track.isrc,
        artworkUrl = data.picture_xl,
        sourceName = "deezer",
      }

      table.insert(
        tracks, {
          encoded = encoder(trackinfo),
          info = trackinfo,
          pluginInfo = {},
        }
      )
    end

    return {
      loadType = "playlist",
      data = { info = { name = data.title, selectedTrack = 0 }, tracks = tracks },
    }
  end

  self._luna.logger:error('Deezer', 'Type not supported')
  return {
    loadType = "error",
    data = {},
    error = {
      message = "Type not supported",
      type = "fault",
      source = "Deezer Source",
    },
  }
end

function Deezer:loadStream(track)
  local song = { SNG_IDS = { track.info.identifier } }

  local url = string.format(
    "https://www.deezer.com/ajax/gw-light.php?method=song.getListData&input=3&api_version=1.0&api_token=%s",
      self._check_form
  )
  local response, data = http.request("POST", url, { { "Cookie", self._cookie } }, json.encode(song))

  if response.code ~= 200 then
    self._luna.logger:error('Deezer', 'Failed loading stream')
    return self:buildError("Failed loading stream", "fault", "Deezer Source")
  end

  data = json.decode(data)

  local formats = { 'MP3_64', 'MP3_128', 'MP3_256', 'MP3_320', 'FLAC' }

  local mediaData = { { type = "FULL", formats = {} } }

  for _, format in ipairs(formats) do
    if tonumber(data.results.data[1]['FILESIZE_' .. format]) > 0 then
      table.insert(
        mediaData[1].formats, { cipher = 'BF_CBC_STRIPE', format = format }
      )
    end
  end

  local _, body = http.request(
    "POST", "https://media.deezer.com/v1/get_url", {}, json.encode(
      {
        license_token = self._license_token,
        media = mediaData,
        track_tokens = { data.results.data[1].TRACK_TOKEN },
      }
    )
  )
  body = json.decode(body)

  if not body then
    return {
      license_token = self._license_token,
      media = mediaData,
      track_tokens = { data.results.data[1].TRACK_TOKEN },
    }
  end

  return {
    url = body.data[1].media[1].sources[1].url,
    format = (string.sub(body.data[1].media[1].format, 1, string.len("MP3")) == "MP3") and 'mp3' or 'flac',
    protocol = 'http',
    extra = data.results.data[1],
  }
end

return Deezer
