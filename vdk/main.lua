-- External library
local timer = require('timer')
local json = require('json')
local fs = require('fs')
local class = require('class')

-- Internal library
local Voice = require('../src/voice')

-- Main code
local VoiceDevelopmentKit = class('VoiceDevelopmentKit')

function VoiceDevelopmentKit:__init()
  self._stream = nil
  self._voice = nil
  print('-------------------------------------------')
  print("LunaStream's Voice Development Kit - (L)VDK")
  print("Version: 1.0.0-internal")
  print('-------------------------------------------')
  self:commandHandling()
end

function VoiceDevelopmentKit:commandHandling()
  if process.argv[2] == "help" or not process.argv[2] then return self:commandManual() end

  local mode, format, encoding = process.argv[2], process.argv[3], process.argv[4]

  local str_template = encoding and './%s/%s/%s.lua' or './%s/%s.lua'
  local require_string = string.format(str_template, mode, format, encoding)

  local success, global_stream = pcall(require, require_string)
  if not success then
    self:commandManual()
    self:errorPrint(global_stream)
    return
  end

  self:log(false, 'Currently running mode: %s, type: %s, encoding: %s', mode, format, encoding or 'Not Specified')

  self._stream = global_stream
  self:log(false, 'Now running voice library with credentials gets from vcred.json...')
  self:voiceManager()
end

function VoiceDevelopmentKit:commandManual()
  print('Usage: luvit vdk (--save-log) [mode] [format/type] [encoding]')
  print('├── mode: stream, file')
  print('├── format/type: mpeg, ogg, webm')
  print('└── encoding: vorbis, mp3, opus')
  print('Note: --save-log is optional for save log file, log file is vdk.log')
end

function VoiceDevelopmentKit:voiceManager()
  local vcred_file = fs.readFileSync('./vdk/vcred.json')
  if not vcred_file then
    self:errorPrint('vcred.json not found, please check vcred.example.json')
    os.exit()
  end

  local vcred = json.decode(vcred_file)
  if not vcred then
    self:errorPrint('vcred.json invalid, please check vcred.example.json')
    os.exit()
  end

  self:log(false, 'Voice Infomation:')
  self:log(false, '├── user_id: %s', vcred.user_id, vcred.guild_id)
  self:log(false, '├── guild_id: %s', vcred.guild_id)
  self:log(false, '├── endpoint: %s', vcred.endpoint)
  self:log(false, '├── session_id: %s', vcred.session_id)
  self:log(false, '└── token: %s', vcred.token)

  self._voice = Voice(vcred.guild_id, vcred.user_id)
  self:voiceEventListener()
  self._voice:voiceCredential(vcred.session_id, vcred.endpoint, vcred.token)
  self._voice:connect()

  self:log(false, 'Audio will play after 5s')

  timer.setTimeout(5000, coroutine.wrap(function ()
    self:log(false, 'Now play the song')

    local get_stream = self._stream(self)
    if not get_stream then
      self:log(false, '[---Error---]: Stream not found or invalid return')
      os.exit()
    end

    self._voice:play(get_stream, { encoder = true })
    self:playAudio()
  end))
end

function VoiceDevelopmentKit:voiceEventListener()
  self._voice:on('ready', function ()
    self:log(false, 'Voice is ready!')
  end)

  self._voice:on('debug', function (log, ...)
    if ... then
      p(log, ...)
    else
      print(log)
    end
  end)
end

function VoiceDevelopmentKit:playAudio()
  self:log(false, 'Now play the song')
end

function VoiceDevelopmentKit:errorPrint(data)
  print('-------------------------------------------')
  print('Error: ' .. data)
  print('-------------------------------------------')
end

function VoiceDevelopmentKit:log(inspect, data, ...)
  if not inspect then
    return print('[LunaStream | VDK]: ' .. string.format(data, ...))
  end
  return p('[LunaStream | VDK]: ', data)
end

VoiceDevelopmentKit()