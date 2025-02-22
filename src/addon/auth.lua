local json = require("json")
local config = require('../utils/config')

return function(req, res, go)
  local pass = req.headers["authorization"]
  if not pass then
    res.body = json.encode({ error = "Missing authorization" })
    res.code = 400
    res.headers["Content-Type"] = "application/json"
    return
  end

  if pass ~= config.server.password then
    res.body = json.encode({ error = "Authorization failed" })
    res.code = 401
    res.headers["Content-Type"] = "application/json"
    return
  end
  go()
end
