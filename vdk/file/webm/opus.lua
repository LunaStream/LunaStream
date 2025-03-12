local quickmedia = require('quickmedia')

local FileStream = require('../../../src/voice/stream/FileStream')

return function (vdk)
  vdk:log(false, 'Song Infomation: kz_livetune - Decorator (ft. Hatsune Miku), format: webm (opus)')

  return FileStream:new('./vdk/audio/kz_livetune_decorator.opus.weba')
    :pipe(quickmedia.opus.WebmDemuxer:new())
    :pipe(quickmedia.opus.Decoder:new(vdk._voice._opus))
end