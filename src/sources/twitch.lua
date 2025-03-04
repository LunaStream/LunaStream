local http = require("coro-http")
local urlp = require("url-param")
local json = require("json")

local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")
local class = require('class')

local Twitch = class('Twitch', AbstractSource)

function Twitch:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._client_id = "kimne78kx3ncx6brgo4mv6wki5h1ko"
  self._device_id = nil
  self._access_tokens = {}
end

function Twitch:setup()
  local headers = {
    { "User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/111.0" },
    { "Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" },
    { "Accept-Language", "en-US,en;q=0.5" },
    { "Connection", "keep-alive" },
  }
  local success, response, data = pcall(http.request, "GET", "https://www.twitch.tv", headers)
  if not success then
    self._luna.logger:error('Twitch', 'Internal error: ' .. response)
    return nil
  end

  if response.code ~= 200 then
    self._luna.logger:error('Twitch', 'Failed to fetch Twitch page')
    return nil
  end
  self._client_id = data:match('clientId="(%w+)"')
  if not self._client_id then
    self._luna.logger:error('Twitch', 'Failed to extract client ID')
    return nil
  end
  for _, header in ipairs(response) do
    if header[1] == 'Set-Cookie' then
      local device_id = header[2]:match('unique_id=(%w+);')
      if device_id then
        self._device_id = device_id
        break
      end
    end
  end
  if not self._device_id then
    self._luna.logger:error('Twitch', 'Failed to extract device ID')
  end
  return self
end

function Twitch:isLinkMatch(query)
  return string.match(query, "^https?://(www%.|go%.|m%.)?twitch%.tv/([%w_]+/clip/[%w%-_]+|videos/%d+|%w+)") ~= nil
end

function Twitch:getChannelName(url)
  return url:match("twitch%.tv/([%w_]+)") and url:match("twitch%.tv/([%w_]+)"):lower()
end

function Twitch:getClipSlug(url)
  return url:match("/clip/([%w%-_]+)$")
end

function Twitch:getVodId(url)
  return url:match("/videos/(%d+)$")
end

function Twitch:getLinkType(query)
  if string.find(query, "/clip/") then
    return "clip", self:getClipSlug(query)
  elseif string.find(query, "/videos/") then
    return "vod", self:getVodId(query)
  end
  return "channel", self:getChannelName(query)
end

function Twitch:buildParam(params)
  local first_time = true
  local str = ''
  for key, value in pairs(params) do
    local new_key = urlp.encode(tostring(key))
    local new_value = urlp.encode(tostring(value))
    local processed = new_key .. '=' .. new_value
    if first_time then
      str = str .. processed
      first_time = false
    else
      str = str .. '&' .. processed
    end
  end
  return str
end

function Twitch:fetchAccessToken(channel)
  local queryStr = [[
        query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!, $platform: String!) {
          streamPlaybackAccessToken(
            channelName: $login,
            params: { platform: $platform, playerBackend: "mediaplayer", playerType: $playerType }
          ) @include(if: $isLive) {
            value
            signature
            authorization {
              isForbidden
              forbiddenReasonCode
            }
            __typename
          }
          videoPlaybackAccessToken(
            id: $vodID,
            params: { platform: $platform, playerBackend: "mediaplayer", playerType: $playerType }
          ) @include(if: $isVod) {
            value
            signature
            __typename
          }
        }
    ]]
  local payload_table = {
    operationName = "PlaybackAccessToken_Template",
    query = queryStr,
    variables = {
      isLive = true,
      login = channel,
      isVod = false,
      vodID = "",
      playerType = "site",
      platform = "web",
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    self._luna.logger:error('Twitch', 'internal error: ' .. response)
    return nil
  end

  if response.code ~= 200 then
    self._luna.logger:error('Twitch', 'Failed to fetch access token')
    return nil
  end
  local result = json.decode(data)
  return {
    value = result.data.streamPlaybackAccessToken.value,
    signature = result.data.streamPlaybackAccessToken.signature,
  }
end

function Twitch:fetchClipMetadata(slug)
  local queryStr = [[
        query ClipsView($slug: ID!) {
        clip(slug: $slug) {
           id
           slug
           title
        broadcaster {
           id
           displayName
           login
        }
        videoQualities {
           quality
           sourceURL
        }
        thumbnailURL
        durationSeconds
    }
}
]]
  local payload_table = {
    operationName = "ClipsView",
    query = queryStr,
    variables = { slug = slug },
    extensions = {
      persistedQuery = {
        version = 1,
        sha256Hash = "0d6d8d951d3b5305a3f2a0f2661b8a6a6d25dc042b155d8df8586905f0a0f435",
      },
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    return nil, "Internal error: " .. response
  end
  if response.code ~= 200 then
    return nil, "Failed to fetch clip metadata"
  end
  local result = json.decode(data)
  return result.data.clip
end

function Twitch:fetchVodMetadata(vod_id)
  local payload_table = {
    operationName = "VideoMetadata",
    variables = { videoID = vod_id, channelLogin = "" },
    extensions = {
      persistedQuery = {
        version = 1,
        sha256Hash = "226edb3e692509f727fd56821f5653c05740242c82b0388883e0c0e75dcbf687",
      },
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    return nil, "Internal error: " .. response
  end
  if response.code ~= 200 then
    return nil, "Failed to fetch VOD metadata"
  end
  local result = json.decode(data)
  return result.data.video
end

function Twitch:fetchVodAccessToken(vod_id)
  local queryStr = [[
        query PlaybackAccessToken_Template($isVod: Boolean!, $vodID: ID!, $playerType: String!, $platform: String!) {
          videoPlaybackAccessToken(
            id: $vodID,
            params: { platform: $platform, playerBackend: "mediaplayer", playerType: $playerType }
          ) @include(if: $isVod) {
            value
            signature
            __typename
          }
        }
    ]]
  local payload_table = {
    operationName = "PlaybackAccessToken_Template",
    query = queryStr,
    variables = {
      isVod = true,
      vodID = vod_id,
      playerType = "site",
      platform = "web",
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    return nil
  end
  if response.code ~= 200 then
    return nil
  end
  local result = json.decode(data)
  return {
    value = result.data.videoPlaybackAccessToken.value,
    signature = result.data.videoPlaybackAccessToken.signature,
  }
end

function Twitch:fetchClipAccessToken(slug)
  local queryStr = [[
        query ClipAccessToken($slug: ID!, $params: PlaybackAccessTokenParams!) {
            clip(slug: $slug) {
                playbackAccessToken(params: $params) {
                    value
                    signature
                }
            }
        }
    ]]
  local payload_table = {
    operationName = "ClipAccessToken",
    query = queryStr,
    variables = {
      slug = slug,
      params = {
        platform = "web",
        playerBackend = "mediaplayer",
        playerType = "embed",
      },
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    return nil, "Internal error: " .. response
  end
  if response.code ~= 200 then
    return nil, "Failed to fetch clip access token"
  end
  local result = json.decode(data)
  if result and result.data and result.data.clip and result.data.clip.playbackAccessToken then
    return {
      value = result.data.clip.playbackAccessToken.value,
      signature = result.data.clip.playbackAccessToken.signature,
    }
  else
    return nil, "Clip access token not found"
  end
end

function Twitch:loadFrom(query)
  local vod_id = self:getVodId(query)
  if vod_id then
    return self:loadVod(vod_id, query)
  end
  local clip_slug = self:getClipSlug(query)
  if clip_slug then
    return self:loadClip(clip_slug, query)
  end
  local channel = self:getChannelName(query)
  if not channel then
    return self:buildError("Invalid Twitch URL", "fault", "Twitch Source")
  end
  local payload_table = {
    operationName = "StreamMetadata",
    variables = { channelLogin = channel },
    extensions = {
      persistedQuery = {
        version = 1,
        sha256Hash = "1c719a40e481453e5c48d9bb585d971b8b372f8ebb105b17076722264dfa5b3e",
      },
    },
  }
  local payload = json.encode(payload_table)
  local headers = {
    { "Client-ID", self._client_id },
    { "X-Device-ID", self._device_id },
    { "Content-Type", "application/json" },
  }
  local success, response, data = pcall(http.request, "POST", "https://gql.twitch.tv/gql", headers, payload)
  if not success then
    return self:buildError("Internal error: " .. response, "fault", "Twitch Source")
  end
  if response.code ~= 200 then
    return self:buildError("Failed to fetch channel info", "fault", "Twitch Source")
  end
  local result = json.decode(data)
  local streamInfo = result.data.user.stream
  if not streamInfo or streamInfo.type ~= "live" then
    return { loadType = "empty", data = {} }
  end
  local thumbnail = string.format("https://static-cdn.jtvnw.net/previews-ttv/live_user_%s-440x248.jpg", channel)
  local trackInfo = {
    identifier = channel,
    uri = query,
    title = result.data.user.lastBroadcast.title or "Live Stream",
    author = channel,
    length = 0,
    isSeekable = false,
    isStream = true,
    artworkUrl = thumbnail,
    sourceName = "twitch",
  }
  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {},
  }
  return { loadType = "track", data = track }
end

function Twitch:loadClip(slug, original_url)
  local clip_data, error_msg = self:fetchClipMetadata(slug)
  if not clip_data then
    return self:buildError(error_msg or "Clip not found", "fault", "Twitch Source")
  end
  local thumbnail = clip_data.thumbnailURL
  local duration = math.floor(clip_data.durationSeconds * 1000)
  local author = clip_data.broadcaster.displayName
  local best_url = nil
  for quality, url in pairs(clip_data.videoQualities) do
    if not best_url or url.quality > best_url.quality then
      best_url = url
    end
  end
  if not best_url then
    return self:buildError("No playable sources found", "fault", "Twitch Source")
  end
  local trackInfo = {
    identifier = slug,
    uri = original_url,
    title = clip_data.title or "Twitch Clip",
    author = author,
    length = duration,
    isSeekable = true,
    isStream = false,
    artworkUrl = thumbnail,
    sourceName = "twitch",
  }
  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {},
  }
  return { loadType = "track", data = track }
end

function Twitch:loadVod(vod_id, original_url)
  local vod_data, error_msg = self:fetchVodMetadata(vod_id)
  if not vod_data then
    return self:buildError(error_msg or "VOD not found", "fault", "Twitch Source")
  end
  local thumbnail = vod_data.previewThumbnailURL
  thumbnail = thumbnail:gsub("{width}", "320"):gsub("{height}", "180")
  local duration = math.floor(vod_data.lengthSeconds * 1000)
  local author = vod_data.owner.displayName
  local trackInfo = {
    identifier = vod_id,
    uri = original_url,
    title = vod_data.title or "Twitch VOD",
    author = author,
    length = duration,
    isSeekable = true,
    isStream = false,
    artworkUrl = thumbnail,
    sourceName = "twitch",
  }
  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {},
  }
  return { loadType = "track", data = track }
end

function Twitch:loadStream(track)
  if track.info.uri:find("/videos/") then
    return self:loadVodStream(track)
  elseif track.info.uri:find("/clip/") then
    return self:loadClipStream(track)
  end
  local channel = self:getChannelName(track.info.uri)
  if not channel then
    return self:buildError("Invalid Twitch URL", "fault", "Twitch Source")
  end
  local token = self:fetchAccessToken(channel)
  if not token then
    return self:buildError("Failed to get access token", "fault", "Twitch Source")
  end
  local params = {
    player_type = "site",
    token = token.value,
    sig = token.signature,
    allow_source = "true",
    allow_audio_only = "true",
  }
  local query = self:buildParam(params)
  local hls_url = string.format("https://usher.ttvnw.net/api/channel/hls/%s.m3u8?%s", channel, query)
  local success, response, data = pcall(http.request, "GET", hls_url)

  if not success then
    return self:buildError("Internal error: " .. success, "fault", "Twitch Source")
  end

  if response.code ~= 200 then
    return self:buildError("Failed to fetch HLS playlist", "fault", "Twitch Source")
  end
  local best_quality = self:parseM3U8(data)
  if not best_quality then
    return self:buildError("No playable streams found", "fault", "Twitch Source")
  end
  return {
    url = best_quality.url,
    format = "ts",
    protocol = "hls",
    isStream = true,
    keepAlive = true
  }
end

function Twitch:loadClipStream(track)
  local slug = self:getClipSlug(track.info.uri)
  local clip_data = self:fetchClipMetadata(slug)
  if not clip_data then
    return self:buildError("Failed to load clip stream", "fault", "Twitch Source")
  end
  local best_quality = nil
  for _, quality in ipairs(clip_data.videoQualities) do
    if not best_quality or quality.quality > best_quality.quality then
      best_quality = quality
    end
  end
  local tokenData, err = self:fetchClipAccessToken(slug)
  if not tokenData then
    return self:buildError(err or "Failed to fetch clip access token", "fault", "Twitch Source")
  end
  local params = { token = tokenData.value, sig = tokenData.signature }
  local query = self:buildParam(params)
  local final_url = best_quality.sourceURL .. "?" .. query
  return { url = final_url, format = "mp4", protocol = "https", isStream = false }
end

function Twitch:loadVodStream(track)
  local vod_id = self:getVodId(track.info.uri)
  local vod_data = self:fetchVodMetadata(vod_id)
  if not vod_data then
    return self:buildError("Failed to load VOD stream", "fault", "Twitch Source")
  end
  local token = self:fetchVodAccessToken(vod_id)
  if not token then
    return self:buildError("Failed to get VOD access token", "fault", "Twitch Source")
  end
  local params = {
    player_type = "html5",
    token = token.value,
    sig = token.signature,
    allow_source = "true",
    allow_audio_only = "true",
  }
  local query = self:buildParam(params)
  local vod_url = string.format("https://usher.ttvnw.net/vod/%s.m3u8?%s", vod_id, query)
  return { url = vod_url, format = "mp4", protocol = "hls", isStream = false, type = "segment" }
end

function Twitch:parseM3U8(data)
  local lines = {}
  for line in data:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  local best_bandwidth = 0
  local best_url = nil
  for i = 1, #lines do
    if lines[i]:find("#EXT%-X%-STREAM%-INF:") then
      local bandwidth = tonumber(lines[i]:match("BANDWIDTH=(%d+)"))
      if bandwidth and bandwidth > best_bandwidth then
        best_bandwidth = bandwidth
        best_url = lines[i + 1]
      end
    end
  end
  if best_url then
    return { url = best_url }
  end
  best_bandwidth = 0
  best_url = nil
  for _, line in ipairs(lines) do
    if line:find("#EXT%-X%-MEDIA:") and line:find('TYPE=AUDIO') then
      local bandwidth = tonumber(line:match("BANDWIDTH=(%d+)")) or 0
      local uri = line:match('URI="(.-)"')
      if uri and bandwidth >= best_bandwidth then
        best_bandwidth = bandwidth
        best_url = uri
      end
    end
  end
  return best_url and { url = best_url } or nil
end

function Twitch:search(query)
  return {
    loadType = "error",
    data = {},
    message = "Search is not supported for Twitch",
  }
end

return Twitch
