local fs = require('fs')

local date = os.date
local format = string.format
local stdout = _G.process.stdout.handle ---@diagnostic disable-line: undefined-field
local openSync, writeSync = fs.openSync, fs.writeSync

-- local BLACK   = 30
local RED = 31
local GREEN = 32
local YELLOW = 33
-- local BLUE    = 34
local MAGENTA = 35
local CYAN = 36
-- local WHITE   = 37

local config = {
	{ 'ERROR  ', RED },
	{ 'WARNING', YELLOW },
	{ 'INFO   ', GREEN },
	{ 'DEBUG  ', CYAN },
	{ 'VERBOSE', MAGENTA },
}

local function table_args(is_file, d, tag, entry, msg)
	local res = { d, tag[1], entry, msg }
	if entry == nil then
		res = { d, tag[1], msg }
	end
	if not is_file then
		res[2] = tag[3]
	end
	return res
end

do
	-- parse config
	local bold = 1
	for _, v in ipairs(config) do
		v[3] = format('\27[%i;%im%s\27[0m', bold, v[2], v[1])
	end
end

local Logger = require('class')('LoggerService')

function Logger:__init(level, dateTime, file, typePad)
	self._level = level
	self._dateTime = dateTime
	self._file = file and openSync(file, 'a')
	self._typePad = typePad
end

function Logger:pad_end(str, length)
	return str .. string.rep(' ', length - #str)
end

--[=[
@m log
@p level number
@p msg string
@p ... *
@r string
@d If the provided level is less than or equal to the log level set on
initialization, this logs a message to stdout as defined by Luvit's `process`
module and to a file if one was provided on initialization. The `msg, ...` pair
is formatted according to `string.format` and returned if the message is logged.
]=]
function Logger:log(level, entry, msg, ...)
	if self._level < level then return end

	local tag = config[level]
	if not tag then return end

	msg = format(msg, ...)

	local d = date(self._dateTime)

	local str_format = '%s | %s | %s \n'
	local class_name = nil

	if self._typePad > 0 then
		str_format = '%s | %s | %s | %s\n'
		class_name = self:pad_end(entry, self._typePad)
	end

	if self._file then
		local args = table_args(true, d, tag, class_name, msg)
		writeSync(self._file, -1, format(str_format, table.unpack(args)))
	end
	local args = table_args(false, d, tag, class_name, msg)
	stdout:write(format(str_format, table.unpack(args)))

	return msg
end

function Logger:error(class, msg, ...)
	self:log(1, class, msg, ...)
end

function Logger:warn(class, msg, ...)
	self:log(2, class, msg, ...)
end

function Logger:info(class, msg, ...)
	self:log(3, class, msg, ...)
end

function Logger:debug(class, msg, ...)
	self:log(4, class, msg, ...)
end

function Logger:verbose(class, msg, ...)
	self:log(5, class, msg, ...)
end

return Logger