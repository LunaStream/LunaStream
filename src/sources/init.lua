local http = require("coro-http")
local MusicUtils = require('musicutils')
local config = require("../utils/config")
local decoder = require("../track/decoder")
local HTTPStream = require("../voice/stream/HTTPStream")

-- Sources
local youtube = require("../sources/youtube")
local soundcloud = require("../sources/soundcloud.lua")
local bandcamp = require("../sources/bandcamp.lua")
local deezer = require("../sources/deezer.lua")
local vimeo = require("../sources/vimeo.lua")
local httpdirectplay = require("../sources/http.lua")
local nicovideo = require("../sources/nicovideo.lua")
local twitch = require("../sources/twitch.lua")
local spotify = require("../sources/spotify.lua")
local instagram = require("../sources/instagram.lua")
local facebook = require("../sources/facebook.lua")
local kwai = require("../sources/kwai.lua")

local class = require('class')

local Sources = class('Sources')

function Sources:__init(luna)
  self._luna = luna
  self._luna.logger:info('SourceManager', 'Setting up all avaliable source...')

  self._search_avaliables = {}
  self._source_avaliables = {}

  if config.luna.bandcamp then
    self._source_avaliables["bandcamp"] = bandcamp(luna):setup()
    self._search_avaliables["bcsearch"] = "bandcamp"
    self._luna.logger:info('SourceManager', 'Registered [BandCamp] audio source manager')
  end
  if config.luna.vimeo then
    self._source_avaliables["vimeo"] = vimeo(luna):setup()
    self._search_avaliables["vmsearch"] = "vimeo"
    self._luna.logger:info('SourceManager', 'Registered [Vimeo] audio source manager')
  end
  
  if config.luna.http then
    self._source_avaliables["http"] = httpdirectplay(luna):setup()
    self._luna.logger:info('SourceManager', 'Registered [HTTPDirectPlay] audio source manager')
  end

  if config.luna.nicovideo then
    self._source_avaliables["nicovideo"] = nicovideo(luna):setup()
    self._search_avaliables["ncsearch"] = "nicovideo"
    self._luna.logger:info('SourceManager', 'Registered [NicoVideo] audio source manager')
  end

  if config.luna.youtube then
    self._source_avaliables["youtube"] = youtube(luna):setup()
    self._search_avaliables["ytsearch"] = "youtube"
    self._luna.logger:info('SourceManager', 'Registered [YouTube] audio source manager')
  end

  if config.luna.youtube_music then
    self._source_avaliables["youtube_music"] = self._source_avaliables["youtube"] or youtube(luna):setup()
    self._search_avaliables["ytmsearch"] = "youtube_music"
    self._luna.logger:info('SourceManager', 'Registered [YouTube Music] audio source manager')

  if config.luna.twitch then
    self._source_avaliables["twitch"] = twitch(luna):setup()
    self._luna.logger:info('SourceManager', 'Registered [Twitch] audio source manager')
  end
  
  if config.luna.spotify then
    self._source_avaliables["spotify"] = spotify(luna):setup()
    self._search_avaliables["spsearch"] = "spotify"
    self._luna.logger:info('SourceManager', 'Registered [Spotify] audio source manager')
  end

  if config.luna.soundcloud then
    self._source_avaliables["soundcloud"] = soundcloud(luna):setup()
    self._search_avaliables["scsearch"] = "soundcloud"
    self._luna.logger:info('SourceManager', 'Registered [SoundCloud] audio source manager')
  end

  if config.luna.deezer then
    self._source_avaliables["deezer"] = deezer(luna):setup()
    self._search_avaliables["dzsearch"] = "deezer"
    self._luna.logger:info('SourceManager', 'Registered [Deezer] audio source manager')
  end

  if config.luna.instagram then
    self._source_avaliables["instagram"] = instagram(luna):setup()
    self._luna.logger:info('SourceManager', 'Registered [Instagram] audio source manager')
  end

  if config.luna.facebook then
    self._source_avaliables["facebook"] = facebook(luna):setup()
    self._luna.logger:info('SourceManager', 'Registered [Facebook] audio source manager')
  end

  if config.luna.kwai then
    self._source_avaliables["kwai"] = kwai(luna):setup()
    self._luna.logger:info('SourceManager', 'Registered [Kwai] audio source manager')
  end
end

function Sources:loadTracks(query, source)
  self._luna.logger:info('SourceManager', "Searching for: " .. query .. " in " .. source)
  local getSourceName = self._search_avaliables[source]
  local getSrc = self._source_avaliables[getSourceName]
  if not getSrc then
    self._luna.logger:error('SourceManager', 'Source invalid or not avaliable!')
    return {
      loadType = "error",
      data = {
        message = source .. " not avaliable",
        severity = "common",
        cause = "SourceManager"
      }
    }
  end
  return getSrc:search(query, source)
end

function Sources:loadForm(link)
  self._luna.logger:info('SourceManager', 'Loading form for link: ' .. link)
  for _, src in pairs(self._source_avaliables) do
    local isLinkMatch, additionalData = src:isLinkMatch(link)
    if isLinkMatch then return src:loadForm(link, additionalData) end
  end

  self._luna.logger:error('SourceManager', 'Link invalid or not avaliable!')

  return {
    loadType = "error",
    data = {
      message = "Link invalid or source not avaliable",
      severity = "common",
      cause = "SourceManager"
    }
  }
end

function Sources:loadStream(encodedTrack)
  local track = decoder(encodedTrack)

  local getSrc = self._source_avaliables[track.info.sourceName]
  if not getSrc then
    self._luna.logger:error('SourceManager', 'Source invalid or not avaliable!')
    return {
      loadType = "error",
      data = {
        message = track.info.sourceName .. " source not avaliable",
        severity = "common",
        cause = "SourceManager"
      }
    }
  end

  return getSrc:loadStream(track, self._luna)
end

function Sources:getStream(track)
  local streamInfo = self:loadStream(track.encoded)
  
  if not streamInfo.url then 
    return nil
  end

  local request, data = http.request("GET", streamInfo.url)

  if request.code ~= 200 then
    return nil
  end

  if data == nil then
    return nil
  end

  local stream = HTTPStream:new(data)
    :pipe(MusicUtils.opus.WebmDemuxer:new())

  return stream
end

return Sources