--!strict
local RuntimeSource = require("../Import/RuntimeSource")

local Installer = {}

export type Status = "installed" | "updated" | "current" | "locked" | "conflict" | "absent"
export type Report = { module: Status, loader: Status, duplicates: number }

Installer.LOADER =
	'local Runtime = require(game:GetService("ReplicatedStorage"):WaitForChild("Quadro"):WaitForChild("Runtime"))\nRuntime.start()'

local function ensure(parent: Instance, name: string, className: string, source: string, create: boolean): (Status, number)
	local found: { Instance } = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(found, child)
		end
	end
	local duplicates = math.max(#found - 1, 0)
	local existing = found[1]
	if existing == nil then
		if not create then
			return "absent", 0
		end
		local created = Instance.new(className) :: any
		created.Name = name
		created.Source = source
		created.Parent = parent
		return "installed", 0
	end
	if existing:GetAttribute("QuadroLock") == true then
		return "locked", duplicates
	end
	if existing.ClassName ~= className then
		return "conflict", duplicates
	end
	local script = existing :: any
	if script.Source ~= source then
		script.Source = source
		return "updated", duplicates
	end
	return "current", duplicates
end

function Installer.install(options: { loader: boolean? }?): Report
	local storage = game:GetService("ReplicatedStorage")
	local folder = storage:FindFirstChild("Quadro")
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "Quadro"
		created.Parent = storage
		folder = created
	end
	local module, moduleDuplicates = ensure(folder :: Instance, "Runtime", "ModuleScript", RuntimeSource, true)
	local scripts = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
	local loader: Status, loaderDuplicates = "absent", 0
	if scripts then
		loader, loaderDuplicates = ensure(scripts, "QuadroRuntime", "LocalScript", Installer.LOADER, options == nil or options.loader ~= false)
	end
	return { module = module, loader = loader, duplicates = moduleDuplicates + loaderDuplicates }
end

function Installer.load(): any
	local module = Instance.new("ModuleScript")
	module.Source = RuntimeSource
	local ok, runtime = pcall(require, module)
	if ok and type(runtime) == "table" and type(runtime.start) == "function" and type(runtime.step) == "function" and type(runtime.stop) == "function" and type(runtime.eligible) == "function" then
		return runtime
	end
	return nil
end

Installer.TAGS = { "QuadroScaleRoot", "QuadroStrokeScale", "QuadroAnimatedGradient", "QuadroShine", "QuadroPageNav" }

function Installer.needed(root: Instance): boolean
	local CollectionService = game:GetService("CollectionService")
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, instance in list do
		for _, tag in Installer.TAGS do
			if CollectionService:HasTag(instance, tag) then
				return true
			end
		end
	end
	return false
end

function Installer.present(): boolean
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Quadro")
	return folder ~= nil and folder:FindFirstChild("Runtime") ~= nil
end

return Installer
