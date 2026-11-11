--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local SelectionService = game:GetService("Selection")
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")
local StudioService = game:GetService("StudioService")

local Codec = require(script.Parent.Codec)
local Library = require(script.Parent.Library)

local Files = {}

local EXPORT_NAME = "QuadroGradients"
local MAX_IMPORT = 200
local MAX_FILE_BYTES = 1000000
Files.MAX_FILE_BYTES = MAX_FILE_BYTES

local exporting = false

function Files.isExporting(): boolean
	return exporting
end

type Session = { recording: string? }

local function runExport(plugin: Plugin, folder: Folder, session: Session): (boolean, any)
	local previous = SelectionService:Get()
	session.recording = ChangeHistoryService:TryBeginRecording("Quadro_export", "Quadro: export") :: any
	folder.Parent = ServerStorage
	SelectionService:Set({ folder })
	local ok, result = pcall(plugin.PromptSaveSelectionAsync, plugin, folder.Name)
	SelectionService:Set(previous)
	return ok, result
end

function Files.exportFolder(plugin: Plugin, folder: Folder): (boolean, any)
	exporting = true
	local session: Session = {}
	local finished, ok, result = pcall(runExport, plugin, folder, session)
	if session.recording then
		pcall(ChangeHistoryService.FinishRecording, ChangeHistoryService, session.recording :: any, Enum.FinishRecordingOperation.Cancel)
	end
	pcall(function()
		folder.Parent = nil
		folder:Destroy()
	end)
	exporting = false
	if not finished then
		warn("[Quadro] export: " .. tostring(ok))
		return false, ok
	end
	return ok, result
end

function Files.export(plugin: Plugin, list: { Codec.Data }): (boolean, any)
	local folder = Instance.new("Folder")
	folder.Name = EXPORT_NAME
	for index, data in list do
		local gradient = Instance.new("UIGradient")
		if Library.write(gradient, data) then
			local base = Library.cleanName(data.name) or ("Gradient " .. index)
			local name, suffix = base, 2
			while folder:FindFirstChild(name) do
				name = base .. " " .. suffix
				suffix += 1
			end
			gradient.Name = name
			gradient.Parent = folder
		else
			gradient:Destroy()
		end
	end
	return Files.exportFolder(plugin, folder)
end

type Picked = { name: string, contents: string }

local function prompt(types: { string }): (Picked?, string?, string?)
	local prompted, file = pcall(function()
		return StudioService:PromptImportFileAsync(types)
	end)
	if not prompted then
		warn("[Quadro] import: " .. tostring(file))
		return nil, "error_import_failed", tostring(file)
	end
	if not file then
		return nil, nil, nil
	end
	local contents = file:GetBinaryContents()
	if #contents > MAX_FILE_BYTES then
		return nil, "error_import_too_large", nil
	end
	return { name = file.Name, contents = contents }, nil, nil
end

local function deserialize(contents: string): ({ Instance }?, string?, string?)
	local ok, instances = pcall(function()
		return SerializationService:DeserializeInstancesAsync(buffer.fromstring(contents))
	end)
	if not ok then
		warn("[Quadro] import: " .. tostring(instances))
		return nil, "error_import_failed", tostring(instances)
	end
	return instances, nil, nil
end

function Files.importInstances(): ({ Instance }?, string?, string?)
	local file, errorKey, detail = prompt({ "rbxm", "rbxmx" })
	if file == nil then
		return nil, errorKey, detail
	end
	return deserialize(file.contents)
end

function Files.import(): ({ Codec.Data }?, string?, string?)
	local file, errorKey, detail = prompt({ "rbxm", "rbxmx", "json" })
	if file == nil then
		return nil, errorKey, detail
	end
	local contents = file.contents
	local found: { Codec.Data } = {}
	if string.match(string.lower(file.name), "%.json$") then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, contents)
		if not ok then
			warn("[Quadro] import: " .. tostring(decoded))
			return nil, "error_import_failed", tostring(decoded)
		end
		if type(decoded) == "table" then
			local items = if type(decoded.gradients) == "table" then decoded.gradients else decoded
			for _, item in items do
				if #found >= MAX_IMPORT then
					break
				end
				local data = Codec.sanitize(item)
				if data then
					table.insert(found, data)
				end
			end
		end
	else
		local instances, failure, reason = deserialize(contents)
		if instances == nil then
			return nil, failure, reason
		end
		for _, root in instances do
			local candidates = root:GetDescendants()
			table.insert(candidates, 1, root)
			for _, candidate in candidates do
				if candidate:IsA("UIGradient") and #found < MAX_IMPORT then
					local data = Codec.sanitize(Library.toData(candidate))
					if data then
						table.insert(found, data)
					end
				end
			end
			root:Destroy()
		end
	end
	return found, nil, nil
end

return Files
