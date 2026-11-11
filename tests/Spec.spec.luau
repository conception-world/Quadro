local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Spec = require("../src/Import/Spec")

local function doc(root)
	return { version = 1, source = { name = "T" }, root = root, images = {}, tokens = { gradients = {} } }
end

return function(t)
	t.case("parses a minimal doc and fills defaults", function()
		local d, errors = Spec.parse(doc({ id = "1:1", name = "Root", kind = "frame", box = { 0, 0, 1920, 1080 } }))
		t.eq(#errors, 0)
		t.eq(d.root.opacity, 1)
		t.eq(d.root.visible, true)
		t.eq(#d.root.children, 0)
		t.eq(#d.warnings, 0)
	end)
	t.case("absolute flag defaults to false and survives parsing", function()
		local d, errors = Spec.parse(doc({
			id = "1:1", name = "R", kind = "list", box = { 0, 0, 100, 100 },
			layout = { dir = "V", gap = 0, padding = { 0, 0, 0, 0 }, align = { "MIN", "MIN" }, wrap = false },
			children = {
				{ id = "1:2", name = "Flow", kind = "frame", box = { 0, 0, 10, 10 } },
				{ id = "1:3", name = "Free", kind = "frame", box = { -5, 0, 10, 10 }, absolute = true },
				{ id = "1:4", name = "Odd", kind = "frame", box = { 0, 0, 10, 10 }, absolute = "yes" },
			},
		}))
		t.eq(#errors, 0)
		t.eq(d.root.absolute, false)
		t.eq(d.root.children[1].absolute, false)
		t.eq(d.root.children[2].absolute, true)
		t.eq(d.root.children[3].absolute, false)
	end)
	t.case("tint is optional, normalized to lowercase hex and validated", function()
		local d, errors = Spec.parse(doc({
			id = "1:1", name = "R", kind = "frame", box = { 0, 0, 100, 100 },
			children = {
				{ id = "1:2", name = "Plain", kind = "frame", box = { 0, 0, 10, 10 } },
				{ id = "1:3", name = "Tinted", kind = "frame", box = { 0, 0, 10, 10 }, tint = "8EE04A" },
			},
		}))
		t.eq(#errors, 0)
		t.eq(d.root.children[1].tint, nil)
		t.eq(d.root.children[2].tint, "8ee04a")
		local _, bad = Spec.parse(doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 }, tint = "lime" }))
		t.eq(#bad, 1)
		t.eq(bad[1], "bad hex on 1:1")
	end)
	t.case("rejects a newer version", function()
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		raw.version = 2
		local d, errors = Spec.parse(raw)
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("rejects an unknown kind", function()
		local d, errors = Spec.parse(doc({ id = "1:1", name = "R", kind = "blob", box = { 0, 0, 10, 10 } }))
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("normalizes fills", function()
		local d = Spec.parse(doc({
			id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 },
			fill = {
				{ solid = "FF0000", a = 0.5 },
				{ linear = { rotation = 90, stops = { { 0, "00FF00" }, { 1, "0000ff", 0.2 } } } },
				{ image = "abc", scale = "fit" },
				{ token = "Confirmation" },
			},
		}))
		local f = d.root.fills
		t.eq(f[1].kind, "solid")
		t.eq(f[1].hex, "ff0000")
		t.eq(f[1].a, 0.5)
		t.eq(f[2].kind, "linear")
		t.eq(f[2].stops[1].hex, "00ff00")
		t.eq(f[2].stops[1].a, 1)
		t.eq(f[3].kind, "image")
		t.eq(f[3].tile, nil)
		t.eq(f[4].name, "Confirmation")
	end)
	t.case("keeps the tile size of a tiled image fill and drops a malformed one", function()
		local d, errors = Spec.parse(doc({
			id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 },
			children = {
				{ id = "1:2", name = "Grain", kind = "image", box = { 0, 0, 10, 10 }, fill = { { image = "abc", scale = "tile", tile = { 128, 32 } } } },
				{ id = "1:3", name = "Bad", kind = "image", box = { 0, 0, 10, 10 }, fill = { { image = "abc", scale = "tile", tile = { 0, "x" } } } },
			},
		}))
		t.eq(#errors, 0)
		local grain = d.root.children[1].fills[1]
		t.eq(grain.scale, "tile")
		t.eq(grain.tile[1], 128)
		t.eq(grain.tile[2], 32)
		t.eq(d.root.children[2].fills[1].tile, nil)
		t.eq(#d.warnings, 1)
		t.eq(d.warnings[1], "tile on 1:3 dropped: invalid size")
	end)
	t.case("expands a single radius to four corners", function()
		local d = Spec.parse(doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 }, radius = 4 }))
		t.eq(#d.root.radius, 4)
		t.eq(d.root.radius[3], 4)
	end)
	t.case("truncates gradients above 20 stops with a warning", function()
		local stops = {}
		for i = 0, 24 do
			table.insert(stops, { i / 24, "ffffff" })
		end
		local d = Spec.parse(doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 }, fill = { { linear = { rotation = 0, stops = stops } } } }))
		t.eq(#d.root.fills[1].stops, 20)
		t.eq(#d.warnings, 1)
	end)

	local function leaf(extra)
		local n = { id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } }
		for k, v in extra do
			n[k] = v
		end
		return n
	end

	t.case("string fill is an error, not a throw", function()
		local d, errors = Spec.parse(doc(leaf({ fill = "red" })))
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("string children is an error", function()
		local d, errors = Spec.parse(doc(leaf({ children = "x" })))
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("NaN in box is an error", function()
		local d, errors = Spec.parse(doc(leaf({ box = { 0, 0, 0 / 0, 10 } })))
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("negative width is an error", function()
		local d = Spec.parse(doc(leaf({ box = { 0, 0, -1, 10 } })))
		t.eq(d, nil)
	end)
	t.case("5001 nodes is an error", function()
		local kids = {}
		for i = 1, 5000 do
			table.insert(kids, { id = "k" .. i, name = "k", kind = "frame", box = { 0, 0, 1, 1 } })
		end
		local d, errors = Spec.parse(doc(leaf({ children = kids })))
		t.eq(d, nil)
		t.eq(#errors > 0, true)
	end)
	t.case("duplicate id is an error", function()
		local d, errors = Spec.parse(doc(leaf({ children = { leaf({}) } })))
		t.eq(d, nil)
		t.eq(errors[1], "duplicate id 1:1")
	end)
	t.case("opacity is clamped", function()
		local d = Spec.parse(doc(leaf({ opacity = 3 })))
		t.eq(d.root.opacity, 1)
	end)
	t.case("radius with two entries is an error", function()
		local d = Spec.parse(doc(leaf({ radius = { 1, 2 } })))
		t.eq(d, nil)
	end)
	t.case("stroke is flattened", function()
		local d = Spec.parse(doc(leaf({ stroke = { paint = { solid = "00FF00", a = 0.5 }, weight = 2, align = "O" } })))
		local s = d.root.stroke
		t.eq(s.hex, "00ff00")
		t.eq(s.a, 0.5)
		t.eq(s.weight, 2)
		t.eq(s.align, "O")
	end)
	t.case("drop shadow is flattened", function()
		local d = Spec.parse(doc(leaf({ effects = { { dropShadow = { color = "000000", a = 0.3, x = 0, y = 4, blur = 8, spread = 1 } }, { blur = 6 }, { weird = 1 } } })))
		local e = d.root.effects
		t.eq(#e, 2)
		t.eq(e[1].kind, "dropShadow")
		t.eq(e[1].hex, "000000")
		t.eq(e[1].y, 4)
		t.eq(e[2].kind, "blur")
		t.eq(e[2].blur, 6)
		t.eq(#d.warnings, 1)
	end)
	t.case("text is flattened with defaults", function()
		local d = Spec.parse(doc(leaf({
			kind = "text",
			text = { chars = "Hi", font = { family = "Inter", weight = 700 }, size = 20, color = "FF0000" },
		})))
		local x = d.root.text
		t.eq(x.family, "Inter")
		t.eq(x.weight, 700)
		t.eq(x.italic, false)
		t.eq(x.hex, "ff0000")
		t.eq(x.a, 1)
		t.eq(x.align[1], "LEFT")
		t.eq(x.align[2], "CENTER")
	end)
	t.case("linear fill with one stop is dropped with a warning", function()
		local d = Spec.parse(doc(leaf({ fill = { { linear = { rotation = 0, stops = { { 0, "ffffff" } } } } } })))
		t.eq(#d.root.fills, 0)
		t.eq(#d.warnings, 1)
	end)
	t.case("merges source warnings before its own and caps them", function()
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 }, fill = { { linear = { rotation = 0, stops = { { 0, "ffffff" } } } } } })
		raw.warnings = { "from exporter", 5, string.rep("x", 500) }
		local d = Spec.parse(raw)
		t.eq(#d.warnings, 3)
		t.eq(d.warnings[1], "from exporter")
		t.eq(#d.warnings[2], 200)
		local many = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		many.warnings = {}
		for i = 1, 150 do
			table.insert(many.warnings, "w" .. i)
		end
		t.eq(#Spec.parse(many).warnings, 100)
	end)
	t.case("parses the exporter sample and carries its warnings", function()
		local raw = serde.decode("json", fs.readFile("tests/fixtures/exporter-sample.json"))
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		t.eq(d ~= nil, true)
		local joined = table.concat(d.warnings, "|")
		t.eq(string.find(joined, "Card: inner shadow dropped (container)", 1, true) ~= nil, true)
		t.eq(string.find(joined, "Rich: mixed text styles, using the first", 1, true) ~= nil, true)
		t.eq(d.root.children[4].kind, "list")
		t.eq(d.root.children[5].kind, "scroll")
		local function hasKind(node: any, kind: string): boolean
			if node.kind == kind then
				return true
			end
			for _, child in node.children do
				if hasKind(child, kind) then
					return true
				end
			end
			return false
		end
		t.eq(hasKind(d.root, "template"), true)
	end)
	t.case("gradient tokens are normalized and bad ones are dropped without failing", function()
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		raw.tokens = { gradients = {
			Good = { rotation = 90, stops = { { 1, "0000FF", 0.5 }, { 0, "FF0000" } } },
			Short = { rotation = 0, stops = { { 0, "ffffff" } } },
			Broken = "nope",
			BadHex = { rotation = 0, stops = { { 0, "zz" }, { 1, "ffffff" } } },
		} }
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		local good = d.tokens.gradients.Good
		t.eq(good.stops[1].hex, "ff0000")
		t.eq(good.stops[2].hex, "0000ff")
		t.eq(good.stops[2].a, 0.5)
		t.eq(d.tokens.gradients.Short, nil)
		t.eq(d.tokens.gradients.Broken, nil)
		t.eq(d.tokens.gradients.BadHex, nil)
		t.eq(#d.warnings >= 3, true)
	end)
	t.case("gradient tokens cap stops", function()
		local stops = {}
		for i = 0, 24 do
			table.insert(stops, { i / 24, "ffffff" })
		end
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		raw.tokens = { gradients = { Many = { rotation = 0, stops = stops } } }
		t.eq(#Spec.parse(raw).tokens.gradients.Many.stops, Spec.MAX_STOPS)
	end)
	t.case("image entries with a non-positive size are dropped with a warning", function()
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		raw.images = { zero = { w = 0, h = 10 }, ok = { w = 4, h = 4 } }
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		t.eq(d.images.zero, nil)
		t.eq(d.images.ok.w, 4)
		t.eq(#d.warnings, 1)
	end)
	t.case("exporter sample keeps token stop alpha end to end", function()
		local raw = serde.decode("json", fs.readFile("tests/fixtures/exporter-sample.json"))
		local d = Spec.parse(raw)
		t.eq(d.tokens.gradients.Neon.stops[1].a, 0.25)
		t.eq(d.tokens.gradients.Neon.stops[2].a, 1)
	end)
	t.case("failed image entries become import warnings", function()
		local raw = doc({ id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 } })
		raw.images = { [string.rep("ab", 32)] = { w = 4, h = 4, asset = "failed", error = "HTTP 400: bad" } }
		local d = Spec.parse(raw)
		t.eq(d.warnings[1], "abababab: falha no envio (HTTP 400: bad)")
	end)
	t.case("a main component root warns and isSource ignores nothing else", function()
		local root = { id = "1:1", name = "Btn", kind = "frame", box = { 0, 0, 10, 10 }, component = { key = "k", name = "Btn", variant = {}, main = true } }
		local d = Spec.parse(doc(root))
		t.eq(d.warnings[1], "Btn: componente principal na raiz é construído como tela, não como template")
		t.eq(Spec.isSource(d.root), true)
		t.eq(Spec.isSource({ name = "__Components", children = {} } :: any), true)
	end)
	t.case("an image fill with an asset id uses that id directly", function()
		local hash = string.rep("cd", 32)
		local raw = doc({
			id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 },
			children = {
				{ id = "1:2", name = "Bag", kind = "image", box = { 0, 0, 10, 10 }, fill = { { asset = "rbxassetid://123", scale = "fit" } } },
				{ id = "1:3", name = "Both", kind = "image", box = { 0, 0, 10, 10 }, fill = { { image = hash, asset = "rbxassetid://456" } } },
				{ id = "1:4", name = "Pack", kind = "image", box = { 0, 0, 10, 10 }, fill = { { image = hash } } },
			},
		})
		raw.images = { [hash] = { w = 4, h = 4, asset = "rbxassetid://9" } }
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		t.eq(#d.warnings, 0)
		local bag = d.root.children[1].fills[1]
		t.eq(bag.kind, "image")
		t.eq(bag.asset, "rbxassetid://123")
		t.eq(bag.hash, nil)
		t.eq(bag.scale, "fit")
		t.eq(Spec.imageId(d, bag), "rbxassetid://123")
		t.eq(Spec.imageId(d, d.root.children[2].fills[1]), "rbxassetid://456")
		t.eq(Spec.imageId(d, d.root.children[3].fills[1]), "rbxassetid://9")
	end)
	t.case("a malformed asset id warns and falls back to the image hash", function()
		local hash = string.rep("ef", 32)
		local raw = doc({
			id = "1:1", name = "R", kind = "frame", box = { 0, 0, 10, 10 },
			children = {
				{ id = "1:2", name = "Decal", kind = "image", box = { 0, 0, 10, 10 }, fill = { { image = hash, asset = "decal:5" } } },
				{ id = "1:3", name = "Lone", kind = "image", box = { 0, 0, 10, 10 }, fill = { { asset = 42 } } },
			},
		})
		raw.images = { [hash] = { w = 4, h = 4, asset = "pending" } }
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		local decal = d.root.children[1].fills[1]
		t.eq(decal.asset, nil)
		t.eq(decal.hash, hash)
		t.eq(Spec.imageId(d, decal), nil)
		t.eq(#d.root.children[2].fills, 0)
		t.eq(d.warnings[1], "asset on 1:2 ignored: expected rbxassetid://<number>")
		t.eq(d.warnings[2], "asset on 1:3 ignored: expected rbxassetid://<number>")
	end)
end
