local class = require('class')

local StatusMonitor = class('StatusMonitor')

function StatusMonitor:__init(luna) self._luna = luna end

function StatusMonitor:get()
  return {
    players = 0,
    playingPlayers = 0,
    uptime = os.time() - self._luna._initialRunTime,
    memory = process.memoryUsage(), -- This in byte
    cpu = process.cpuUsage(),
  }
end

return StatusMonitor
