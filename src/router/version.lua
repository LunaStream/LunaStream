local metadata = require("../../package.lua")

return function (req, res, answer)
  answer(metadata.versionExtended.semver, 200, {  ["Content-Type"] = "application/json" })
end