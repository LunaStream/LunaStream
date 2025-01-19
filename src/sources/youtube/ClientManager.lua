local class = require('class')

local YouTubeClientManager, get = class('YouTubeClientManager')

function YouTubeClientManager:__init(luna)
  self._luna = luna
  self._avaliableClients = {}
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
    local clientData = require('./clients/' .. clientName)
    self._avaliableClients[clientName] = clientData
    self._luna.logger:debug('YouTubeClientManager', 'Client [%s] registered!', clientName)
  end
end

function YouTubeClientManager:buildContext()
  -- Check if bypassAgeRestriction is true or false
  if self._luna.config.sources.youtube.bypassAgeRestriction then
    self._ytContext.thirdParty = { embedUrl = 'https://www.youtube.com' }
  else
    self._ytContext.client = {
      userAgent = 'com.google.android.youtube/19.47.41 (Linux; U; Android 14 gzip)',
      clientName = 'ANDROID',
      clientVersion = '19.47.41',
    }
    self._currentClient = 'ANDROID'
  end

  -- Add common fields for 'client'
  self._ytContext.client = self._ytContext.client or {}
  self._ytContext.client.screenDensityFloat = 1
  self._ytContext.client.screenHeightPoints = 1080
  self._ytContext.client.screenPixelDensity = 1
  self._ytContext.client.screenWidthPoints = 1920

  -- Add the alternative client configuration if bypassAgeRestriction is false
  if not self._luna.config.sources.youtube.bypassAgeRestriction then
    self._ytContext.client.clientName = 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
    self._ytContext.client.clientVersion = '2.0'
    self._ytContext.client.userAgent = 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/111.0'
    self._currentClient = 'TVHTML5EMBED'
  end
end

function YouTubeClientManager:switchClient(clientName)
  if not self._avaliableClients[clientName] then
    self._luna.logger:error('YouTubeClientManager', 'Client %s not found!', clientName)
    return false
  end
  if self._currentClient == clientName then return end
  self._luna.logger:debug('YouTubeClientManager', 'Switch to client: ' .. clientName)
  for key, value in pairs(self._avaliableClients[clientName].additionalContexts) do
    self._ytContext.client[key] = value
  end
  self._currentClient = clientName
end

return YouTubeClientManager