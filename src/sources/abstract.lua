local class = require('class')
local encoder = require("../track/encoder.lua")

local AbstractSource = class('AbstractSource')

function AbstractSource.__init()
	
end

function AbstractSource:setup()
  error('Missing :setup() function')
end

function AbstractSource:search(query, source)
  error('Missing :search() function')
end

function AbstractSource:isLinkMatch(query, source)
  error('Missing :isLinkMatch() function')
end

function AbstractSource:loadForm(query, source)
  error('Missing :loadForm() function')
end

function AbstractSource:buildTrack(data)
	local isrc = nil
	if type(data.publisher_metadata) == "table" then
		isrc = data.publisher_metadata.isrc
	end

	local info = {
		title = data.title,
		author = data.user.permalink,
		identifier = tostring(data.id),
		uri = data.permalink_url,
		is_stream = false,
		is_seekable = true,
		source_name = self._sourceName,
		isrc = isrc,
		artwork_url = data.artwork_url,
		length = data.full_duration,
	}

	return {
		encoded = encoder(info),
		info = info
	}
end

return AbstractSource