local fs = require('fs')
local path = require('path')

local config_file = 'format.yml'

local function load_dir(dir)
	local files, err = fs.readdirSync(dir)
	if err then
		error(err)
	end
	return files
end

local function readdir_recursive(dir)
	local results = {}
	local dir_list = path.join(table.unpack(dir))
	local files = load_dir(dir_list)

	table.foreach(files, function(_, name)
		local small_dir = path.join(dir_list, name)
		local dir_locate_status, err = fs.lstatSync(small_dir)
		if err then
			error(err)
		end
		if dir_locate_status.type ~= 'directory' then
			if string.match(small_dir, '(.+)%.lua') then
				table.insert(results, small_dir)
			end
		else
			local another_time = readdir_recursive({ dir_list, name })
			table.foreach(another_time, function(_, value)
				if string.match(value, '(.+)%.lua') then
					table.insert(results, value)
				end
			end)
		end
	end)

	return results
end

local dir_list = readdir_recursive({ '.', 'src' })

for _, value in pairs(readdir_recursive({ '.', 'libs' })) do
	table.insert(dir_list, value)
end

for _, value in pairs(dir_list) do
	local curr_cmd = string.format('lua-format %s -c %s', value, config_file)
	local openPop = assert(io.popen(curr_cmd))
	local output = openPop:read('*all')
	openPop:close()
	fs.writeFileSync(value, output)
	print('[LunaStream Formatter]: Formatted ' .. value)
end