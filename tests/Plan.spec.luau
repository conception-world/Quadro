local Spec = require("../src/Import/Spec")
local Plan = require("../src/Import/Plan")

local function build()
	return Spec.parse({
		version = 1,
		source = {},
		root = {
			id = "1", name = "Screen", kind = "frame", box = { 0, 0, 100, 100 },
			children = {
				{ id = "2", name = "Card", kind = "frame", box = { 0, 0, 10, 10 } },
				{ id = "3", name = "NewThing", kind = "frame", box = { 0, 0, 10, 10 } },
				{ id = "9", name = "Decor", kind = "ignore", box = { 0, 0, 10, 10 } },
			},
		},
		images = {},
		tokens = { gradients = {} },
	})
end

local function has(list, id)
	return table.find(list, id) ~= nil
end

return function(t)
	t.case("classifies create, update, remove and orphan", function()
		local existing = {
			["1"] = { name = "Screen", parentId = nil, foreign = false },
			["2"] = { name = "OldCard", parentId = "1", foreign = false },
			["4"] = { name = "Gone", parentId = "1", foreign = false },
			["5"] = { name = "GoneWithScript", parentId = "1", foreign = true },
		}
		local p = Plan.diff(build(), existing)
		t.eq(has(p.update, "1"), true)
		t.eq(has(p.update, "2"), true)
		t.eq(has(p.create, "3"), true)
		t.eq(has(p.remove, "4"), true)
		t.eq(has(p.orphan, "5"), true)
		t.eq(has(p.create, "9"), false)
		t.eq(#p.renamed, 1)
		t.eq(p.renamed[1].to, "Card")
	end)
	t.case("first import creates everything but ignored nodes", function()
		local p = Plan.diff(build(), {})
		t.eq(#p.create, 3)
		t.eq(#p.update + #p.remove + #p.orphan, 0)
	end)
	t.case("the root is never treated as a template source", function()
		local doc = Spec.parse({
			version = 1, source = {}, images = {}, tokens = { gradients = {} },
			root = {
				id = "1", name = "Screen", kind = "frame", box = { 0, 0, 100, 100 },
				component = { key = "k", name = "Screen", variant = {}, main = true },
				children = { { id = "2", name = "Card", kind = "frame", box = { 0, 0, 10, 10 } } },
			},
		})
		local p = Plan.diff(doc, {})
		t.eq(has(p.create, "1"), true)
		t.eq(has(p.create, "2"), true)
	end)
end
