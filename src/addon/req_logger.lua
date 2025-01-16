local config = require('../utils/config')

return function (req, res, go, luna)
  if not config.logger.request.enable then go() end
  go()
  luna.logger:info('WebServer', "%s %s %s", res.code, req.method, req.path)
  if config.logger.request.withHeader then
    p(req.headers)
  end
end