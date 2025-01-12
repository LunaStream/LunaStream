local metadata = require("../constants/metadata.lua")

return function (req, res, answer)
  answer(metadata.version.semver, 200, {  ["Content-Type"] = "application/json" })
end