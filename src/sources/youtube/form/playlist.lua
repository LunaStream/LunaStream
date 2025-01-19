local http = require("coro-http")
local json = require("json")

local encoder = require("../../../track/encoder.lua")

local function split(str, delimiter)
  local result = {}
  for match in (str..delimiter):gmatch("(.-)"..delimiter) do
    table.insert(result, match)
  end
  return result
end

return function (source, query, src_type)
  local config = source._luna.config

  local identifier = query:match("[?&]v=(...........)")

  local response, playlist = http.request(
    "POST",
    string.format('https://%s/youtubei/v1/next', source:getBaseHostRequest(src_type)), {},
    json.encode({
      context = source._ytContext,
      playlistId = query:match("list=([%w-]+)"),
      contentCheckOk = true,
      racyCheckOk = true
    })
  )

  if response.code ~= 200 then
    source._luna.logger:error('Youtube', "Server response error: %s | On query: %s", response.code, query)
    return source:buildError(
      "Server response error: " .. response.code,
      "fault", "YouTube Source"
    )
  end

  playlist = json.decode(playlist)

  if playlist.error then
    source._luna.logger:error('Youtube', playlist.error.message)
    return source:buildError(
      playlist.error.message,
      "fault", "YouTube Source"
    )
  end

  if playlist.playabilityStatus.status ~= 'OK' then
    local errorMessage = playlist.playabilityStatus.reason or playlist.playabilityStatus.messages[1]
    source._luna.logger:error('Youtube', errorMessage)
    return source:buildError(
      playlist.error.message,
      "common", errorMessage
    )
  end

  local contentsRoot = nil
  if config.sources.youtube.bypassAgeRestriction then
    contentsRoot = playlist.contents.singleColumnWatchNextResults.playlist
  else
    contentsRoot = (src_type == 'ytmsearch')
      and playlist.contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs[1].tabRenderer.content.musicQueueRenderer
      or playlist.contents.singleColumnWatchNextResults
  end

  if not (
    (src_type == 'ytmsearch' and not config.search.sources.youtube.bypassAgeRestriction)
    and contentsRoot.content or contentsRoot
  ) then
    source._luna.logger:debug('Youtube', 'No matches found.')
    return {
      loadType = 'empty',
      data = {}
    }
  end

  local tracks = {}
  local selectedTrack = 0
  local playlistContent = nil

  if config.sources.youtube.bypassAgeRestriction then
    playlistContent = contentsRoot.playlist.contents
  else
    if src_type == 'ytmsearch' then
      playlistContent = contentsRoot.content.playlistPanelRenderer.contents
    else
      _, playlistContent = pcall(function () return contentsRoot.playlist.playlist.contents end)
    end
  end

  if not playlistContent then
    source._luna.logger:debug('Youtube', 'No matches found.')
    return {
      loadType = 'empty',
      data = {}
    }
  end

  if #playlistContent > config.sources.maxAlbumPlaylistLength then
    playlistContent = table.slice(playlistContent, 1, config.sources.maxAlbumPlaylistLength)
  end

  for i, video in pairs(playlistContent) do
    video = video.playlistPanelVideoRenderer or video.gridVideoRenderer

    if not video then goto continue end

    -- Calculate the length in milliseconds
    local videoLength = 0

    if video.lengthText then
      local timeParts = split(video.lengthText.runs[1].text, ":")
      local minutes = tonumber(timeParts[1]) or 0
      local seconds = tonumber(timeParts[2]) or 0
      videoLength = (minutes * 60 + seconds) * 1000
    end

    local track = {
      identifier = video.videoId,
      isSeekable = true,
      author = video.shortBylineText.runs and video.shortBylineText.runs[1].text or 'Unknown author',
      length = videoLength,
      isStream = false,
      position = 0,
      title = video.title.runs[1].text,
      uri =  string.format('https://%s/watch?v=%s', source:getBaseHost(src_type), video.videoId),
      artworkUrl = video.thumbnail.thumbnails[#video.thumbnail.thumbnails].url:match("([^?]+)"),
      isrc = nil,
      sourceName = 'youtube'
    }

    table.insert(tracks, {
      encoded = encoder(track),
      info = track,
      pluginInfo = {}
    })

    if identifier and track.identifier == identifier then
      selectedTrack = i
    end
    ::continue::
  end

  if #tracks == 0 then
    source._luna.logger:debug('Youtube', 'No matches found.')
    return {
      loadType = 'empty',
      data = {}
    }
  end

  local playlistName = nil

  if config.sources.youtube.bypassAgeRestriction then
    playlistName = contentsRoot.playlist.title
  else
    playlistName = (src_type == 'ytmsearch')
      and contentsRoot.header.musicQueueHeaderRenderer.subtitle.runs[1].text
      or contentsRoot.playlist.playlist.title
  end

  source._luna.logger:debug(
    'YouTube',
    'Loaded playlist %s from %s',
    playlistName,
    query
  )

  return {
    loadType = 'playlist',
    data = {
      info = {
        name = playlistName,
        selectedTrack = selectedTrack
      },
      pluginInfo = {},
      tracks = tracks
    }
  }
end
