local fs = require('fs')
local path = require('path')
local json = require('json')
local package_file = require('./package.lua')
local binary_format = package.cpath:match('%p[\\|/]?%p(%a+)')
NULL = json.null

local make = {
	manifest_file_dir = './manifest.json',
	warnings = [[
-- THIS IS PROJECT TREE FILE
-- Do NOT delete this file or it will crash
-- Changes to this file may cause incorrect behavior
-- You will be responsible for this when changing any content in the file.
]],
	version = 'v1.0.0',
	args = {
		build = {
			type = 1,
			desc = 'Build manifest to standalone executable file',
		},
		manifest = {
			type = 2,
			desc = 'Build manifest',
		},
	}
}

function make.run()
	local cli_data, cli_arg = make.get_cli_data()
	local is_github_action, curr_cmd = make.is_github()
	make.l('INFO', 'LunaticSea make')
	make.l('INFO', 'Version: ' .. make.version)

	if is_github_action then
		make.l('INFO', 'Current mode: Github action ' .. cli_arg)
	else
		make.l('INFO', 'Current mode: Internal ' .. cli_arg)
	end

	if cli_data and cli_data.type == 3 then
		return make.install()
	end

	make.manifest_file(cli_data, curr_cmd)
end

function make.manifest_file(cli_data, curr_cmd)
	make.l('INFO', 'Checking if ' .. make.manifest_file_dir .. ' exist')
	local is_exist = fs.existsSync(make.manifest_file_dir)
	if is_exist then
		make.l('INFO', make.manifest_file_dir .. ' exist, delete...')
		fs.unlinkSync(make.manifest_file_dir)
	end

	make.l('INFO', 'Making manifest file...')

  -- Get git data
  local gitobj = {
    branch = "git rev-parse --abbrev-ref HEAD",
    commit = "git rev-parse HEAD",
    commitTime = "git show -s --format=%ct HEAD",
  }

  for key, command in pairs(gitobj) do
    local openPop = assert(io.popen(command))
    local output = openPop:read('*all')
    openPop:close()
    gitobj[key] = output:sub(1, -2)
  end

  -- Get luvit data
  local runtimeObj = {}
  local openLuvit = assert(io.popen(
    process.env['GITHUB_BUILD'] and './luvit --version' or 'luvit --version'
  ))
	local outputLuvit = openLuvit:read('*all')
	openLuvit:close()
  outputLuvit = make.split(outputLuvit, '%a+ %a+: v?%d+.%d+.%d+')
  for _, data in pairs(outputLuvit) do
    data = make.split(data, '%S+')
    runtimeObj[data[1]] = data[3]
  end

  -- Build object
  local obj = {
    name = package_file.name,
    codename = package_file.codename,
    author = package_file.author,
    homepage = package_file.homepage,
    license = package_file.license,
    version = {
      major = "1",
      minor = "0",
      patch = "2",
      preRelease = "dev",
      semver = "1.0.2-dev",
      build = "",
    },
    runtime = runtimeObj,
    buildTime = os.time(),
    git = gitobj
  }

  make.l('INFO', 'Making manifest file complete')

	fs.writeFile(make.manifest_file_dir, json.encode(obj), function(err)
		make.build_project(err, cli_data, curr_cmd)
	end)
end

function make.build_project(err, cli_data, curr_cmd)
	if err then
		error(err)
	end
	make.l('INFO', 'Writting complete!')

	if cli_data.type == 2 then
		return make.l('INFO', 'Finished 💫')
	end

	make.l('INFO', 'Building project ...')

	local openPop = assert(io.popen(curr_cmd))
	local output = openPop:read('*all')
	openPop:close()

	print(output)

	make.l('INFO', 'Building complete!')
	make.l('INFO', 'Removing old builds...')
	fs.rmdirSync('./build')
	make.l('INFO', 'Apply new builds')
	local p_name = make.pname_output()
	fs.mkdirSync('./build')
	fs.renameSync('./' .. p_name, './build/' .. p_name)
	make.l('INFO', 'Finished 💫')
end

function make.doc()
	print('\n\nInvalid arg, choose only some mode below:\n')
	for name, data in pairs(make.args) do
		print(' - ' .. name .. ': ' .. data.desc)
	end
	print('')
	print('')
	os.exit()
end

function make.is_github()
	if process.env['GITHUB_BUILD'] then
		return true, './lit make'
	end
	if binary_format == 'dll' then
		return false, 'lit make'
	end
	return false, 'lit make'
end

function make.get_cli_data()
	local get_mode = process.argv[2]
	if not get_mode then
		get_mode = 'build'
	end
	local arg_mode = make.args[get_mode]
	if not arg_mode then
		return make.doc()
	end
	return arg_mode, get_mode
end

function make.l(type, msg)
	print(type .. ' - ' .. msg)
end

function make.pname_output()
	if binary_format == 'dll' then
		return package_file.name .. '.exe'
	end
	return package_file.name
end

function make.split(string, pattern)
	local t = {}
	for i in string.gmatch(string, pattern) do
		t[#t + 1] = i
	end
	return t
end

make.run()