local LibraryData = require("../src/LibraryData")

local GRADIENT = {
	name = "Sunset",
	rotation = 90,
	offset = { 0, 0 },
	color = { { t = 0, c = "ff0000", a = 0 }, { t = 1, c = "0000ff", a = 0 } },
	transparency = { { 0, 0 }, { 1, 0 } },
}

return function(t)
	t.case("cleanName folds accents, joins words and is idempotent", function()
		t.eq(LibraryData.cleanName("  Botão Primário "), "Botao_Primario")
		t.eq(LibraryData.cleanName("a  b!!c"), "a_b_c")
		t.eq(LibraryData.cleanName("Card-2"), "Card-2")
		t.eq(LibraryData.cleanName("__x__"), "x")
		t.eq(LibraryData.cleanName("日本"), nil)
		t.eq(LibraryData.cleanName(""), nil)
		t.eq(LibraryData.cleanName(42), nil)
		local long = LibraryData.cleanName(string.rep("ab_", 40))
		t.eq(#long <= LibraryData.MAX_NAME, true)
		t.eq(LibraryData.cleanName(long), long)
	end)
	t.case("keys round-trip and reject unknown kinds or dirty names", function()
		local kind, name = LibraryData.parseKey(LibraryData.key("color", "Primary_Blue"))
		t.eq(kind, "color")
		t.eq(name, "Primary_Blue")
		t.eq(LibraryData.parseKey("shadow_Big"), nil)
		t.eq(LibraryData.parseKey("color_a b"), nil)
		t.eq(LibraryData.parseKey("color"), nil)
	end)
	t.case("color tokens are lowercase hex", function()
		t.eq(LibraryData.sanitize("color", "#FF8800"), "ff8800")
		t.eq(LibraryData.sanitize("color", "ff880"), nil)
		t.eq(LibraryData.sanitize("color", { 1, 2, 3 }), nil)
	end)
	t.case("size tokens are UDim or UDim2 parts", function()
		local udim2 = LibraryData.sanitize("size", { 0.5, 10, 0, 40 })
		t.eq(#udim2, 4)
		t.eq(udim2[2], 10)
		t.eq(#LibraryData.sanitize("size", { 0, 8 }), 2)
		t.eq(LibraryData.sanitize("size", { 0, 8, 1 }), nil)
		t.eq(LibraryData.sanitize("size", { 0, 0 / 0 }), nil)
		t.eq(LibraryData.sanitize("size", { 0, "8" }), nil)
	end)
	t.case("font tokens carry family, weight and style", function()
		local font = LibraryData.sanitize("font", { family = "rbxasset://fonts/families/GothamSSm.json", weight = "Bold", style = "Italic", extra = 1 })
		t.eq(font.weight, "Bold")
		t.eq(font.style, "Italic")
		t.eq(font.extra, nil)
		t.eq(LibraryData.sanitize("font", { family = "", weight = "Bold", style = "Normal" }), nil)
		t.eq(LibraryData.sanitize("font", { family = "x", weight = "Bold 2", style = "Normal" }), nil)
	end)
	t.case("gradient tokens reuse the gradient codec", function()
		local data = LibraryData.sanitize("gradient", GRADIENT)
		t.eq(data.rotation, 90)
		t.eq(data.color[2].c, "0000ff")
		t.eq(LibraryData.sanitize("gradient", { rotation = 0 }), nil)
	end)
	t.case("merge lists both scopes and the place wins", function()
		local items = LibraryData.merge({ color_B = "111111", color_A = "222222" }, { color_A = "333333", color_C = "444444" })
		t.eq(#items, 3)
		t.eq(items[1].key, "color_A")
		t.eq(items[1].scope, "place")
		t.eq(items[1].value, "222222")
		t.eq(items[1].shared, true)
		t.eq(items[2].scope, "place")
		t.eq(items[2].shared, false)
		t.eq(items[3].key, "color_C")
		t.eq(items[3].scope, "global")
	end)
	t.case("sanitizeGlobal drops bad entries and enforces the caps", function()
		local big = string.rep("A", LibraryData.MAX_COMPONENT_BYTES + 1)
		local out = LibraryData.sanitizeGlobal({
			tokens = { color_Ok = "#00FF00", color_Bad = "nope", wat_X = "ffffff", ["color_a b"] = "ffffff" },
			components = { Card = "QUJD", Huge = big, Junk = "not base64!", ["Bad Name"] = "QUJD" },
		})
		t.eq(out.tokens.color_Ok, "00ff00")
		t.eq(LibraryData.count(out.tokens), 1)
		t.eq(out.components.Card, "QUJD")
		t.eq(LibraryData.count(out.components), 1)
		local many = {}
		for index = 1, LibraryData.MAX_COMPONENTS + 5 do
			many["C" .. index] = "QUJD"
		end
		t.eq(LibraryData.count(LibraryData.sanitizeGlobal({ components = many }).components), LibraryData.MAX_COMPONENTS)
		t.eq(LibraryData.count(LibraryData.sanitizeGlobal("junk").tokens), 0)
	end)
	t.case("component size cap is exact", function()
		t.eq(LibraryData.validComponent("Card", string.rep("A", LibraryData.MAX_COMPONENT_BYTES)), true)
		t.eq(LibraryData.validComponent("Card", string.rep("A", LibraryData.MAX_COMPONENT_BYTES + 1)), false)
	end)
	t.case("freeName keeps free names and suffixes taken ones", function()
		local taken = { Card = true, ["Card-2"] = true }
		local function isTaken(name)
			return taken[name] == true
		end
		t.eq(LibraryData.freeName("Panel", isTaken), "Panel")
		t.eq(LibraryData.freeName("Card", isTaken), "Card-3")
		local long = string.rep("a", LibraryData.MAX_NAME)
		local free = LibraryData.freeName(long, function(name)
			return name == long
		end)
		t.eq(#free <= LibraryData.MAX_NAME, true)
		t.eq(LibraryData.cleanName(free), free)
	end)
	t.case("remove needs a second click on the same item within the window", function()
		t.eq(LibraryData.confirms(nil, "token:place:color_A", 10), false)
		local pending = { id = "token:place:color_A", at = 10 }
		t.eq(LibraryData.confirms(pending, "token:place:color_A", 12.9), true)
		t.eq(LibraryData.confirms(pending, "token:place:color_B", 11), false)
		t.eq(LibraryData.confirms(pending, "token:place:color_A", 13.5), false)
	end)
end
