local class = require('class')
local ffi = require('ffi')

local enums = require('./enums')

local Opus, get = class('Opus')

local typeof = ffi.typeof

function Opus:__init(production)
  self._enums = enums
  local os_name = require('los').type()
  local arch = os_name == 'darwin' and 'universal' or jit.arch
  local lib_name_list = {
    win32 = '.dll',
    linux = '.so',
    darwin = '.dylib'
  }
  local bin_dir = string.format('./bin/opus_%s_%s%s', os_name, arch, lib_name_list[os_name])

  ffi.cdef(require('./cdef.lua'))

  local loaded, lib = pcall(ffi.load, production and './native/opus' or bin_dir)

  self._lib = lib

  if not loaded then
    error(lib)
    return nil, lib
  end

  self._int_ptr_t = typeof('int[1]')
  self._opus_int32_t = typeof('opus_int32')
  self._opus_int32_ptr_t = typeof('opus_int32[1]')

	self._encoder = require('./encoder')(self)
	self._decoder = require('./decoder')(self)
end

function Opus:throw(code)
  local version = ffi.string(self.lib.opus_get_version_string())
	local message = ffi.string(self.lib.opus_strerror(code))
	return error(string.format('[%s] %s', version, message))
end

function Opus:check(value)
	return value >= enums.OK and value or self:throw(value)
end

function get:enums()
  return self._enums
end

function get:lib()
  return self._lib
end

function get:encoder()
  return self._encoder
end

function get:decoder()
  return self._decoder
end

return Opus