local class = require('class')
local dgram = require('dgram')

local Emitter = require('./Emitter')
local sodium = require('sodium')

local UDPController, get = class('UDPController', Emitter)

function UDPController:__init(production_mode)
  Emitter.__init(self)
  self._udp = dgram.createSocket('udp4')

  self._address = nil
  self._port = nil
  self._ssrc = nil
  self._sec_key = nil
  self._crypto = sodium(self:getBinaryPath('sodium', production_mode))

  self:setupEvents()
end

function UDPController:getBinaryPath(name, production)
  local os_name = require('los').type()
  local arch = os_name == 'darwin' and 'universal' or jit.arch
  local lib_name_list = {
    win32 = '.dll',
    linux = '.so',
    darwin = '.dylib'
  }
  local bin_dir = string.format('./bin/%s_%s_%s%s', name, os_name, arch, lib_name_list[os_name])
  return production and './native/' .. name or bin_dir
end

function UDPController:updateCredentials(address, port, ssrc, sec_key)
  self._address = address or self._address
  self._port = port or self._port
  self._ssrc = ssrc or self._ssrc
  self._sec_key = sec_key and self._crypto:key(sec_key) or self._sec_key
end

function UDPController:ipDiscovery()
  local packet = string.pack('>I2I2I4c64H', 0x1, 70,
    self.ssrc,
    self.address,
    self.port
  )

  self.udp:recvStart()

  self:send(packet)

  local success, data = self:waitFor('message', 20000)

  self.udp:recvStop()

  assert(success, data)

  return {
    ip = string.unpack('xxxxxxxxz', data),
    port = string.unpack('>I2', data, #data - 1)
  }
end

function UDPController:send(packet, cb)
  self.udp:send(packet, self._port, self._address, cb)
end

function UDPController:start()
  self.udp:recvStart()
end

function UDPController:stop()
  self.udp:recvStop()
  self.udp:removeAllListeners('message')
  self.udp:removeAllListeners('error')
end

function UDPController:setupEvents()
  self.udp:on('message', function (packet)
    self:emit('message', packet)
    print('[LunaStream / Voice | UDP]: Received data from UDP server with Discord.')
  end)

  self.udp:on('error', function (err)
    print('[LunaStream / Voice | UDP]: Received error from UDP server with Discord.')
    ---@diagnostic disable-next-line: undefined-global
    p(err)
  end)
end

function get:udp()
  return self._udp
end

function get:address()
  return self._address
end

function get:port()
  return self._port
end

function get:ssrc()
  return self._ssrc
end

function get:sec_key()
  return self._sec_key
end

function get:crypto()
  return self._crypto
end

return UDPController
