local bundle = require("luvi").bundle
local fs = require("fs")
local json = require("json")

return function (isDevMode)
  if isDevMode then
    local data = fs.readFileSync('./manifest.json')
    return json.decode(data)
  else
    local data = bundle.readfile('./manifest.json')
    return json.decode(data)
  end
end