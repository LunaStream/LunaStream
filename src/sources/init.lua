local http = require("coro-http")
local Readable = require("stream").Readable
local quickmedia = require("quickmedia")
local config = require("../utils/config")
local decoder = require("../track/decoder")

-- Sources
local youtube = require("../sources/youtube")
local avaliable_sources = {
  bandcamp = require("../sources/bandcamp.lua"),
 -- deezer = require("../sources/deezer.lua"),
  http = require("../sources/http.lua"),
  local_file = require("../sources/local_file.lua"),
  nicovideo = require("../sources/nicovideo.lua"),
  instagram = require("../sources/instagram.lua"),
  facebook = require("../sources/facebook.lua"),
  twitch = require("../sources/twitch.lua"),
  kwai = require("../sources/kwai.lua"),
  spotify = require("../sources/spotify.lua"),
  vimeo = require("../sources/vimeo.lua"),
  soundcloud = require("../sources/soundcloud.lua"),
}

local class = require("class")

local Sources = class("Sources")

function Sources:__init(luna)
  self._luna = luna
  self._luna.logger:info("SourceManager", "Setting up all avaliable source...")
  self._search_avaliables = {}
  self._source_avaliables = {}
  self._ffmpeg_config = {
    path = self:getBinaryPath('ffmpeg'),
    args = {
      '-loglevel', 'error',
      '-analyzeduration', '0',
      '-i', 'pipe:0',
      '-f', 's16le',
      '-ar', '48000',
      '-ac', '2',
      '-strict', '-2',
      'pipe:1'
    }
  }

  local is_yt = false
  local is_ytm = false

  -- Load all sources from config.luna.sources
  for _, source_name in pairs(config.luna.sources) do
    if source_name == "youtube" then
      is_yt = true
      goto continue
    end

    if source_name == "youtube_music" then
      is_ytm = true
      goto continue
    end

    if not avaliable_sources[source_name] then
      self._luna.logger:debug("SourceManager", "Audio source named %s not found!", source_name)
      goto continue
    end

    local source_class = avaliable_sources[source_name](luna):setup()

    if not source_class then
      self._luna.logger:error("SourceManager", "Failed on register [%s] audio source manager", source_name)
      goto continue
    end

    self._source_avaliables[source_name] = source_class

    if source_class._search_id then
      self._search_avaliables[source_class._search_id] = source_name
    end

    self._luna.logger:info("SourceManager", "Registered [%s] audio source manager", source_class.__name)
    ::continue::
  end

  if is_yt then
    self._source_avaliables["youtube"] = youtube(luna):setup()
    self._search_avaliables["ytsearch"] = "youtube"
    self._luna.logger:info("SourceManager", "Registered [YouTube] audio source manager")
  end

  if is_ytm then
    self._source_avaliables["youtube_music"] = self._source_avaliables["youtube"] or youtube(luna):setup()
    self._search_avaliables["ytmsearch"] = "youtube_music"
    self._luna.logger:info("SourceManager", "Registered [YouTube Music] audio source manager")
  end
end

function Sources:loadTracks(query, source)
  self._luna.logger:info("SourceManager", "Searching for: " .. query .. " in " .. source)
  local getSourceName = self._search_avaliables[source]
  local getSrc = self._source_avaliables[getSourceName]
  if not getSrc then
    self._luna.logger:error("SourceManager", "Source invalid or not avaliable!")
    return {
      loadType = "error",
      data = {
        message = source .. " not avaliable",
        severity = "common",
        cause = "SourceManager",
      },
    }
  end
  return getSrc:search(query, source)
end

function Sources:loadForm(link)
  self._luna.logger:info("SourceManager", "Loading form for link: " .. link)
  for _, src in pairs(self._source_avaliables) do
    local isLinkMatch, additionalData = src:isLinkMatch(link)
    if isLinkMatch then
      return src:loadForm(link, additionalData)
    end
  end

  self._luna.logger:error("SourceManager", "Link invalid or not avaliable!")
  return {
    loadType = "error",
    data = {
      message = "Link invalid or source not avaliable",
      severity = "common",
      cause = "SourceManager",
    },
  }
end

function Sources:loadStream(encodedTrack)
  local track = decoder(encodedTrack)
  local getSrc = self._source_avaliables[track.info.sourceName]
  if not getSrc then
    self._luna.logger:error("SourceManager", "Source invalid or not avaliable!")
    return {
      loadType = "error",
      data = {
        message = track.info.sourceName .. " source not avaliable",
        severity = "common",
        cause = "SourceManager",
      },
    }
  end
  return getSrc:loadStream(track, self._luna)
end

function Sources:getStream(track)
  local streamInfo = self:loadStream(track.encoded)

  if not streamInfo or not streamInfo.url then
    return nil
  end

  if streamInfo.protocol == "file" then
    local fstream = quickmedia.stream.file:new(streamInfo.url):pipe(quickmedia.core.FFmpeg:new(self._ffmpeg_config))
    return fstream, streamInfo.format
  end
  p(streamInfo.url, streamInfo.type, streamInfo.format)

  if streamInfo.protocol == "hls" then
    return self:loadHLS(streamInfo.url, streamInfo.type), streamInfo.type
  end

  local headers = streamInfo.auth and streamInfo.auth.headers or nil

  local streamClient = quickmedia.stream.http:new('GET', streamInfo.url, headers, nil, {
    keepAlive = streamInfo.keepAlive
  })

  local request = streamClient:setup()

  if request.res.code ~= 200 then
    return self._luna.logger:error("SourceManager", "Stream url response error: " .. request.res.code)
  end

  if track.info.sourceName == "deezer" then
    local source = self._source_avaliables["deezer"]

    request:pipe(source:decryptAudio():new(track.info.identifier)):pipe(quickmedia.core.FFmpeg:new(self._ffmpeg_config))
    return request, streamInfo.format
  end

  return request:pipe(quickmedia.core.FFmpeg:new(self._ffmpeg_config))
end

---------------------------------------------------------------
-- Function: getBinaryPath
-- Parameters:
--    name (string) - name of the binary/library.
--    production (boolean) - production mode flag.
-- Objective: Returns the binary path for the given library based on the OS and production mode.
---------------------------------------------------------------
function Sources:getBinaryPath(name)
  local os_name = require('los').type()
  local arch = os_name == 'darwin' and 'universal' or jit.arch
  local lib_name_list = { win32 = '.exe', linux = '.bin', darwin = '.macos' }
  return string.format('./bin/%s-%s-%s%s', name, os_name, arch, lib_name_list[os_name])
end


function Sources:loadHLS(url, type)
  local stream = Readable:new()

  coroutine.wrap(function()
    local uv = require('uv')
    local timer = require('timer')

    local function sleep(delay)
      local thread = coroutine.running()
      if not thread then return end
      local t = uv.new_timer()
      t:start(delay, 0, function()
          t:stop()
          t:close()
          if coroutine.status(thread) == "suspended" then
            coroutine.resume(thread)
          end
        end
      )
      return coroutine.yield()
    end

    self._luna.logger:debug("HLS", "Starting HLS stream for: %s", url)

    local res, body = http.request("GET", url)
    if not res or res.code ~= 200 then
      self._luna.logger:error("HLS", "Failed to fetch initial playlist: %s", url)
      return stream:push(nil)
    end

    local lines = {}
    for line in body:gmatch("([^\r\n]+)") do table.insert(lines, line) end

    local media_playlist_url = url

    if table.some(lines, function(l) return l:match("#EXT%-X%-MEDIA") and l:match("TYPE=AUDIO") end) then
        local audio_streams = {}
        for _, line in ipairs(lines) do
            if line:match("#EXT%-X%-MEDIA") and line:match("TYPE=AUDIO") then
                local uri = line:match('URI="([^"]+)"')
                if uri then
                    table.insert(audio_streams, {uri=uri, default=line:match("DEFAULT=YES")})
                end
            end
        end
        local picked_stream = table.find(audio_streams, function(s) return s.default end) or audio_streams[#audio_streams]
        if picked_stream then
            media_playlist_url = picked_stream.uri
            if not media_playlist_url:match("^https?://") then
                local baseUrl = url:match("(.*/)")
                media_playlist_url = baseUrl .. media_playlist_url
            end
            self._luna.logger:debug("HLS", "Found audio-only stream via #EXT-X-MEDIA: %s", media_playlist_url)
        end
    elseif table.some(lines, function(l) return l:match("#EXT%-X%-STREAM%-INF") end) then
        local streams = {}
        for i, line in ipairs(lines) do
            if line:match("#EXT%-X%-STREAM%-INF") then
                local bandwidth = line:match("BANDWIDTH=(%d+)")
                local stream_url = lines[i+1]
                if stream_url and not stream_url:match("^#") then
                    table.insert(streams, {bandwidth = tonumber(bandwidth) or 0, url = stream_url})
                end
            end
        end
        if #streams > 0 then
            table.sort(streams, function(a, b) return a.bandwidth < b.bandwidth end)
            media_playlist_url = streams[1].url
            if not media_playlist_url:match("^https?://") then
                local baseUrl = url:match("(.*/)")
                media_playlist_url = baseUrl .. media_playlist_url
            end
            self._luna.logger:debug("HLS", "No #EXT-X-MEDIA found. Falling back to lowest bandwidth stream: %s", media_playlist_url)
        end
    end

    local downloaded_segments = {}
    local saw_end = false

    while not saw_end do
        self._luna.logger:debug("HLS", "Fetching playlist: %s", media_playlist_url)
        local media_res, media_body = http.request("GET", media_playlist_url)
        if not media_res or media_res.code ~= 200 then
            self._luna.logger:error("HLS", "Failed to fetch media playlist: %s", media_playlist_url)
            return stream:push(nil)
        end

        local media_lines = {}
        for line in media_body:gmatch("([^\r\n]+)") do table.insert(media_lines, line) end

        local segments_to_process = {}
        local target_duration = 5
        saw_end = false

        for i, line in ipairs(media_lines) do
            if line:match("#EXT%-X%-TARGETDURATION:") then
                target_duration = tonumber(line:match("#EXT%-X%-TARGETDURATION:(%d+)")) or 10
            end
            if line:match("#EXTINF") then
                local duration = tonumber(line:match("#EXTINF:([%d%.]+),"))
                local uri = media_lines[i+1]
                if uri and not uri:match("^#") then
                    if not uri:match("^https?://") then
                        local baseUrl = media_playlist_url:match("(.*/)")
                        uri = baseUrl .. uri
                    end
                    table.insert(segments_to_process, {url=uri, duration=duration})
                end
            end
            if line:match("#EXT%-X%-ENDLIST") then
                saw_end = true
            end
        end

        if #segments_to_process == 0 and not saw_end then
            self._luna.logger:debug("HLS", "Live playlist is empty, waiting...")
            sleep(target_duration * 1000)
            goto continue
        end

        local new_segments_found = false
        for _, segment in ipairs(segments_to_process) do
            if not downloaded_segments[segment.url] then
                new_segments_found = true
                self._luna.logger:debug("HLS", "Downloading segment: %s", segment.url)
                local seg_res, seg_body = http.request("GET", segment.url)
                if seg_res and seg_res.code == 200 then
                    stream:push(seg_body)
                    downloaded_segments[segment.url] = true
                    self._luna.logger:debug("HLS", "Segment finished, waiting for %s seconds.", segment.duration)
                    sleep(segment.duration * 1000)
                else
                    self._luna.logger:error("HLS", "Failed to download segment %s, stopping.", segment.url)
                    return stream:push(nil)
                end
            end
        end

        if not new_segments_found and not saw_end then
            self._luna.logger:debug("HLS", "No new segments in playlist, waiting...")
            sleep(target_duration * 1000)
        end

        ::continue::
    end

    self._luna.logger:info("HLS", "End of playlist detected.")
    return stream:push(nil)

  end)()

  return stream:pipe(quickmedia.core.FFmpeg:new(self._ffmpeg_config))
end

return Sources