local json = require("json")
local http = require("coro-http")
local encoder = require("../../../track/encoder.lua")

return function(query, src_type, youtube)
  local playlistId = query:match("list=([%w%-]+)")
  if not playlistId then
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Invalid playlist ID",
        severity = "common",
        domain = "YouTube Source",
      },
    }
  end

  local response, data = http.request(
    "POST", string.format("https://%s/youtubei/v1/next", youtube:baseHostRequest(src_type)), {
      { "User-Agent", youtube._clientManager.ytContext.client.userAgent },
      { "X-GOOG-API-FORMAT-VERSION", "2" },
      { "Content-Type", "application/json" },
    }, json.encode(
      {
        context = youtube._clientManager.ytContext,
        playlistId = playlistId,
        contentCheckOk = true,
        racyCheckOk = true,
      }
    )
  )

  if response.code ~= 200 then
    return {
      loadType = "error",
      data = {},
      error = {
        message = "Server response error: " .. response.code,
        severity = "fault",
        domain = "YouTube Source",
      },
    }
  end

  data = json.decode(data)

  if data.error then
    return {
      loadType = "error",
      data = {},
      error = {
        message = data.error.message or "Unknown error",
        severity = "common",
        domain = "YouTube Source",
      },
    }
  end
  local contentsRoot = data.contents.singleColumnWatchNextResults

  if not contentsRoot then
    return { loadType = "empty", data = {} }
  end

  local playlistName = data.contents.singleColumnWatchNextResults.playlist.playlist.title

  playlistName = playlistName or "Unknown Playlist"

  local playlistContent = contentsRoot.playlist.playlist.contents

  if not playlistContent then
    return { loadType = "empty", data = {} }
  end

  local tracks = {}

  for _, video in ipairs(playlistContent) do
    video = video.playlistPanelVideoRenderer or video.gridVideoRenderer
    if video then
      local lengthMs = 0
      local overlay = video.thumbnailOverlays and video.thumbnailOverlays[1] and
                        video.thumbnailOverlays[1].thumbnailOverlayTimeStatusRenderer
      local timeText = overlay and overlay.text and overlay.text.runs and overlay.text.runs[1].text

      if timeText then
        local minutes, seconds = timeText:match("(%d+):(%d+)")
        if minutes and seconds then
          lengthMs = (tonumber(minutes) * 60 + tonumber(seconds)) * 1000
        end
      end

      local track = {
        identifier = video.videoId,
        isSeekable = true,
        author = video.shortBylineText and video.shortBylineText.runs and video.shortBylineText.runs[1].text or
          "Unknown author",
        length = lengthMs,
        isStream = false,
        position = 0,
        title = video.title and video.title.simpleText or "Unknown title",
        uri = string.format("https://%s/watch?v=%s", youtube:baseHostRequest(src_type), video.videoId),
        artworkUrl = video.thumbnail and video.thumbnail.thumbnails and
          video.thumbnail.thumbnails[#video.thumbnail.thumbnails].url or nil,
        isrc = nil,
        sourceName = src_type == "ytmsearch" and 'youtube_music' or 'youtube',
      }

      tracks[#tracks + 1] = {
        encoded = encoder(track),
        info = track,
        pluginInfo = {},
      }
    end
  end

  return {
    loadType = "playlist",
    data = {
      info = { name = playlistName, selectedTrack = 0 },
      pluginInfo = {},
      tracks = tracks,
    },
  }
end
