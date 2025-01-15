local json = require("json")

return function(req, res, answer, luna)
    local session_id = req.params.sessionId
    local guild_id = req.params.guildId

    if not session_id then
        return answer('{ "error": "Missing session_id field" }', 400, { ["Content-Type"] = "application/json" })
    end

    if not luna._sessions[session_id] then
        return answer('{ "error": "Invalid session_id" }', 404, { ["Content-Type"] = "application/json" })
    end

    local players = luna._sessions[session_id].players

    if req.method == "GET" then
        if not guild_id then
            if not players or next(players) == nil then
                return answer("[]", 200, { ["Content-Type"] = "application/json" })
            end

            local response = {}
            for id, player in pairs(players) do
                table.insert(response, {
                    guildId = id,
                    track = player.track or {},
                    volume = player.volume or 0,
                    paused = player.paused or false,
                    state = player.state or {},
                    voice = player.voice or {},
                    filters = player.filters or {}
                })
            end
            return answer(json.encode(response), 200, { ["Content-Type"] = "application/json" })
        end

        local player = players and players[guild_id]
        if player then
            return answer(json.encode({
                guildId = guild_id,
                track = player.track or {},
                volume = player.volume or 0,
                paused = player.paused or false,
                state = player.state or {},
                voice = player.voice or {},
                filters = player.filters or {}
            }), 200, { ["Content-Type"] = "application/json" })
        end

        return answer('{ "error": "Invalid guild_id" }', 404, { ["Content-Type"] = "application/json" })

    elseif req.method == "PATCH" then
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

    elseif req.method == "DELETE" then
        if not guild_id then
            return answer('{ "error": "Missing guild_id field" }', 400, { ["Content-Type"] = "application/json" })
        end

        if players[guild_id] then
            players[guild_id] = nil
            return answer("", 204, { ["Content-Type"] = "application/json" })
        end

        return answer('{ "error": "Invalid guild_id" }', 404, { ["Content-Type"] = "application/json" })
    else
        return answer('{ "error": "Unsupported HTTP method" }', 405, { ["Content-Type"] = "application/json" })
    end
end
