return function(numLetters)
  local alphabet = "abcdefghijklmnopqrstuvwxyz"
  local letters = {}
  for letter in alphabet:gmatch(".") do
    table.insert(letters, letter)
  end

  math.randomseed(os.time())
  for i = #letters, 2, -1 do
    local j = math.random(i)
    letters[i], letters[j] = letters[j], letters[i]
  end

  local result = {}
  for i = 1, numLetters do
    table.insert(result, letters[i])
  end

  return table.concat(result)
end
