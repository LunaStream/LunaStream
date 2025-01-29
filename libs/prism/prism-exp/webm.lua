local fs = require('fs')
local prism_opus = require('opus')

fs.createReadStream('./sample/videoplayback.webm')
  :pipe(prism_opus.WebmDemuxer:new())
  :pipe(fs.createWriteStream('./results/videoplayback.demuxed.webm'))