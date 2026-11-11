--!strict
local Catalog = {}

Catalog.SELECTION_IDS = {
	"transform.posScale",
	"transform.posOffset",
	"transform.sizeScale",
	"transform.sizeOffset",
	"constraint.aspect",
	"text.scale",
	"layout.group",
	"layout.groupButton",
	"layout.groupEach",
	"layout.ungroup",
	"layout.fit",
	"layout.expand",
}

Catalog.NEEDS_ARGUMENTS = {
	["anchor.set"] = true,
	["convert.to"] = true,
	["gradient.apply"] = true,
	["gradient.rename"] = true,
	["gradient.delete"] = true,
	["gradient.select"] = true,
	["gradient.edit"] = true,
	["effect.nineSlice"] = true,
	["layout.align"] = true,
	["import.spec"] = true,
	["stroke.convert"] = true,
	["corner.convert"] = true,
	["padding.convert"] = true,
	["responsive.clamp"] = true,
	["library.saveToken"] = true,
	["library.applyToken"] = true,
	["library.removeToken"] = true,
	["library.copyToken"] = true,
	["library.setTokenColor"] = true,
	["library.insertComponent"] = true,
	["library.removeComponent"] = true,
	["library.copyComponent"] = true,
}

Catalog.IGNORED_KEYS = {
	Unknown = true,
	LeftShift = true,
	RightShift = true,
	LeftControl = true,
	RightControl = true,
	LeftAlt = true,
	RightAlt = true,
	LeftSuper = true,
	RightSuper = true,
}

function Catalog.capturable(keyName: string): boolean
	return not Catalog.IGNORED_KEYS[keyName]
end

function Catalog.assignShortcut(shortcuts: { [string]: string }, id: string, key: string?): { [string]: string }
	local out = table.clone(shortcuts)
	local previous = out[id]
	out[id] = nil
	if key == nil then
		return out
	end
	for otherId, otherKey in out do
		if otherKey == key then
			out[otherId] = previous
		end
	end
	out[id] = key
	return out
end

return Catalog
