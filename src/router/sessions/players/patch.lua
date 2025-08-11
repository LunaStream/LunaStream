local json = require("json")
local Player = require("../../../managers/player.lua")

return function(req, answer, luna, guild_id, players, session_id)
  local noReplace = req.path:match("?noReplace=([^%s]+)") or false

  if not guild_id then
    return answer(
      '{ "error": "Missing guild_id field" }', 400, {
        ["Content-Type"] = "application/json",
      }
    )
  end

  local body = json.decode(req.body)

  if not body then
    return answer(
      '{ "error": "Missing body field" }', 400, {
        ["Content-Type"] = "application/json",
      }
    )
  end

  local player = players[guild_id] or Player(luna, guild_id, session_id):new()

  if player.guild == nil then
    player.guild = guild_id
  end

  if body.voice ~= player.voiceState then
    player:updateVoiceState(body.voice)
  end

  if body.track then
    if noReplace ~= true or next(player.track) == nil then
      coroutine.wrap(player.play)(player, body.track)
    end
  end

  if body.volume then
    player:setVolume(body.volume)
  end

  players[guild_id] = player

  return answer(
    json.encode(
      {
        guildId = guild_id,
        track = player.track,
        volume = player.volume,
        paused = player.paused,
        state = player.voiceState,
        voice = player.voiceState,
        filters = nil,
      }
    ), 200, { ["Content-Type"] = "application/json" }
  )
end
