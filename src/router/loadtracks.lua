local json = require("json")

return function (req, res, answer, luna)
  local getIdentifier = req.path:match("?identifier=([^%s]+)")
  if not getIdentifier then
    return answer(json.encode({
      error = "Missing identifier"
    }), 400, {  ["Content-Type"] = "application/json" })
  end

  getIdentifier = require("url").decode(getIdentifier)
  local getQuerySource = getIdentifier:match("([^%s]+):[^%s]+")
  local getQuery = getIdentifier:match("[^%s]+:([^%s]+)")
  local isLink = getIdentifier:find("https://") or getIdentifier:find("http://")

  if (
    not getQuery
    and not isLink
    and not getQuerySource
  ) then
    return answer(json.encode({
      error = "Identifier not in required form like source:query or not a link"
    }), 400, {  ["Content-Type"] = "application/json" })
  end

  local search_res = nil

  if isLink then
    search_res = luna.sources:loadForm(getIdentifier)
  else
    search_res = luna.sources:loadTracks(getQuery, getQuerySource)
  end

  if search_res and search_res.loadType == "error" then
    return answer(json.encode(search_res), 400, {  ["Content-Type"] = "application/json" })
  end

  answer(json.encode(search_res), 200, {  ["Content-Type"] = "application/json" })
end