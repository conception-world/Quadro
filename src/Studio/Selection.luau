--!strict
local Selection = {}

local function isContainer(instance: Instance): boolean
	return instance:IsA("Folder") or instance:IsA("ScreenGui") or instance:IsA("SurfaceGui") or instance:IsA("BillboardGui")
end

function Selection.guiTargets(): { GuiObject }
	local targets: { GuiObject } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(gui: GuiObject)
		if not seen[gui] then
			seen[gui] = true
			table.insert(targets, gui)
		end
	end
	for _, instance in game:GetService("Selection"):Get() do
		if instance:IsA("GuiObject") then
			add(instance)
		elseif isContainer(instance) then
			for _, child in instance:GetChildren() do
				if child:IsA("GuiObject") then
					add(child)
				end
			end
		end
	end
	return targets
end

function Selection.firstGui(): GuiObject?
	for _, instance in game:GetService("Selection"):Get() do
		local candidate: Instance? = instance
		if instance:IsA("UIGradient") or instance:IsA("UIStroke") then
			candidate = instance.Parent
			if candidate and candidate:IsA("UIStroke") then
				candidate = candidate.Parent
			end
		end
		if candidate and candidate:IsA("GuiObject") then
			return candidate
		end
	end
	return nil
end

function Selection.candidates(): { Instance }
	local found: { Instance } = {}
	for _, gui in Selection.guiTargets() do
		table.insert(found, gui)
	end
	for _, instance in game:GetService("Selection"):Get() do
		if not instance:IsA("GuiObject") and not isContainer(instance) then
			table.insert(found, instance)
		end
	end
	return found
end

function Selection.set(list: { Instance })
	game:GetService("Selection"):Set(list)
end

return Selection
