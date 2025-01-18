local json = require("json")

return function(answer, guild_id, players)
  if not guild_id then
    return answer('{ "error": "Missing guild_id field" }', 400, { ["Content-Type"] = "application/json" })
  end

  if players[guild_id] then
    players[guild_id] = nil
    return answer("", 204, { ["Content-Type"] = "application/json" })
  end

  return answer('{ "error": "Invalid guild_id" }', 404, { ["Content-Type"] = "application/json" })
end