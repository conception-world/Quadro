local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SUMMARY = 'string.format("%d PASS, %d FAIL"'

return function(t)
	if not fs.isDir("studio-tests") then
		return
	end
	for _, name in fs.readDir("studio-tests") do
		if string.sub(name, -5) == ".luau" then
			t.case("studio test " .. name .. " compiles and reports compactly", function()
				local source = fs.readFile("studio-tests/" .. name)
				local compiled, problem = pcall(luau.compile, source)
				if not compiled then
					error(tostring(problem))
				end
				t.eq(string.find(source, SUMMARY, 1, true) ~= nil, true)
			end)
		end
	end
end
