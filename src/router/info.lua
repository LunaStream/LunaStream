local metadata = require("../constants/metadata.lua")
local json = require("json")

return function (req, res, answer)
  answer(json.encode(metadata), 200, {  ["Content-Type"] = "application/json" })
end