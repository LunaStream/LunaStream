local fs = require('fs')
local prism_opus = require('opus')

fs.createReadStream('./sample/speech_orig.ogg')
  :pipe(prism_opus.OggDemuxer:new())
  :pipe(fs.createWriteStream('./results/speech_orig.demuxed.ogg'))