local MusicUtils = require('musicutils')
local audioDecoder = require('audioDecoder')

local FileStream = require('../../../src/voice/stream/FileStream')

return function (vdk)
  vdk:log(false, 'Song Infomation: kz_livetune - Decorator (ft. Hatsune Miku), format: webm (opus)')

  return FileStream:new('./vdk/audio/kz_livetune_decorator.opus.weba')
    :pipe(MusicUtils.opus.WebmDemuxer:new())
    :pipe(audioDecoder.opus:new(vdk._voice._opus))
end