local json = require("json")

return function (req, res, answer, luna)
  answer(json.encode(luna.services.statusMonitor:get()), 200, {  ["Content-Type"] = "application/json" })
end