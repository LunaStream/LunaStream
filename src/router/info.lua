local json = require("json")

return function (req, res, answer, luna)
  answer(json.encode(luna.manifest), 200, {  ["Content-Type"] = "application/json" })
end