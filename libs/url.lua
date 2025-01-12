function Encode(url)
	if url == nil then return end
	url = url:gsub("\n", "\r\n")
	url = url:gsub("([^%w ])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	url = url:gsub(" ", "+")
	return url
end

function Decode(url)
	if url == nil then return end
	url = url:gsub("+", " ")
	url = url:gsub("%%(%x%x)", function(x)
		return string.char(tonumber(x, 16))
	end)
	return url
end

return {
	decode = Decode,
	encode = Encode
}