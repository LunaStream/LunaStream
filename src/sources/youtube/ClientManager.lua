local class = require('class')
local http = require('coro-http')
local json = require('json')
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
    IOS = {
      clientName = 'IOS',
      clientVersion = '19.47.7',
      userAgent = 'com.google.ios.youtube/19.47.7 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)',
      deviceMake = 'Apple',
      deviceModel = 'iPhone 13',
      osName = 'iOS',
      osVersion = '17.5.1.21F90',
      hl = 'en',
      gl = 'US',
      utcOffsetMinutes = 0
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
    }
  }
  self._ytContext = {}
  self._currentClient = ''
  self._visitorData = nil
end

function get:ytContext()
  return self._ytContext
end

function YouTubeClientManager:setup()
  self:buildContext()
  self._luna.logger:debug('YouTubeClientManager', 'Set up contexts and multi client data complete')
  return self
end

function YouTubeClientManager:buildContext()
  self:switchClient('ANDROID')
end

function YouTubeClientManager:_fetchVisitorData()
  if self._visitorData then
    return self._visitorData
  end

  local success, response, data = pcall(http.request,
    "GET", "https://www.youtube.com/sw.js_data", {
      { "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" }
    }
  )

  if success and response.code == 200 then
    data = data:gsub("^%)]}'\n", "")
    local ok, parsed = pcall(json.decode, data)
    if ok and parsed then
      self._visitorData = parsed[1][3][1][1][14]
      self._luna.logger:debug('YouTube', string.format('Visitor data: %s', self._visitorData:gsub("%%", "%%%%")))
      return self._visitorData
    else
      self._luna.logger:warn('YouTube', 'Failed to parse visitorData')
    end
  else
    self._luna.logger:warn('YouTube', 'Failed to fetch visitorData')
  end
end

function YouTubeClientManager:switchClient(clientName)
  if not self._avaliableClients[clientName] then
    self._luna.logger:error('YouTubeClientManager', 'Client %s not found!', clientName)
    return false
  end

  if self._currentClient == clientName then
    return
  end

  self._luna.logger:debug('YouTubeClientManager', 'Switching to client: ' .. clientName)
  self._ytContext.client = self._avaliableClients[clientName]
  self._ytContext.client.visitorData = self:_fetchVisitorData()
end

return YouTubeClientManager
