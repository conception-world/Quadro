--!strict
local Installer = require("../Runtime/Installer")
local Spec = require("./Spec")

local Templates = {}

export type Group = { name: string, key: string, normal: Spec.Node, states: { [string]: Spec.Node } }

local GUI_PROPERTIES = { "BackgroundColor3", "BackgroundTransparency", "TextColor3", "ImageColor3", "Size" }
local MODIFIER_PROPERTIES: { [string]: string } = { UIGradient = "Color", UIStroke = "Color" }

function Templates.segment(name: string, occurrence: number): string
	local clean = string.gsub(name, "[^%w_]", "_")
	return if occurrence > 1 then clean .. "-" .. occurrence else clean
end

function Templates.attributeName(path: { string }, property: string): string
	return table.concat(path, "/") .. "." .. property
end

local function stateOf(node: Spec.Node): string?
	return (node.component :: any).variant.State
end

function Templates.collect(root: Spec.Node, warnings: { string }): { Group }
	local byName: { [string]: { Spec.Node } } = {}
	local function walk(node: Spec.Node, inPage: boolean)
		if node.kind == "ignore" then
			return
		end
		local component = node.component
		if component and component.main then
			if not inPage then
				table.insert(warnings, node.name .. ": componente principal fora de __Components só vira template")
			end
			local list = byName[component.name]
			if list == nil then
				list = {}
				byName[component.name] = list
			end
			table.insert(list :: { Spec.Node }, node)
			return
		end
		for _, child in node.children do
			walk(child, inPage or node.name == Spec.COMPONENTS_PAGE)
		end
	end
	for _, child in root.children do
		walk(child, false)
	end
	local names: { string } = {}
	for name in byName do
		table.insert(names, name)
	end
	table.sort(names)
	local groups: { Group } = {}
	for _, name in names do
		local list = byName[name]
		local normal = list[1]
		local normals = 0
		for _, candidate in list do
			local variant = (candidate.component :: any).variant
			local properties: { string } = {}
			for property in variant do
				table.insert(properties, property)
			end
			if #properties > 1 then
				table.sort(properties)
				table.insert(warnings, name .. ": variant has several properties (" .. table.concat(properties, ", ") .. "), only State is used")
			end
			local state = stateOf(candidate)
			if state == nil or state == "Normal" then
				normals += 1
				if normals == 1 then
					normal = candidate
				end
			end
		end
		if normals > 1 then
			table.insert(warnings, name .. ": several Normal variants, using the first")
		end
		local states: { [string]: Spec.Node } = {}
		for _, candidate in list do
			local state = stateOf(candidate)
			if candidate ~= normal and state ~= nil and state ~= "Normal" then
				if states[state] then
					table.insert(warnings, name .. ": duplicate State " .. state .. ", using the first")
				else
					states[state] = candidate
				end
			end
		end
		table.insert(groups, { name = name, key = (normal.component :: any).key, normal = normal, states = states })
	end
	return groups
end

local function read(instance: Instance, property: string): (boolean, any)
	return pcall(function()
		return (instance :: any)[property]
	end)
end

local function same(a: any, b: any): boolean
	if typeof(a) == "ColorSequence" then
		return tostring(a) == tostring(b)
	end
	return a == b
end

type Entry = { instance: Instance, clean: string, occurrence: number }

local function entries(parent: Instance): { Entry }
	local seen: { [string]: number } = {}
	local list: { Entry } = {}
	for _, child in parent:GetChildren() do
		local clean = string.gsub(child.Name, "[^%w_]", "_")
		local occurrence = (seen[clean] or 0) + 1
		seen[clean] = occurrence
		table.insert(list, { instance = child, clean = clean, occurrence = occurrence })
	end
	return list
end

local function counterpart(list: { Entry }, entry: Entry): Instance?
	for _, candidate in list do
		if candidate.clean == entry.clean and candidate.occurrence == entry.occurrence then
			return candidate.instance
		end
	end
	return nil
end

local function ratioOf(a: number, b: number): number
	return if a ~= 0 then b / a else 1
end

local function compare(base: Instance, variant: Instance, path: { string }, property: string, out: { [string]: any })
	local okBase, a = read(base, property)
	local okVariant, b = read(variant, property)
	if not (okBase and okVariant) or same(a, b) then
		return
	end
	if property == "Size" then
		out[Templates.attributeName(path, "SizeScale")] = Vector2.new(ratioOf(a.X.Scale, b.X.Scale), ratioOf(a.Y.Scale, b.Y.Scale))
	else
		out[Templates.attributeName(path, property)] = b
	end
end

local function walkDiff(base: Instance, variant: Instance, path: { string }, out: { [string]: any }, warnings: { string }, label: string)
	if base:IsA("GuiObject") then
		for _, property in GUI_PROPERTIES do
			compare(base, variant, path, property, out)
		end
	end
	local baseEntries = entries(base)
	local variantEntries = entries(variant)
	for _, entry in baseEntries do
		if entry.occurrence == 2 and entry.instance:GetAttribute("QuadroSlot") ~= true then
			table.insert(warnings, string.match(label, "^[^/]*") .. ": siblings named " .. entry.clean .. " share a name, states use index suffixes")
		end
		local other = counterpart(variantEntries, entry)
		local child = entry.instance
		if other and other.ClassName == child.ClassName then
			local childPath = table.clone(path)
			table.insert(childPath, Templates.segment(child.Name, entry.occurrence))
			local modifierProperty = MODIFIER_PROPERTIES[child.ClassName]
			if modifierProperty then
				compare(child, other, childPath, modifierProperty, out)
			elseif child:IsA("GuiObject") then
				walkDiff(child, other, childPath, out, warnings, label)
			end
		end
	end
	for _, entry in variantEntries do
		if MODIFIER_PROPERTIES[entry.instance.ClassName] and counterpart(baseEntries, entry) == nil then
			table.insert(warnings, label .. ": variant adds " .. entry.instance.ClassName .. " missing from Normal, ignored")
		end
	end
end

function Templates.diff(base: Instance, variant: Instance, warnings: { string }, label: string): { [string]: any }
	local out: { [string]: any } = {}
	walkDiff(base, variant, {}, out, warnings, label)
	return out
end

function Templates.writeStates(template: Instance, states: { [string]: { [string]: any } }, warnings: { string })
	local holder = template:FindFirstChild("QuadroStates")
	if next(states) == nil then
		if holder then
			holder.Parent = nil
		end
		return
	end
	if holder == nil then
		holder = Instance.new("Configuration")
		holder.Name = "QuadroStates"
		holder.Parent = template
	end
	local container = holder :: Instance
	for _, child in container:GetChildren() do
		if states[child.Name] == nil or not child:IsA("Configuration") then
			child.Parent = nil
		end
	end
	for name, values in states do
		local config = container:FindFirstChild(name)
		if config == nil then
			config = Instance.new("Configuration")
			config.Name = name
			config.Parent = container
		end
		local target = config :: Instance
		for key in target:GetAttributes() do
			target:SetAttribute(key, nil)
		end
		for key, value in values do
			local ok = pcall(target.SetAttribute, target, key, value)
			if not ok then
				table.insert(warnings, template.Name .. ": state attribute '" .. key .. "' skipped (unsupported)")
			end
		end
	end
end

local function members(parent: Instance, list: { Instance }?): { Instance }
	local out = list or {}
	for _, child in parent:GetChildren() do
		if child:GetAttribute("QuadroFlowWrap") == true or child:GetAttribute("QuadroSlot") == true then
			members(child, out)
		else
			table.insert(out, child)
		end
	end
	return out
end

local function bind(parent: Instance, node: Spec.Node, index: { [string]: Instance })
	local claimed: { [Instance]: boolean } = {}
	for _, child in node.children do
		if child.kind == "ignore" then
			continue
		end
		for _, candidate in members(parent) do
			if candidate:IsA("GuiObject") and not claimed[candidate] and candidate.Name == child.name then
				claimed[candidate] = true
				candidate:SetAttribute("FigmaId", child.id)
				index[child.id] = candidate
				bind(candidate, child, index)
				break
			end
		end
	end
	for _, candidate in members(parent) do
		if candidate:IsA("GuiObject") and not claimed[candidate] then
			local slot = candidate.Parent
			if slot and slot:GetAttribute("QuadroSlot") == true then
				slot.Parent = nil
			else
				candidate.Parent = nil
			end
		end
	end
end

function Templates.instantiate(template: Instance, node: Spec.Node, index: { [string]: Instance }): Instance
	local clone = template:Clone() :: Instance
	local stale = clone:FindFirstChild("QuadroStates")
	if stale then
		stale.Parent = nil
	end
	for _, descendant in clone:GetDescendants() do
		descendant:SetAttribute("FigmaId", nil)
		descendant:SetAttribute("QuadroLock", nil)
		descendant:SetAttribute("FigmaComponentKey", nil)
	end
	clone:SetAttribute("FigmaComponentKey", nil)
	clone:SetAttribute("QuadroLock", nil)
	clone:SetAttribute("FigmaId", node.id)
	index[node.id] = clone
	bind(clone, node, index)
	return clone
end

function Templates.folder(): Folder
	local storage = game:GetService("ReplicatedStorage")
	local existing = storage:FindFirstChild("QuadroTemplates")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "QuadroTemplates"
	folder.Parent = storage
	return folder
end

function Templates.syncRuntime(force: boolean): Installer.Report?
	if force or Installer.present() then
		return Installer.install({ loader = false })
	end
	return nil
end

return Templates
