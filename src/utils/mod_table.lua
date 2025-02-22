local function split(reqTable, start, endIndex)
  local result = {}
  local newIndex = 1
  for i = start, endIndex, 1 do
    table.insert(result, newIndex, reqTable[i])
    newIndex = newIndex + 1
  end
  return result
end

return { split = split }
