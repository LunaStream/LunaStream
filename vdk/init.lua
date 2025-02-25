local childprocess = require("childprocess")
local fs = require('fs')

local function slice(t, first, last)
  local sliced = {}
  for i = first, last do
    sliced[#sliced + 1] = t[i]
  end
  return sliced
end

local fd = nil
local cmd = "luvit"  -- Change this to the command you want to capture logs from
local input_arg = slice(process.argv, 2, #process.argv)  -- Arguments for the command

if input_arg[1] == "--save-log" then
  table.remove(input_arg, 1)
  fd = fs.openSync('./vdk.log', 'w+')
end

local args = { './vdk/main', table.unpack(input_arg) }

local proc = childprocess.spawn(cmd, args)

proc.stdout:on("data", function(chunk)
  print(chunk:sub(1, -2))
  if fd then
    fs.writeSync(fd, -1, chunk)
  end
end)

proc.stderr:on("data", function(chunk)
  print(chunk:sub(1, -2))
  if fd then
    fs.writeSync(fd, -1, chunk)
  end
end)

proc:on("exit", function(code, signal)
  if fd then
    fs.writeSync(fd, -1, "----- EOS -----")
    fs.closeSync(fd)
  end
end)