local json = require("json")

return function (req, res, answer)
  if req.headers["Content-Type"] ~= "application/json" then
    return answer(json.encode({
      error = "Invalid Content-Type"
    }), 400, {  ["Content-Type"] = "application/json" })
  end

  if not req.body then
    return answer(json.encode({
      error = "Missing body"
    }), 400, {  ["Content-Type"] = "application/json" })
  end

  local result, err = require("../track/encoder.lua")(
    json.decode(req.body)
  )

  if err then
    return answer(json.encode({
      error = err
    }), 400, {  ["Content-Type"] = "application/json" })
  end

  answer(result, 200, {  ["Content-Type"] = "text/plain" })
end