--!strict
local Codec = require(script.Parent.Codec)
local Library = require(script.Parent.Library)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Scan = {}

local ROOTS = {
	"Workspace",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterGui",
	"StarterPlayer",
	"StarterPack",
	"ServerStorage",
}

export type Group = { signature: string, name: string, data: Codec.Data, uses: number, references: { UIGradient } }

function Scan.collect(): { Group }
	local bySignature: { [string]: Group } = {}
	local groups: { Group } = {}
	local easel = workspace:FindFirstChild("EaselGradients")
	for _, name in ROOTS do
		local service = game:FindFirstChild(name)
		if service then
			local ok, descendants = pcall(service.GetDescendants, service)
			if ok then
				for _, instance in descendants do
					if instance:IsA("UIGradient") and not (easel and instance:IsDescendantOf(easel)) then
						local data = Library.toData(instance)
						local signature = Codec.signature(data)
						local group = bySignature[signature]
						if group then
							group.uses += 1
							table.insert(group.references, instance)
						else
							group = {
								signature = signature,
								name = data.name,
								data = data,
								uses = 1,
								references = { instance },
							}
							bySignature[signature] = group
							table.insert(groups, group)
						end
					end
				end
			end
		end
	end
	table.sort(groups, function(a, b)
		if a.uses ~= b.uses then
			return a.uses > b.uses
		end
		return a.name < b.name
	end)
	return groups
end

function Scan.summary(groups: { Group }): { { signature: string, name: string, uses: number, data: Codec.Data } }
	local out = {}
	for _, group in groups do
		table.insert(out, { signature = group.signature, name = group.name, uses = group.uses, data = group.data })
	end
	return out
end

function Scan.selectReferences(signature: string): number
	for _, group in Scan.collect() do
		if group.signature == signature then
			Selection.set(group.references)
			return #group.references
		end
	end
	return 0
end

function Scan.targets(): { Instance }
	local targets: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(instance: Instance)
		if not seen[instance] then
			seen[instance] = true
			table.insert(targets, instance)
		end
	end
	for _, instance in game:GetService("Selection"):Get() do
		if instance:IsA("UIGradient") or instance:IsA("UIStroke") then
			add(instance)
		end
	end
	for _, gui in Selection.guiTargets() do
		add(gui)
	end
	return targets
end

function Scan.apply(data: Codec.Data, targets: { Instance }): number
	local applied = 0
	local done: { [Instance]: boolean } = {}
	for _, target in targets do
		local gradient: UIGradient? = if target:IsA("UIGradient")
			then target
			else target:FindFirstChildOfClass("UIGradient")
		if gradient then
			if not done[gradient] then
				done[gradient] = true
				if Library.write(gradient, data) then
					applied += 1
				end
			end
		else
			local created = Instance.new("UIGradient")
			if Library.write(created, data) then
				created.Parent = target
				done[created] = true
				applied += 1
			else
				created:Destroy()
			end
		end
	end
	return applied
end

return Scan
