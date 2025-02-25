local FileStream = require('../../../src/voice/stream/FileStream')
local mpg123 = require('audioDecoder').mpg123

return function (vdk)
  vdk:log(false, 'Song Infomation: kz_livetune - Decorator (ft. Hatsune Miku), format: mp3')

  return FileStream:new('./vdk/audio/kz_livetune_decorator.mp3')
    :pipe(mpg123:new('./bin/mpg123/win32/x64.dll'))
end