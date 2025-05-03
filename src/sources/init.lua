local http = require("coro-http")
local stream = require("stream")
local PassThrough = stream.PassThrough
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
    path =  self:getBinaryPath('ffmpeg'),
    args = {
      '-loglevel', 'error',
      '-analyzeduration', '0',
      '-hwaccel', 'auto',
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
  local lib_name_list = { win32 = '.exe', linux = '', darwin = '' }
  return string.format('./bin/%s-%s-%s%s', name, os_name, arch, lib_name_list[os_name])
end

function Sources:loadHLS(url, type)
  local stream = PassThrough:new()

  if type == "segment" then
    coroutine.wrap(function()
      local success, res, body = pcall(http.request, "GET", url)
      if not success then
        self._luna.logger:error("loadHLS", "Internal error: " .. res)
        stream:close()
        return
      end
      if res.code ~= 200 then
        self._luna.logger:error("loadHLS", "HTTP error in segment: " .. res.code)
        stream:close()
        return
      end
      local chunkSize = 16 * 1024
      local bodyLength = #body
      for i = 1, bodyLength, chunkSize do
        local chunk = body:sub(i, math.min(i + chunkSize - 1, bodyLength))
        stream:write(chunk)
        coroutine.yield()
      end
      stream:close()
    end)()
    return stream

  elseif type == "playlist" then
    p(url, type)
    coroutine.wrap(function()
      local success, res, playlistBody = pcall(http.request, "GET", url)
      p(success, res, playlistBody)
      if not success then
        self._luna.logger:error("loadHLS", "Internal error: " .. res)
        stream:close()
        return
      end

      if res.code ~= 200 then
        self._luna.logger:error("loadHLS", "HTTP error in playlist: " .. res.code)
        stream:close()
        return
      end

      local segments = {}
      for line in playlistBody:gmatch("[^\r\n]+") do
        if not line:match("^#") and line:match("%S") then
          table.insert(segments, line)
        end
      end

      for _, segUrl in ipairs(segments) do
        if not segUrl:match("^https?://") then
          local baseUrl = url:match("(.*/)")
          segUrl = baseUrl .. segUrl
        end
      p(segUrl)
        local success, segRes, segBody = pcall(http.request, "GET", segUrl)
        if success and segRes.code == 200 then
          local chunkSize = 16 * 1024
          local segLength = #segBody
          for i = 1, segLength, chunkSize do
            local chunk = segBody:sub(i, math.min(i + chunkSize - 1, segLength))
            stream:write(chunk)
            coroutine.yield()
          end
        else
          if type(segRes) == "string" then return
            self._luna.logger:error("loadHLS", "Internal error: " .. segRes)
          end
          self._luna.logger:error("loadHLS", "HTTP error in segment: " .. segRes.code)
        end
      end

      stream:close()
    end)()
    return stream
  end

  return stream
end

return Sources
