local class = require('class')

local YouTubeClientManager, get = class('YouTubeClientManager')

function YouTubeClientManager:__init(luna)
  self._luna = luna
  self._avaliableClients = {
    ANDROID = {
      clientName = 'ANDROID',
      clientVersion = '20.03.35',
      userAgent = 'com.google.android.youtube/20.03.35 (Linux; U; Android 14 gzip)',
      deviceMake = 'Google',
      deviceModel = 'Pixel 6',
      osName = 'Android',
      osVersion = '14',
      hl = 'en',
      gl = 'US',
      androidSdkVersion = '30',
    },
    ANDROID_MUSIC = {
      clientName = 'ANDROID_MUSIC',
      clientVersion = '8.02.53',
      userAgent = 'com.google.android.apps.youtube.music/8.02.53 (Linux; U; Android 14 gzip)',
      deviceMake = 'Google',
      deviceModel = 'Pixel 6',
      osName = 'Android',
      osVersion = '14',
      hl = 'en',
      gl = 'US',
      androidSdkVersion = '30',
    },
  }
  self._ytContext = {}
  self._currentClient = ''
end

function get:ytContext() return self._ytContext end

function YouTubeClientManager:setup()
  self:buildContext()
  self._luna.logger:debug('YouTubeClientManager', 'Set up contexts and multi client data complete')
  return self
end

function YouTubeClientManager:buildContext() self:switchClient('ANDROID') end

function YouTubeClientManager:switchClient(clientName)
  if not self._avaliableClients[clientName] then
    self._luna.logger:error('YouTubeClientManager', 'Client %s not found!', clientName)
    return false
  end

  if self._currentClient == clientName then return end

  self._luna.logger:debug('YouTubeClientManager', 'Switching to client: ' .. clientName)
  self._ytContext.client = self._avaliableClients[clientName]
end

return YouTubeClientManager
