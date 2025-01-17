return function (req, res, answer, luna)
  answer(luna.manifest.version.semver, 200, {  ["Content-Type"] = "application/json" })
end