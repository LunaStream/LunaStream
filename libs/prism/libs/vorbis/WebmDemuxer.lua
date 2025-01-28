local WebmBaseDemuxer = require('abstract/WebmBaseDemuxer')
local VorbisWebmDemuxer = WebmBaseDemuxer:extend()

function VorbisWebmDemuxer:initialize()
  WebmBaseDemuxer.initialize(self)
end

function VorbisWebmDemuxer:_checkData(data, VORBIS_HEAD)
  if string.byte(data, 1) ~= 2 then return true end
  local slice = string.sub(data, 5, 10)
  if slice ~= VORBIS_HEAD then return true end
  return false
end

-- data is a string
function VorbisWebmDemuxer:_checkHead(data)
  if self:_checkData(data, 'vorbis') then
    error('Audio codec is not Vorbis!');
  end

  self._super:push(string.sub(data, 4, 4 + string.byte(data, 2) - 1));
  self._super:push(string.sub(data, (4 + string.byte(data, 2)), (4 + string.byte(data, 2)) + string.byte(data, 3) - 1));
  self._super:push(string.sub(data, 4 + string.byte(data, 2) + string.byte(data, 3)));
end

return VorbisWebmDemuxer