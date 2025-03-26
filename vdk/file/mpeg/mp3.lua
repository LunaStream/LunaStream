local FileStream = require('../../../src/voice/stream/FileStream')
local quickmedia = require('quickmedia')

return function (vdk)
  vdk:log(false, 'Song Infomation: kz_livetune - Decorator (ft. Hatsune Miku), format: mp3')

  return FileStream:new('./vdk/audio/kz_livetune_decorator.mp3')
    :pipe(quickmedia.mpeg.Mp3Decoder:new('./bin/mpg123/win32/x64.dll'))
end