--!strict
local Spec = require("./Spec")

local Plan = {}

export type Existing = { [string]: { name: string, parentId: string?, foreign: boolean } }
export type Result = {
	create: { string }, update: { string }, remove: { string }, orphan: { string },
	renamed: { { id: string, from: string, to: string } },
}

function Plan.diff(doc: any, existing: Existing): Result
	local result: Result = { create = {}, update = {}, remove = {}, orphan = {}, renamed = {} }
	local seen: { [string]: boolean } = {}

	local function walk(node: any)
		if node.kind == "ignore" or (node ~= doc.root and Spec.isSource(node)) then
			return
		end
		seen[node.id] = true
		local old = existing[node.id]
		if old then
			table.insert(result.update, node.id)
			if old.name ~= node.name then
				table.insert(result.renamed, { id = node.id, from = old.name, to = node.name })
			end
		else
			table.insert(result.create, node.id)
		end
		for _, child in node.children do
			walk(child)
		end
	end
	walk(doc.root)

	local gone = {}
	for id in existing do
		if not seen[id] then
			table.insert(gone, id)
		end
	end
	table.sort(gone)
	for _, id in gone do
		table.insert(if existing[id].foreign then result.orphan else result.remove, id)
	end
	return result
end

return Plan
