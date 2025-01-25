local http = require("coro-http")
local urlp = require("url-param")
local json = require("json")

local AbstractSource = require('./abstract.lua')
local encoder = require("../track/encoder.lua")
local class = require('class')

local Deezer = class('Deezer', AbstractSource)

function Deezer:__init(luna)
    AbstractSource.__init(self)
    self._luna = luna
    self._license_token = nil
    self._form_validation = nil
end

function Deezer:setup()
    local random_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local api_token = random_chars:sub(math.random(1, #random_chars), math.random(1, #random_chars))
    
    local url = string.format(
        "https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token=%s", 
        api_token
    )

    local response, data = http.request("GET", url)

    if response.code ~= 200 then
        self._luna.logger:error('Deezer', 'Failed initializing Deezer source')
        return nil
    end

    data = json.decode(data)

    if data.error  == true then
        self._luna.logger:error('Deezer', 'Failed initializing Deezer source')
        return nil
    end

    self._license_token = data.results.USER.OPTIONS.license_token
    self._check_form = data.results.checkForm

    return self
end

function Deezer:search(query)
    self._luna.logger:debug('Deezer', 'Searching: ' .. query)
    local query_link = string.format("https://api.deezer.com/2.0/search?q=%s", urlp.encode(query))
    local response, data = http.request("GET", query_link)

    if response.code ~= 200 then
        local error_message = string.format("Server response error: %s | On query: %s", response.code, query)
        self._luna.logger:error('Deezer', error_message)
        return self:buildError(error_message, "fault", "Deezer Source")
    end

    data = json.decode(data)

    if data.error then
        local api_error_message = string.format("API error: %s | On query: %s", data.error.message, query)
        self._luna.logger:error('Deezer', api_error_message)
        return self:buildError(api_error_message, "fault", "Deezer Source")
    end

    if data.total == 0 then
        self._luna.logger:debug('Deezer', string.format("No results found for query: %s", query))
        return {
            loadType = "empty",
            data = {}
        }
    end

    local max_results = self._luna.config.sources.maxSearchResults
    if data.total > max_results then
        data.data = { table.unpack(data.data, 1, max_results) }
    end

    local tracks = {}

    for _, track in ipairs(data.data) do
        local trackinfo = {
            identifier = track.id,
            uri = track.link,
            title = track.title,
            author = track.artist.name,
            length = track.duration * 1000,
            isSeekable = true,
            isStream = false,
            isrc = track.isrc,
            artworkUrl = data.cover_xl or data.picture_xl,
            sourceName = "deezer"
        }
        
        table.insert(tracks, {
            encoded = encoder(trackinfo),
            info = trackinfo,
            pluginInfo = {}
        })
    end

    return {
        loadType = "search",
        data = tracks
    }
end

function Deezer:getLinkType(query)
    local type, id = string.match(query, "/(%a+)/(%d+)$")
    return type, id
end

function Deezer:isLinkMatch(query)
    local valid = string.match(query, "^https?://www%.deezer%.com/")
        and (string.match(query, "/album/%d+$")
        or string.match(query, "/track/%d+$")
        or string.match(query, "/playlist/%d+$"))

    return valid ~= nil
end

function Deezer:loadForm(query)
    local type, id = self:getLinkType(query)
    if not type then
        self._luna.logger:error('Deezer', 'Type not supported')
        return {
            loadType = "error",
            data = {},
            error = {
                message = "Type not supported",
                type = "fault",
                source = "Deezer Source"
            }
          }
    end
    
    local url = string.format("https://api.deezer.com/%s/%s", type, id)
    local response, data = http.request("GET", url)

    if response.code ~= 200 then
        self._luna.logger:error('Deezer', 'Failed loading form')
        return {
            loadType = "error",
            data = {},
            error = {
                message = "Failed loading form",
                type = "fault",
                source = "Deezer Source"
            }
          }
    end

    data = json.decode(data)

    if data.error then
        self._luna.logger:error('Deezer', 'Failed loading form')
        return {
            loadType = "error",
            data = {},
            error = {
                message = "Failed loading form",
                type = "fault",
                source = "Deezer Source"
            }
          }
    end

    local tracks = {}
    if type == "track" then
        local trackinfo = {
            identifier = data.id,
            uri = data.link,
            title = data.title,
            author = data.artist.name,
            length = data.duration * 1000,
            isSeekable = true,
            isStream = false,
            isrc = data.isrc,
            artworkUrl = data.album.cover_xl or data.album.picture_xl,
            sourceName = "deezer"
        }
        
        table.insert(tracks, {
            encoded = encoder(trackinfo),
            info = trackinfo,
            pluginInfo = {}
        })

        return {
            loadType = "track",
            data = {
                info = {
                    name = data.title,
                    selectedTrack = 0
                },
                tracks = tracks
            }
        }
    end

    if type == "album" then
        for _, track in ipairs(data.tracks.data) do
            local trackinfo = {
                identifier = track.id,
                uri = track.link,
                title = track.title,
                author = track.artist.name,
                length = track.duration * 1000,
                isSeekable = true,
                isStream = false,
                isrc = track.isrc,
                artworkUrl = data.cover_xl or data.picture_xl,
                sourceName = "deezer"
            }
            
            table.insert(tracks, {
                encoded = encoder(trackinfo),
                info = trackinfo,
                pluginInfo = {}
            })
        end

        return {
            loadType = "playlist",
            data = {
                info = {
                    name = data.title,
                    selectedTrack = 0
                },
                tracks = tracks
            }
        }
    end

    if type == "playlist" then
        for _, track in ipairs(data.tracks.data) do
            local trackinfo = {
                identifier = track.id,
                uri = track.link,
                title = track.title,
                author = track.artist.name,
                length = track.duration * 1000,
                isSeekable = true,
                isStream = false,
                isrc = track.isrc,
                artworkUrl = data.picture_xl,
                sourceName = "deezer"
            }
            
            table.insert(tracks, {
                encoded = encoder(trackinfo),
                info = trackinfo,
                pluginInfo = {}
            })
        end

        return {
            loadType = "playlist",
            data = {
                info = {
                    name = data.title,
                    selectedTrack = 0
                },
                tracks = tracks
            }
        }
    end 
    
    self._luna.logger:error('Deezer', 'Type not supported')
    return {
        loadType = "error",
        data = {},
        error = {
            message = "Type not supported",
            type = "fault",
            source = "Deezer Source"
        }
    }
end


function Deezer:loadStream(track)

end

return Deezer
