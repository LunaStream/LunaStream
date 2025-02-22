local class = require('class')

local AbstractSource = class('AbstractSource')

function AbstractSource.__init() end

function AbstractSource:setup() error('Missing :setup() function') end

function AbstractSource:search(query) error('Missing :search() function') end

function AbstractSource:isLinkMatch(query) error('Missing :isLinkMatch() function') end

function AbstractSource:loadForm(query) error('Missing :loadForm() function') end

function AbstractSource:buildError(message, severity, cause)
  return {
    loadType = "error",
    data = { message = message, severity = severity, cause = cause },
  }, nil
end

function AbstractSource:loadStream(track, additionalData) error("Missing :loadStream() function") end

return AbstractSource
