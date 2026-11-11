local Spec = require("../src/Import/Spec")
local Templates = require("../src/Import/Templates")

local function component(id, state, main)
	return {
		id = id, name = "State=" .. state, kind = "frame", box = { 0, 0, 10, 10 },
		component = { key = "k" .. id, name = "Btn", variant = { State = state }, main = main },
	}
end

return function(t)
	t.case("collect groups variants by component name", function()
		local doc = Spec.parse({
			version = 1, source = {}, images = {}, tokens = { gradients = {} },
			root = {
				id = "1", name = "S", kind = "frame", box = { 0, 0, 100, 100 },
				children = { {
					id = "2", name = "__Components", kind = "frame", box = { 0, 0, 10, 10 },
					children = { component("3", "Hover", true), component("4", "Normal", true) },
				}, component("5", "Normal", false) },
			},
		})
		local groups = Templates.collect(doc.root, {})
		t.eq(#groups, 1)
		t.eq(groups[1].normal.id, "4")
		t.eq(groups[1].key, "k4")
		t.eq(groups[1].states.Hover.id, "3")
	end)
	t.case("attribute names are legal and keep the path", function()
		t.eq(Templates.attributeName({}, "Size"), ".Size")
		t.eq(Templates.attributeName({ Templates.segment("Body", 1), Templates.segment("Label 1", 1) }, "TextColor3"), "Body/Label_1.TextColor3")
		t.eq(Templates.segment("Dot", 2), "Dot-2")
	end)
	t.case("collect warns for a main component outside __Components", function()
		local doc = Spec.parse({
			version = 1, source = {}, images = {}, tokens = { gradients = {} },
			root = {
				id = "1", name = "S", kind = "frame", box = { 0, 0, 100, 100 },
				children = { component("3", "Normal", true), {
					id = "2", name = "__Components", kind = "frame", box = { 0, 0, 10, 10 },
					children = { component("4", "Hover", true) },
				} },
			},
		})
		local warnings = {}
		Templates.collect(doc.root, warnings)
		t.eq(#warnings, 1)
		t.eq(warnings[1], "State=Normal: componente principal fora de __Components só vira template")
	end)
	t.case("collect never treats the root as a source", function()
		local doc = Spec.parse({
			version = 1, source = {}, images = {}, tokens = { gradients = {} },
			root = {
				id = "1", name = "S", kind = "frame", box = { 0, 0, 100, 100 },
				component = { key = "kr", name = "Screen", variant = {}, main = true },
				children = { component("3", "Normal", true) },
			},
		})
		local groups = Templates.collect(doc.root, {})
		t.eq(#groups, 1)
		t.eq(groups[1].name, "Btn")
	end)
end
