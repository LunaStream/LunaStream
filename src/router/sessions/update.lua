local json = require("json")

return function (req, res, answer, luna)
  local session_id = req.params.sessionId
  local options = json.decode(req.body)

  if not session_id then
    return answer('{ "error": "Missing session_id field" }', 400, { ["Content-Type"] = "application/json" })
  end

  local current_session = luna.sessions[session_id]

  current_session.resuming = options.resuming or false
  current_session.timeout = options.timeout or 0

  return answer(json.encode({
    resuming = options.resuming or false,
    timeout = options.timeout or 0
  }), 200, { ["Content-Type"] = "application/json" })
end