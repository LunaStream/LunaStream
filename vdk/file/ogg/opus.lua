local quickmedia = require('quickmedia')

local FileStream = require('../../../src/voice/stream/FileStream')

return function (vdk)
  vdk:log(false, 'Song Infomation: kz_livetune - Decorator (ft. Hatsune Miku), format: ogg (opus)')

  return FileStream:new('./vdk/audio/kz_livetune_decorator.opus.ogg')
    :pipe(quickmedia.opus.OggDemuxer:new())
    :pipe(quickmedia.opus.Decoder:new(vdk._voice._opus))
end