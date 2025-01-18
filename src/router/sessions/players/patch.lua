local json = require("json")

return function (req, answer, guild_id, players)
  if not guild_id then
    return answer('{ "error": "Missing guild_id field" }', 400, { ["Content-Type"] = "application/json" })
  end

  local body = json.decode(req.body or "{}")
  local player = players[guild_id] or {}

  if body.track then
    player.track = {
      encoded = body.track.encoded or player.track and player.track.encoded or "",
      identifier = body.track.identifier or player.track and player.track.identifier or nil,
      userData = body.track.userData or player.track and player.track.userData or nil
    }
  end

  player.position = body.position or player.position or 0
  player.endTime = body.endTime or player.endTime or 0
  player.volume = body.volume or player.volume or 0
  player.paused = body.paused or player.paused or false
  player.filters = body.filters or player.filters or {}
  player.voice = body.voice or player.voice or {}
  player.state = body.state or player.state or {}

  players[guild_id] = player

  return answer(json.encode({
      guildId = guild_id,
      track = player.track,
      volume = player.volume,
      paused = player.paused,
      state = player.state,
      voice = player.voice,
      filters = player.filters
  }), 200, { ["Content-Type"] = "application/json" })
end