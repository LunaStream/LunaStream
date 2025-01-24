-- Patch table library
table.filter = function(t, func)
	local out = {}
	for k, v in pairs(t) do
		if func(v, k, t) then
			table.insert(out, v)
		end
	end
	return out
end

table.includes = function(t, e)
	for _, value in pairs(t) do
		if value == e then
			return e
		end
	end
	return nil
end

table.reduce = function(tbl, func, initial)
	local accumulator = initial
	for _, value in ipairs(tbl) do
		accumulator = func(accumulator, value)
	end
	return accumulator
end

table.length = function (T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

table.map = function (tbl, func)
    local result = {}
    for i, v in ipairs(tbl) do
        result[i] = func(v, i, tbl)  -- Apply the function to each element
    end
    return result
end

table.slice = function(t, first, last)
  local sliced = {}
  for i = first, last do
    sliced[#sliced+1] = t[i]
  end
  return sliced
end

table.some = function (tbl, condition)
  for _, value in ipairs(tbl) do
    if condition(value) then
      return true
    end
  end
  return false
end

-- Define a function similar to Array.find in JavaScript
table.find = function (arr, condition)
  for _, element in ipairs(arr) do
    if condition(element) then
      return element
    end
  end
  return nil
end

table.unpack = table.unpack or unpack

-- Patch string library
string.split = function(string, pattern)
	local t = {}
	for i in string.gmatch(string, pattern) do
		t[#t + 1] = i
	end
	return t
end
