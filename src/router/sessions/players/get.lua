local json = require("json")

return function(answer, guild_id, players)
  if not guild_id then
    if not players or next(players) == nil then return answer("[]", 200, {
      ["Content-Type"] = "application/json",
    }) end

    local response = {}

    for id, player in pairs(players) do
      table.insert(
        response, {
          guildId = id,
          track = player.track or {},
          volume = player.volume or 0,
          paused = player.paused or false,
          state = player.state or {},
          voice = player.voice or {},
          filters = player.filters or {},
        }
      )
    end

    return answer(
      json.encode(response), 200, { ["Content-Type"] = "application/json" }
    )
  end

  local player = players and players[guild_id]

  if player then
    return answer(
      json.encode(
        {
          guildId = guild_id,
          track = player.track or {},
          volume = player.volume or 0,
          paused = player.paused or false,
          state = player.state or {},
          voice = player.voiceState or {},
          filters = player.filters or {},
        }
      ), 200, { ["Content-Type"] = "application/json" }
    )
  end

  return answer(
    '{ "error": "Invalid guild_id" }', 404, {
      ["Content-Type"] = "application/json",
    }
  )
end
