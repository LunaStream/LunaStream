local config = require('../utils/config')

return function (req, res, go)
  if not config.logger.request.enable then go() end
  go()
  print(string.format("[webserver]: %s %s %s", res.code, req.method, req.path))
  if config.logger.request.withHeader then
    p(req.headers)
  end
end