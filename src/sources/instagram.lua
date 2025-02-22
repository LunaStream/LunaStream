local http = require("coro-http")
local json = require("json")
local urlp = require("url-param")
local AbstractSource = require("./abstract.lua")
local encoder = require("../track/encoder.lua")
local class = require("class")

local Instagram = class("Instagram", AbstractSource)

function Instagram:__init(luna)
  AbstractSource.__init(self)
  self._luna = luna
end

function Instagram:setup() return self end

function Instagram:search(query)
  return self:buildError("Search not supported for Instagram", "fault", "Instagram Source")
end

function Instagram:getPostId(url)
  if not url then return nil, "Instagram URL not provided" end
  local postId = url:match("instagram%.com/p/([%w_-]+)")
  if not postId then postId = url:match("instagram%.com/reels?/([%w_-]+)") end
  if not postId then return nil, "Instagram post/reel ID not found" end
  return postId
end

function Instagram:encodePostRequestData(shortcode)
  local variables = json.encode(
    {
      shortcode = shortcode,
      fetch_comment_count = "null",
      fetch_related_profile_media_count = "null",
      parent_comment_count = "null",
      child_comment_count = "null",
      fetch_like_count = "null",
      fetch_tagged_user_count = "null",
      fetch_preview_comment_count = "null",
      has_threaded_comments = "false",
      hoisted_comment_id = "null",
      hoisted_reply_id = "null",
    }
  )

  local requestData = {
    av = "0",
    __d = "www",
    __user = "0",
    __a = "1",
    __req = "3",
    __hs = "19624.HYP:instagram_web_pkg.2.1..0.0",
    dpr = "3",
    __ccg = "UNKNOWN",
    __rev = "1008824440",
    __s = "xf44ne:zhh75g:xr51e7",
    __hsi = "7282217488877343271",
    __dyn = "7xeUmwlEnwn8K2WnFw9-2i5U4e0yoW3q32360CEbo1nEhw2nVE4W0om78b87C0yE5ufz81s8hwGwQwoEcE7O2l0Fwqo31w9a9x-0z8-U2zxe2GewGwso88cobEaU2eUlwhEe87q7-0iK2S3qazo7u1xwIw8O321LwTwKG1pg661pwr86C1mwraCg",
    __csr = "gZ3yFmJkillQvV6ybimnG8AmhqujGbLADgjyEOWz49z9XDlAXBJpC7Wy-vQTSvUGWGh5u8KibG44dBiigrgjDxGjU0150Q0848azk48N09C02IR0go4SaR70r8owyg9pU0V23hwiA0LQczA48S0f-x-27o05NG0fkw",
    __comet_req = "7",
    lsd = "AVqbxe3J_YA",
    jazoest = "2957",
    __spin_r = "1008824440",
    __spin_b = "trunk",
    __spin_t = "1695523385",
    fb_api_caller_class = "RelayModern",
    fb_api_req_friendly_name = "PolarisPostActionLoadPostQueryQuery",
    variables = variables,
    server_timestamps = "true",
    doc_id = "10015901848480474",
  }

  local parts = {}
  for key, value in pairs(requestData) do table.insert(parts, key .. "=" .. value) end
  return table.concat(parts, "&")
end

function Instagram:isLinkMatch(link) return link:match("instagram%.com") ~= nil, nil end

function Instagram:fetchFromGraphQL(postId, timeout)
  if not postId then return nil, "Post ID not provided" end

  local API_URL = "https://www.instagram.com/api/graphql"
  local headers = {
    { "Accept", "*/*" },
    { "Content-Type", "application/x-www-form-urlencoded" },
    { "User-Agent", "Mozilla/5.0 (Linux; Android 11; SAMSUNG SM-G973U)" },
    { "X-FB-Friendly-Name", "PolarisPostActionLoadPostQueryQuery" },
    { "X-CSRFToken", "RVDUooU5MYsBbS1CNN3CzVAuEP8oHB52" },
    { "X-IG-App-ID", "1217981644879628" },
    { "X-FB-LSD", "AVqbxe3J_YA" },
  }

  local encodedData = self:encodePostRequestData(postId)
  local response, body = http.request("POST", API_URL, headers, encodedData)

  if response.code ~= 200 then return nil, "Request failed with code " .. response.code end

  local data = json.decode(body)
  if not data or not data.data or not data.data.xdt_shortcode_media then
    return nil, "Invalid response from Instagram API"
  end

  local media = data.data.xdt_shortcode_media
  if not media.is_video then return nil, "This post is not a video" end

  local videoUrl = media.video_url
  if not videoUrl then return nil, "Video URL not found" end

  return {
    videoUrl = videoUrl,
    author = media.owner.username,
    length = media.video_duration,
    thumbnail = media.display_url,
    title = media.edge_media_to_caption.edges[1].node.text or "Instagram Video",
  }
end

function Instagram:loadForm(query)
  local postId, err = self:getPostId(query)
  if not postId then return self:buildError(err or "Invalid Instagram URL", "fault", "Instagram Source") end

  local videoData, err = self:fetchFromGraphQL(postId)
  if not videoData then return self:buildError(err or "Video not available", "fault", "Instagram Source") end

  local trackInfo = {
    identifier = postId,
    title = videoData.title,
    author = videoData.author or "User Unknown",
    length = videoData.length * 1000 or 0,
    sourceName = "Instagram",
    artworkUrl = videoData.thumbnail or "",
    uri = query,
    isStream = false,
    isSeekable = true,
    isrc = nil,
  }

  local track = {
    encoded = encoder(trackInfo),
    info = trackInfo,
    pluginInfo = {},
  }

  return { loadType = "track", data = track }
end

function Instagram:loadStream(track)
  local videoUrl = self:fetchFromGraphQL(track.info.identifier).videoUrl

  if not videoUrl then return self:buildError("Not found", "fault", "Instagram Source") end

  return { url = videoUrl, format = "mp4", protocol = "http" }
end

return Instagram
