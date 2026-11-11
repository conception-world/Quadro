local process = require("@lune/process")

local specs = {
	require("./Geometry.spec"),
	require("./Store.spec"),
	require("./Strings.spec"),
	require("./Settings.spec"),
	require("./Registry.spec"),
	require("./Notify.spec"),
	require("./Codec.spec"),
	require("./Catalog.spec"),
	require("./Spec.spec"),
	require("./Units.spec"),
	require("./Fonts.spec"),
	require("./Plan.spec"),
	require("./Templates.spec"),
	require("./Bridge.spec"),
	require("./Runtime.spec"),
	require("./Stops.spec"),
	require("./EffectPresets.spec"),
	require("./BuilderMath.spec"),
	require("./LibraryData.spec"),
	require("./ColorMath.spec"),
	require("./StudioTests.spec"),
}

local passed, failed = 0, 0
local t = {}

function t.case(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

function t.eq(actual: any, expected: any)
	if actual ~= expected then
		error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

function t.near(actual: number, expected: number, eps: number?)
	if math.abs(actual - expected) > (eps or 1e-4) then
		error(string.format("expected ~%s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

for _, spec in specs do
	spec(t)
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
