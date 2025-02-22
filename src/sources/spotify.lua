local http = require("coro-http")
local json = require("json")
local urlp = require("url-param")
local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")
local class = require("class")

local Spotify = class('Spotify', AbstractSource)

function Spotify:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._token = nil
  self._tokenExpiration = 0
end

function Spotify:setup()
  self._luna.logger:info("Spotify", "Setting up Spotify source")
  if not self:_requestToken() then
    self._luna.logger:error("Spotify", "Failed to get token from open.spotify.com")
  end
  return self
end

function Spotify:_requestToken()
  local headers = { { "User-Agent", "Mozilla/5.0" }, { "Accept", "application/json" } }
  local response, data = http.request("GET", "https://open.spotify.com/get_access_token", headers)

  if response.code ~= 200 then
    self._luna.logger:error("Spotify", "Failed to get token from open.spotify.com: " .. response.code)
    return false
  end
  local result = json.decode(data)
  if not result or not result.accessToken then
    self._luna.logger:error("Spotify", "Invalid token response from open.spotify.com")
    return false
  end
  self._token = "Bearer " .. result.accessToken
  self._tokenExpiration = tonumber(result.accessTokenExpirationTimestampMs) / 1000
  return true
end

function Spotify:_renewToken()
  if os.time() >= self._tokenExpiration then
    self:_requestToken()
  end
end

function Spotify:request(endpoint)
  self:_renewToken()
  local url = "https://api.spotify.com/v1" .. (endpoint:sub(1, 1) == "/" and endpoint or "/" .. endpoint)
  local headers = { { "Authorization", self._token } }
  local response, data = http.request("GET", url, headers)
  if response.code ~= 200 then
    return nil, "Request failed with code " .. response.code
  end
  return json.decode(data)
end

function Spotify:isLinkMatch(query)
  return (string.match(query, "open%.spotify%.com") or string.match(query, "spotify:%a+")) ~= nil
end

function Spotify:getLinkType(query)
  if self:getTrackID(query) then
    return "track", self:getTrackID(query)
  elseif self:getAlbumID(query) then
    return "album", self:getAlbumID(query)
  elseif self:getPlaylistID(query) then
    return "playlist", self:getPlaylistID(query)
  elseif self:getArtistID(query) then
    return "artist", self:getArtistID(query)
  end
  return nil, nil
end

function Spotify:getTrackID(url)
  local id = url:match("open%.spotify%.com/.*/track/([%w-]+)") or url:match("open%.spotify%.com/track/([%w-]+)") or
               url:match("spotify:track:([%w-]+)")
  return id
end

function Spotify:getAlbumID(url)
  local id = url:match("open%.spotify%.com/.*/album/([%w-]+)") or url:match("open%.spotify%.com/album/([%w-]+)") or
               url:match("spotify:album:([%w-]+)")
  return id
end

function Spotify:getPlaylistID(url)
  local id =
    url:match("open%.spotify%.com/.*/playlist/([%w-]+)") or url:match("open%.spotify%.com/playlist/([%w-]+)") or
      url:match("spotify:playlist:([%w-]+)")
  return id
end

function Spotify:getArtistID(url)
  local id = url:match("open%.spotify%.com/.*/artist/([%w-]+)") or url:match("open%.spotify%.com/artist/([%w-]+)") or
               url:match("spotify:artist:([%w-]+)")
  return id
end

function Spotify:fetchTrackMetadata(track_id)
  local result, err = self:request("/tracks/" .. track_id)
  if not result then
    return nil, "Failed to fetch track metadata"
  end
  return result
end

function Spotify:fetchAlbumMetadata(album_id)
  local result, err = self:request("/albums/" .. album_id)
  if not result then
    return nil, "Failed to fetch album metadata"
  end
  return result
end

function Spotify:fetchPlaylistMetadata(playlist_id)
  local result, err = self:request("/playlists/" .. playlist_id)
  if not result then
    return nil, "Failed to fetch playlist metadata"
  end
  return result
end

function Spotify:fetchArtist(id)
  local artist, err = self:request("/artists/" .. id)
  if not artist then
    return nil, "Failed to fetch artist metadata"
  end
  local topTracks, err2 = self:request("/artists/" .. id .. "/top-tracks?market=US")
  if not topTracks then
    return nil, "Failed to fetch artist top tracks"
  end
  local tracks = {}
  for _, track in ipairs(topTracks.tracks or {}) do
    table.insert(tracks, self:buildUnresolved(track))
  end
  return {
    loadType = "playlist",
    data = { info = { name = artist.name, selectedTrack = 0 }, tracks = tracks },
  }
end

function Spotify:buildUnresolved(track)
  if not track then
    error("Spotify track object not provided")
  end
  local artworkUrl = nil
  if track.album and track.album.images and #track.album.images > 0 then
    artworkUrl = track.album.images[#track.album.images].url
  end
  local artists = {}
  if track.artists then
    for _, artist in ipairs(track.artists) do
      table.insert(artists, artist.name)
    end
  end
  local trackInfo = {
    identifier = track.id,
    uri = "https://open.spotify.com/track/" .. track.id,
    title = track.name,
    author = table.concat(artists, ", "),
    length = track.duration_ms,
    isSeekable = true,
    isStream = false,
    artworkUrl = artworkUrl,
    sourceName = "spotify",
  }
  return { encoded = encoder(trackInfo), info = trackInfo, pluginInfo = {} }
end

function Spotify:loadForm(query)
  local typ, id = self:getLinkType(query)
  if not typ or not id then
    return self:buildError("Invalid Spotify URL", "fault", "Spotify Source")
  end
  if typ == "track" then
    return self:loadTrack(id, query)
  elseif typ == "album" then
    return self:loadAlbum(id, query)
  elseif typ == "playlist" then
    return self:loadPlaylist(id, query)
  elseif typ == "artist" then
    return self:fetchArtist(id)
  else
    return self:buildError("Unsupported Spotify type", "fault", "Spotify Source")
  end
end

function Spotify:loadTrack(track_id, original_url)
  local track_data, err = self:fetchTrackMetadata(track_id)
  if not track_data then
    return self:buildError(err or "Track not found", "fault", "Spotify Source")
  end
  local artworkUrl = nil
  if track_data.album and track_data.album.images and #track_data.album.images > 0 then
    artworkUrl = track_data.album.images[#track_data.album.images].url
  end
  local artists = {}
  for _, artist in ipairs(track_data.artists) do
    table.insert(artists, artist.name)
  end
  local trackInfo = {
    identifier = track_id,
    uri = original_url,
    title = track_data.name,
    author = table.concat(artists, ", "),
    length = track_data.duration_ms,
    isSeekable = true,
    isStream = false,
    artworkUrl = artworkUrl,
    sourceName = "spotify",
  }
  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {},
  }
  return { loadType = "track", data = track }
end

function Spotify:loadAlbum(album_id, original_url)
  local album_data, err = self:fetchAlbumMetadata(album_id)
  if not album_data then
    return self:buildError(err or "Album not found", "fault", "Spotify Source")
  end
  local tracks = {}
  for _, item in ipairs(album_data.tracks.items) do
    local artworkUrl = nil
    if album_data.images and #album_data.images > 0 then
      artworkUrl = album_data.images[#album_data.images].url
    end
    local artists = {}
    for _, artist in ipairs(item.artists) do
      table.insert(artists, artist.name)
    end
    local trackInfo = {
      identifier = item.id,
      uri = "https://open.spotify.com/track/" .. item.id,
      title = item.name,
      author = table.concat(artists, ", "),
      length = item.duration_ms,
      isSeekable = true,
      isStream = false,
      artworkUrl = artworkUrl,
      sourceName = "spotify",
    }
    local track = {
      encoded = encoder(trackInfo),
      info = trackInfo,
      pluginInfo = {},
    }
    table.insert(tracks, track)
  end
  return {
    loadType = "playlist",
    data = {
      info = { name = album_data.name, selectedTrack = 0 },
      tracks = tracks,
    },
  }
end

function Spotify:loadPlaylist(playlist_id, original_url)
  local playlist_data, err = self:fetchPlaylistMetadata(playlist_id)
  if not playlist_data then
    return self:buildError(err or "Playlist not found", "fault", "Spotify Source")
  end
  local tracks = {}
  for _, item in ipairs(playlist_data.tracks.items) do
    if item.track then
      local track = item.track
      local artworkUrl = nil
      if track.album and track.album.images and #track.album.images > 0 then
        artworkUrl = track.album.images[#track.album.images].url
      end
      local artists = {}
      for _, artist in ipairs(track.artists) do
        table.insert(artists, artist.name)
      end
      local trackInfo = {
        identifier = track.id,
        uri = "https://open.spotify.com/track/" .. track.id,
        title = track.name,
        author = table.concat(artists, ", "),
        length = track.duration_ms,
        isSeekable = true,
        isStream = false,
        artworkUrl = artworkUrl,
        sourceName = "spotify",
      }
      local encodedTrack = {
        encoded = encoder(trackInfo),
        info = trackInfo,
        pluginInfo = {},
      }
      table.insert(tracks, encodedTrack)
    end
  end
  return {
    loadType = "playlist",
    data = {
      info = { name = playlist_data.name, selectedTrack = 0 },
      tracks = tracks,
    },
  }
end

function Spotify:loadStream(track)
  return self:buildError("Direct streaming is not supported", "fault", "Spotify Source")
end

function Spotify:search(query)
  self:_renewToken()
  local encodedQuery = urlp.encode(query)
  local url = "https://api.spotify.com/v1/search?q=" .. encodedQuery .. "&type=track"
  local headers = { { "Authorization", self._token } }
  local response, data = http.request("GET", url, headers)
  if response.code ~= 200 then
    return { loadType = "error", data = {}, message = "Search request failed" }
  end
  local result = json.decode(data)
  local tracks = {}
  for _, item in ipairs(result.tracks.items) do
    local artworkUrl = nil
    if item.album and item.album.images and #item.album.images > 0 then
      artworkUrl = item.album.images[#item.album.images].url
    end
    local artists = {}
    for _, artist in ipairs(item.artists) do
      table.insert(artists, artist.name)
    end
    local trackInfo = {
      identifier = item.id,
      uri = "https://open.spotify.com/track/" .. item.id,
      title = item.name,
      author = table.concat(artists, ", "),
      length = item.duration_ms,
      isSeekable = true,
      isStream = false,
      artworkUrl = artworkUrl,
      sourceName = "spotify",
    }
    local track = {
      encoded = encoder(trackInfo),
      info = trackInfo,
      pluginInfo = {},
    }
    table.insert(tracks, track)
  end
  return { loadType = "search", data = tracks }
end

return Spotify
