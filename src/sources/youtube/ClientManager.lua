local class = require('class')

local YouTubeClientManager, get = class('YouTubeClientManager')

function YouTubeClientManager:__init(luna)
  self._luna = luna
  self._avaliableClients = {
    ANDROID = {
      additionalContexts = {
        clientName = 'ANDROID',
        clientVersion = '19.47.41',
        userAgent = 'com.google.android.youtube/19.47.41 (Linux; U; Android 14 gzip)',
        deviceMake = 'Google',
        deviceModel = 'Pixel 6',
        osName = 'Android',
        osVersion = '14',
        hl = 'en',
        gl = 'US',
        utcOffsetMinutes = 0,
      },
    },
    IOS = {
      additionalContexts = {
        clientName = 'IOS',
        clientVersion = '19.47.7',
        userAgent = 'com.google.ios.youtube/19.47.7 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)',
        deviceMake = 'Apple',
        deviceModel = 'iPhone16,2',
        osName = 'iPhone',
        osVersion = '17.5.1.21F90',
        hl = 'en',
        gl = 'US',
        utcOffsetMinutes = 0,
      },
    },
  }
  self._ytContext = {}
  self._currentClient = ''
end

function get:ytContext()
  return self._ytContext
end

function get:additionalHeaders()
  local config = self._luna.config
  local additionalHeaders = {}

  if config.sources.youtube.authentication.ANDROID.enabled then
    additionalHeaders = {
      { 'Authorization', 'Bearer' .. config.sources.youtube.authentication.Android.authorization },
      { 'X-Goog-Visitor-Id', config.sources.youtube.authentication.Android.visitorId }
    }
  elseif (config.sources.youtube.authentication.WEB.enabled) then
    -- TODO: Port https://github.com/ytdl-org/youtube-dl/blob/master/youtube_dl/extractor/youtube.py#L105-L262 to Node.js
    additionalHeaders = {
      { 'Authorization', config.sources.youtube.authentication.web.authorization },
      { 'Cookie', config.sources.youtube.authentication.web.cookie },
      { 'X-Goog-Visitor-Id', config.sources.youtube.authentication.Android.visitorId },
      { 'X-Goog-AuthUser', '0' },
      { 'X-Youtube-Bootstrap-Logged-In', 'true' },
    }
  end
  return additionalHeaders
end

function YouTubeClientManager:setup()
  self:buildClientData()
  self:buildContext()
  self._luna.logger:debug('YouTubeClientManager', 'Set up contexts and multi client data complete')
  return self
end

function YouTubeClientManager:buildClientData()
  for _, clientName in pairs(self._luna.config.sources.youtube.clients) do
    local clientData = self._avaliableClients[clientName]
    if clientData then
      self._luna.logger:debug('YouTubeClientManager', 'Client [%s] registered!', clientName)
    else
      self._luna.logger:warn('YouTubeClientManager', 'Client [%s] not found in available clients!', clientName)
    end
  end
end

function YouTubeClientManager:buildContext()
  self:switchClient('ANDROID')
end

function YouTubeClientManager:switchClient(clientName)
  if not self._avaliableClients[clientName] then
    self._luna.logger:error('YouTubeClientManager', 'Client %s not found!', clientName)
    return false
  end

  if self._currentClient == clientName then return end

  self._luna.logger:debug('YouTubeClientManager', 'Switching to client: ' .. clientName)
  local clientData = self._avaliableClients[clientName].additionalContexts

  for key, value in pairs(clientData) do
    self._ytContext.client = self._ytContext.client or {}
    self._ytContext.client[key] = value
  end

  self._currentClient = clientName
end

return YouTubeClientManager