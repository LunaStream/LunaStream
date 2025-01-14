local class = require('class')

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
	error("Missing build track function")
end

return AbstractSource