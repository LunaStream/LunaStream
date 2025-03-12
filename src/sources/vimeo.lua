local http = require("coro-http")
local urlp = require("url-param")
local json = require("json")

local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")
local class = require('class')

local Vimeo = class('Vimeo', AbstractSource)

function Vimeo:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
  self._jwt = nil
  self._search_id = 'vmsearch'
end

function Vimeo:setup()
  self._luna.logger:debug('Vimeo', 'Setting up jwt for fetch tracks...')
  self:_getJwt()
  return self
end

function Vimeo:_getJwt()
  local url = "https://vimeo.com/_next/viewer"
  local success, res, body = pcall(http.request, "GET", url)

  if not success then
    self._luna.logger:error('Vimeo', 'Failed to fetch license token: ' .. res)
    return nil
  end

  if res.code ~= 200 then
    self._luna.logger:error('Vimeo', 'Failed to fetch license token')
    return nil
  end

  local data = json.decode(body)
  if not data or not data.jwt then
    self._luna.logger:error('Vimeo', 'Not found jwt')
    return nil
  end

  self._jwt = data.jwt
  return self._jwt
end

function Vimeo:search(query)
  local url = string.format("https://api.vimeo.com/search?query=%s&per_page=5&filter_type=clip", urlp.encode(query))
  local headers = { { "Authorization", "jwt " .. self._jwt }, { "Accept", "application/json" } }
  local success, response, data = pcall(http.request, "GET", url, headers)

  if not success then
    self._luna.logger:error('Vimeo', 'Failed to fetch search results: ' .. response)
    return nil, "Failed to fetch search results: " .. response
  end

  if response.code == 401 then
    self._luna.logger:debug('Vimeo', 'JWT token expired, fetching new authorization')
    self._jwt = self:_getJwt()
    return self:search(query) -- It seems that the JWT becomes invalid after a certain time that I did not identify, so I put it to get the new JWT in case it is not authorized.
  end

  if response.code ~= 200 then
    self._luna.logger:error('Vimeo', 'Failed to fetch search results')
    return nil, "Failed to fetch search results"
  end

  data = json.decode(data)

  if not data then
    self._luna.logger:error('Vimeo', 'Failed to decode search results')
    return nil, "Failed to decode search results"
  end

  local tracks = {}

  for _, video in ipairs(data.data) do
    local highestQualityPicture = nil
    local maxWidth = 0

    if video.clip.pictures and video.clip.pictures.sizes then
      for _, size in ipairs(video.clip.pictures.sizes) do
        if size.width > maxWidth then
          maxWidth = size.width
          highestQualityPicture = size.link
        end
      end
    end
    local trackUrlPattern = "^https?://vimeo%.com/([0-9]+)%??.*$"
    local videoId = string.match(video.clip.link, trackUrlPattern)
    local trackInfo = {
      title = video.clip.name,
      identifier = videoId,
      author = video.clip.user.name,
      length = video.clip.duration * 1000,
      uri = video.clip.link,
      isStream = false,
      isSeekable = true,
      sourceName = "vimeo",
      artworkUrl = highestQualityPicture or video.user.pictures.base_link,
      isrc = nil,
    }
    table.insert(tracks, { encoded = encoder(trackInfo), info = trackInfo })
  end

  return { loadType = "search", data = tracks }
end

function Vimeo:isLinkMatch(query)
  local trackUrlPattern = "^https?://vimeo%.com/([0-9]+)%??.*$"
  return string.match(query, trackUrlPattern) ~= nil
end

function Vimeo:loadForm(query)
  local trackUrlPattern = "^https?://vimeo%.com/([0-9]+)%??.*$"
  local videoId = string.match(query, trackUrlPattern)
  local url = string.format("https://vimeo.com/api/v2/video/%s.json", videoId)
  local success, response, data = pcall(http.request, "GET", url)

  if not success then
    self._luna.logger:error('Vimeo', 'Failed to fetch video data: %s', response)
    return {
      loadType = "error",
      data = {
        message = "Failed to fetch video data: " .. response,
        severity = "common",
        cause = "Vimeo Source",
      },
    }
  end

  if response.code ~= 200 then
    self._luna.logger:error('Vimeo', 'Failed to fetch video data')
    return {
      loadType = "error",
      data = {
        message = "Failed to fetch video data",
        severity = "common",
        cause = "Vimeo Source",
      },
    }
  end

  data = json.decode(data)

  if not data then
    return { loadType = "empty", tracks = {} }
  end

  local trackInfo = {
    title = data[1].title,
    identifier = data[1].id,
    author = data[1].user_name,
    length = data[1].duration * 1000,
    uri = data[1].url,
    isStream = false,
    isSeekable = true,
    sourceName = "vimeo",
    artworkUrl = data[1].thumbnail_large,
    isrc = nil,
  }

  return {
    loadType = "track",
    data = { encoded = encoder(trackInfo), info = trackInfo },
  }
end

function Vimeo:loadStream(track)
  if not self._jwt then
    return nil, "License token not available"
  end

  local apiUrl = string.format("https://api.vimeo.com/videos/%s", track.info.identifier)
  local headers = { { "Authorization", "jwt " .. self._jwt }, { "Accept", "application/json" } }
  local success, responseGetConfig, dataConfig = pcall(http.request, "GET", apiUrl, headers)

  if not success then
    return nil, "Failed to fetch video data: " .. responseGetConfig
  end

  if responseGetConfig.code == 401 then
    self._luna.logger:debug('Vimeo', 'JWT token expired, fetching new authorization')
    self._jwt = self:_getJwt()
    return self:loadStream(track)
  end

  if responseGetConfig.code ~= 200 then
    return nil, "Failed to fetch video data"
  end

  dataConfig = json.decode(dataConfig)

  if not dataConfig then
    return nil, "Failed to decode video data"
  end

  local apiUrl = dataConfig.config_url
  local success, response, data = pcall(http.request, "GET", apiUrl, headers)

  if not success then
    self._luna.logger:error('Vimeo', 'Failed to fetch video data: %s', response)
    return nil, "Failed to fetch video data: " .. response
  end

  if response.code == 401 then
    self._luna.logger:debug('Vimeo', 'JWT token expired, fetching new authorization')
    self._jwt = self:_getJwt()
    return self:loadStream(track)
  end

  if response.code ~= 200 then
    self._luna.logger:error('Vimeo', 'Failed to fetch video data')
    return nil, "Failed to fetch video data"
  end

  data = json.decode(data)

  if not data then
    self._luna.logger:error('Vimeo', 'Failed to decode video data')
    return nil, "Failed to decode video data"
  end

  local playbackUrl = data.request and data.request.files and data.request.files.hls and data.request.files.hls.cdns and
                        data.request.files.hls.cdns[data.request.files.hls.default_cdn].url

  if not playbackUrl then
    self._luna.logger:error('Vimeo', 'Failed to fetch playback url')
    return data
  end

  return { url = playbackUrl, format = "mp4", protocol = "hls", keepAlive = true, type = "segment" }
end

return Vimeo
