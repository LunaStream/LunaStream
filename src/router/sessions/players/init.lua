local deleteMethod = require('./delete.lua')
local patchMethod = require('./patch.lua')
local getMethod = require('./get.lua')

return function(req, res, answer, luna)
  local session_id = req.params.sessionId
  local guild_id = req.params.guildId

  if not session_id then
    return answer(
      '{ "error": "Missing session_id field" }', 400, {
        ["Content-Type"] = "application/json",
      }
    )
  end
  if not luna.sessions[session_id] then
    return answer(
      '{ "error": "Invalid session_id" }', 404, {
        ["Content-Type"] = "application/json",
      }
    )
  end

  local players = luna.sessions[session_id].players

  if req.method == "GET" then
    return getMethod(answer, guild_id, players)
  elseif req.method == "PATCH" then
    return patchMethod(req, answer, luna, guild_id, players, session_id)
  elseif req.method == "DELETE" then
    return deleteMethod(answer, guild_id, players)
  else
    return answer(
      '{ "error": "Unsupported HTTP method" }', 405, {
        ["Content-Type"] = "application/json",
      }
    )
  end
end
