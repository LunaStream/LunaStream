local class = require('class')
local dgram = require('dgram')

local Emitter = require('./Emitter')
local sodium = require('./sodium')

local UDPController = class('UDPController', Emitter)

function UDPController:__init(production_mode)
  Emitter.__init(self)
  self._udp = dgram.createSocket('udp4')

  self._address = nil
  self._port = nil
  self._ssrc = nil
  self._sec_key = nil
  self._crypto = sodium(production_mode)

  self:setupEvents()
end

function UDPController:updateCredentials(address, port, ssrc, sec_key)
  self._address = address
  self._port = port
  self._ssrc = ssrc
  self._sec_key = sec_key and self._crypto:key(sec_key) or self._sec_key
end

function UDPController:ipDiscovery()
  local packet = string.pack('>I2I2I4c64H', 0x1, 70,
    self._ssrc,
    self._address,
    self._port
  )

  self._udp:recvStart()

  self:send(packet)

  local success, data = self:waitFor('message', 20000)

  self._udp:recvStop()

  assert(success, data)

  return {
    ip = string.unpack('xxxxxxxxz', data),
    port = string.unpack('>I2', data, #data - 1)
  }
end

function UDPController:send(packet)
  self._udp:send(packet, self._port, self._address)
end

function UDPController:start()
  self._udp:recvStart()
end

function UDPController:stop()
  self._udp:recvStop()
  self._udp:removeAllListeners('message')
  self._udp:removeAllListeners('error')
end

function UDPController:setupEvents()
  self._udp:on('message', function (packet)
    self:emit('message', packet)
    print('[LunaStream / Voice | UDP]: Received data from UDP server with Discord.')
  end)

  self._udp:on('error', function (err)
    print('[LunaStream / Voice | UDP]: Received error from UDP server with Discord.')
    p(err)
  end)
end

return UDPController