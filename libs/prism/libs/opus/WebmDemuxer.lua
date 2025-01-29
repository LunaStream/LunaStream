local WebmBaseDemuxer = require('abstract/WebmBaseDemuxer')
local OpusWebmDemuxer = WebmBaseDemuxer:extend()

function OpusWebmDemuxer:initialize()
  WebmBaseDemuxer.initialize(self)
end

-- data is a string
function OpusWebmDemuxer:_checkHead(data)
  if string.sub(data, 1, 8) ~= 'OpusHead' then
    error('Audio codec is not Opus!');
  end
end

return OpusWebmDemuxer