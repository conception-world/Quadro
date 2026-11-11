--!strict
local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SelectionService = game:GetService("Selection")
local SerializationService = game:GetService("SerializationService")
local StarterGui = game:GetService("StarterGui")
local Files = require(script.Parent.Parent.Gradients.Files)
local GradientLibrary = require(script.Parent.Parent.Gradients.Library)
local Scan = require(script.Parent.Parent.Gradients.Scan)
local Gui = require(script.Parent.Parent.Studio.Gui)
local Installer = require(script.Parent.Parent.Runtime.Installer)
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)
local LibraryData = require(script.Parent.Parent.LibraryData)
local ToolsPlus = require(script.Parent.ToolsPlus)

local Library = {}

local ROOT = "QuadroLibrary"
local TOKENS = "Tokens"
local COMPONENTS = "Components"
local SIZE_ATTRIBUTE = "QuadroComponentSize"
local KILOBYTE = 1024

export type Listing = { tokens: { LibraryData.Item }, components: { LibraryData.Item } }

local function fail(message: string, ...: any): any
	return { ok = false, count = 0, message = message, args = { ... } }
end

local function failed(id: string, cause: any): any
	if cause == History.BUSY then
		return fail("error_busy")
	end
	warn("[Quadro] " .. id .. ": " .. tostring(cause))
	return fail("error_command_failed")
end

local function childOf(parent: Instance?, name: string, className: string): Instance?
	if parent == nil then
		return nil
	end
	for _, child in parent:GetChildren() do
		if child.Name == name and child.ClassName == className then
			return child
		end
	end
	return nil
end

local function ensure(parent: Instance, name: string, className: string): Instance
	local found = childOf(parent, name, className)
	if found then
		return found
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local function holder(name: string, className: string): Instance?
	return childOf(childOf(ReplicatedStorage, ROOT, "Folder"), name, className)
end

local function placeHolder(name: string, className: string): Instance
	return ensure(ensure(ReplicatedStorage, ROOT, "Folder"), name, className)
end

local function decode(kind: string, text: any): any
	if type(text) ~= "string" then
		return nil
	end
	local ok, raw = pcall(HttpService.JSONDecode, HttpService, text)
	return if ok then LibraryData.sanitize(kind, raw) else nil
end

local function placeTokens(): { [string]: any }
	local out: { [string]: any } = {}
	local tokens = holder(TOKENS, "Configuration")
	if tokens then
		for key, text in tokens:GetAttributes() do
			local kind = LibraryData.parseKey(key)
			local value = if kind then decode(kind, text) else nil
			if value ~= nil then
				out[key] = value
			end
		end
	end
	return out
end

local function placeComponents(): { [string]: GuiObject }
	local out: { [string]: GuiObject } = {}
	local components = holder(COMPONENTS, "Folder")
	if components then
		for _, child in components:GetChildren() do
			if child:IsA("GuiObject") and LibraryData.cleanName(child.Name) == child.Name and out[child.Name] == nil then
				out[child.Name] = child
			end
		end
	end
	return out
end

local function global(ctx: any): LibraryData.Global
	return ctx.store:get().settings.globalLibrary
end

local function names(map: { [string]: any }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for name in map do
		out[name] = true
	end
	return out
end

function Library.listing(store: any): Listing
	local saved: LibraryData.Global = store:get().settings.globalLibrary
	return {
		tokens = LibraryData.merge(placeTokens(), saved.tokens),
		components = LibraryData.merge(names(placeComponents()), names(saved.components)),
	}
end

function Library.refresh(store: any)
	store:set({ library = Library.listing(store) })
end

local function isText(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function owner(instance: Instance): Instance
	if instance:IsA("UIGradient") or instance:IsA("UICorner") then
		local parent = instance.Parent
		if parent and parent:IsA("UIStroke") then
			parent = parent.Parent
		end
		return parent or instance
	end
	return instance
end

local function gradientOf(instance: Instance): UIGradient?
	if instance:IsA("UIGradient") then
		return instance
	end
	local direct = instance:FindFirstChildOfClass("UIGradient")
	if direct then
		return direct
	end
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	return if stroke then stroke:FindFirstChildOfClass("UIGradient") else nil
end

local function sourceValue(kind: string, property: string): (any, Instance?)
	for _, instance in SelectionService:Get() do
		if kind == "gradient" then
			local gradient = gradientOf(instance)
			if gradient then
				return GradientLibrary.restData(gradient), gradient
			end
		elseif kind == "size" and instance:IsA("UICorner") then
			return instance.CornerRadius, instance
		elseif instance:IsA("GuiObject") then
			if kind == "size" then
				return instance.Size, instance
			elseif kind == "font" and isText(instance) then
				return (instance :: any).FontFace, instance
			elseif kind == "color" and property == "background" then
				return instance.BackgroundColor3, instance
			elseif kind == "color" and isText(instance) then
				return (instance :: any).TextColor3, instance
			end
		end
	end
	return nil, nil
end

local function encode(kind: string, value: any): any
	local valueType = typeof(value)
	local plain = value
	if kind == "color" and valueType == "Color3" then
		plain = value:ToHex()
	elseif kind == "size" and valueType == "UDim2" then
		plain = { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "size" and valueType == "UDim" then
		plain = { value.Scale, value.Offset }
	elseif kind == "font" and valueType == "Font" then
		plain = { family = value.Family, weight = value.Weight.Name, style = value.Style.Name }
	end
	return LibraryData.sanitize(kind, plain)
end

local function toFont(value: any): Font?
	local ok, font = pcall(function()
		return Font.new(value.family, (Enum.FontWeight :: any)[value.weight], (Enum.FontStyle :: any)[value.style])
	end)
	return if ok then font else nil
end

local function writeToken(ctx: any, id: string, scope: string, key: string, value: any): any
	if scope == "place" then
		local ok, cause = History.record(id, function()
			placeHolder(TOKENS, "Configuration"):SetAttribute(key, if value == nil then nil else HttpService:JSONEncode(value))
			return 1
		end, { nested = ctx.fromHook })
		return if ok then nil else failed(id, cause)
	end
	local saved = global(ctx)
	local tokens = table.clone(saved.tokens)
	if value ~= nil and tokens[key] == nil and LibraryData.count(tokens) >= LibraryData.MAX_TOKENS then
		return fail("error_library_global_full", LibraryData.MAX_TOKENS)
	end
	tokens[key] = value
	if not GradientLibrary.persist(ctx, "globalLibrary", { tokens = tokens, components = saved.components }) then
		return fail("error_setting_not_saved")
	end
	return nil
end

local function writeComponent(ctx: any, name: string, data: string?): any
	local saved = global(ctx)
	local components = table.clone(saved.components)
	if data ~= nil and components[name] == nil and LibraryData.count(components) >= LibraryData.MAX_COMPONENTS then
		return fail("error_library_global_full", LibraryData.MAX_COMPONENTS)
	end
	components[name] = data
	if not GradientLibrary.persist(ctx, "globalLibrary", { tokens = saved.tokens, components = components }) then
		return fail("error_setting_not_saved")
	end
	return nil
end

local function placeComponent(ctx: any, id: string, name: string, copy: Instance?): any
	local ok, cause = History.record(id, function()
		local existing = placeComponents()[name]
		if existing then
			existing.Parent = nil
		end
		if copy then
			copy.Name = name
			copy.Parent = placeHolder(COMPONENTS, "Folder")
		end
		return 1
	end, { nested = ctx.fromHook })
	return if ok then nil else failed(id, cause)
end

local function serialize(instance: Instance): (string?, any)
	local ok, encoded = pcall(function(): string
		local bytes = SerializationService:SerializeInstancesAsync({ instance })
		return buffer.tostring(EncodingService:Base64Encode(bytes))
	end)
	if not ok then
		warn("[Quadro] library serialize: " .. tostring(encoded))
		return nil, fail("error_command_failed")
	end
	if #encoded > LibraryData.MAX_COMPONENT_BYTES then
		return nil, fail("error_library_too_big", math.ceil(#encoded / KILOBYTE), LibraryData.MAX_COMPONENT_BYTES // KILOBYTE)
	end
	return encoded, nil
end

local function deserialize(data: string?): GuiObject?
	if data == nil then
		return nil
	end
	local ok, list = pcall(function(): { Instance }
		return SerializationService:DeserializeInstancesAsync(EncodingService:Base64Decode(buffer.fromstring(data)))
	end)
	if not ok then
		warn("[Quadro] library deserialize: " .. tostring(list))
		return nil
	end
	local found: GuiObject? = nil
	for _, instance in list do
		if found == nil and instance:IsA("GuiObject") then
			found = instance
		else
			instance:Destroy()
		end
	end
	return found
end

local function validScope(scope: any): boolean
	return table.find(LibraryData.SCOPES, scope) ~= nil
end

local function tokenKey(kind: any, name: any): string?
	if table.find(LibraryData.KINDS, kind) == nil or type(name) ~= "string" or LibraryData.cleanName(name) ~= name then
		return nil
	end
	return LibraryData.key(kind, name)
end

local function scopeLabel(ctx: any, scope: string): string
	return ctx.t("library_scope_" .. scope)
end

local function finish(ctx: any, key: string, ...: any): any
	Library.refresh(ctx.store)
	ctx.notify(ctx.t(key, ...), "success")
	return { ok = true, count = 1 }
end

local function registerTokens(registry: any)
	registry:define("library.saveToken", "cmd_library_save_token", function(ctx, kind: any, name: any, value: any, scope: any, property: any)
		local where = if scope == nil then "place" else scope
		local target = if property == nil then "background" else property
		if table.find(LibraryData.KINDS, kind) == nil or not validScope(where) or table.find(LibraryData.COLOR_PROPERTIES, target) == nil then
			return fail("error_bad_args")
		end
		local raw, source = value, nil
		if raw == nil then
			raw, source = sourceValue(kind, target)
			if raw == nil then
				return fail("error_library_no_source_" .. kind)
			end
		end
		local typed = if type(name) == "string" and name ~= "" then name elseif source then owner(source).Name else nil
		local cleaned = LibraryData.cleanName(typed)
		if cleaned == nil then
			return fail("error_library_bad_name")
		end
		local taken = if where == "place" then placeTokens() else global(ctx).tokens
		local clean = LibraryData.freeName(cleaned, function(candidate: string): boolean
			return taken[LibraryData.key(kind, candidate)] ~= nil
		end)
		local encoded = encode(kind, raw)
		if encoded == nil then
			return fail("error_bad_args")
		end
		local failure = writeToken(ctx, "library.saveToken", where, LibraryData.key(kind, clean), encoded)
		if failure then
			return failure
		end
		return finish(ctx, "result_library_saved", clean, scopeLabel(ctx, where))
	end)

	registry:define("library.applyToken", "cmd_library_apply_token", function(ctx, kind: any, name: any, property: any)
		local target = if property == nil then "background" else property
		local key = tokenKey(kind, name)
		if key == nil or table.find(LibraryData.COLOR_PROPERTIES, target) == nil then
			return fail("error_bad_args")
		end
		local value = placeTokens()[key]
		if value == nil then
			value = global(ctx).tokens[key]
		end
		if value == nil then
			return fail("error_library_missing", name)
		end
		local id = "library.applyToken"
		if kind == "gradient" then
			return ToolsPlus.execute(ctx, id, Scan.targets(), nil, function(instance: Instance)
				return Scan.apply(value, { instance }) > 0
			end)
		elseif kind == "font" then
			local font = toFont(value)
			if font == nil then
				return fail("error_bad_args")
			end
			return ToolsPlus.execute(ctx, id, Selection.guiTargets(), function(gui: GuiObject)
				return isText(gui) or "result_library_not_text"
			end, function(gui: GuiObject)
				(gui :: any).FontFace = font
				return true
			end)
		elseif kind == "color" then
			local color = Color3.fromHex(value)
			return ToolsPlus.execute(ctx, id, Selection.guiTargets(), function(gui: GuiObject)
				return target == "background" or isText(gui) or "result_library_not_text"
			end, function(gui: GuiObject)
				if target == "background" then
					gui.BackgroundColor3 = color
				else
					(gui :: any).TextColor3 = color
				end
				return true
			end)
		elseif #value == 2 then
			local radius = UDim.new(value[1], value[2])
			local targets: { Instance } = {}
			for _, instance in SelectionService:Get() do
				if instance:IsA("UICorner") then
					table.insert(targets, instance)
				end
			end
			for _, gui in Selection.guiTargets() do
				table.insert(targets, gui)
			end
			return ToolsPlus.execute(ctx, id, targets, nil, function(instance: Instance)
				local corner = if instance:IsA("UICorner") then instance else instance:FindFirstChildOfClass("UICorner")
				if corner == nil then
					corner = Instance.new("UICorner")
					corner.Parent = instance
				end
				(corner :: UICorner).CornerRadius = radius
				return true
			end)
		end
		local size = UDim2.new(value[1], value[2], value[3], value[4])
		return ToolsPlus.execute(ctx, id, Selection.guiTargets(), nil, function(gui: GuiObject)
			gui.Size = size
			return true
		end)
	end)

	registry:define("library.removeToken", "cmd_library_remove_token", function(ctx, kind: any, name: any, scope: any)
		local key = tokenKey(kind, name)
		if key == nil or not validScope(scope) then
			return fail("error_bad_args")
		end
		local present = if scope == "place" then placeTokens()[key] else global(ctx).tokens[key]
		if present == nil then
			return fail("error_library_missing", name)
		end
		local failure = writeToken(ctx, "library.removeToken", scope, key, nil)
		if failure then
			return failure
		end
		return finish(ctx, "result_library_removed", name, scopeLabel(ctx, scope))
	end)

	registry:define("library.copyToken", "cmd_library_copy_token", function(ctx, kind: any, name: any, to: any)
		local key = tokenKey(kind, name)
		if key == nil or not validScope(to) then
			return fail("error_bad_args")
		end
		local value = if to == "global" then placeTokens()[key] else global(ctx).tokens[key]
		if value == nil then
			return fail("error_library_missing", name)
		end
		local failure = writeToken(ctx, "library.copyToken", to, key, value)
		if failure then
			return failure
		end
		return finish(ctx, "result_library_copied", name, scopeLabel(ctx, to))
	end)

	registry:define("library.setTokenColor", "cmd_library_set_token_color", function(ctx, name: any, scope: any, hex: any)
		local key = tokenKey("color", name)
		local value = LibraryData.sanitize("color", hex)
		if key == nil or value == nil or not validScope(scope) then
			return fail("error_bad_args")
		end
		local present = if scope == "place" then placeTokens()[key] else global(ctx).tokens[key]
		if present == nil then
			return fail("error_library_missing", name)
		end
		local failure = writeToken(ctx, "library.setTokenColor", scope, key, value)
		if failure then
			return failure
		end
		return finish(ctx, "result_library_recolored", name, scopeLabel(ctx, scope))
	end)
end

local function insertTarget(): Instance?
	for _, instance in SelectionService:Get() do
		if instance:IsA("GuiObject") or instance:IsA("LayerCollector") then
			return instance
		end
	end
	return StarterGui:FindFirstChildOfClass("ScreenGui")
end

local function componentName(name: any): string?
	return if type(name) == "string" and LibraryData.cleanName(name) == name then name else nil
end

local function registerComponents(registry: any)
	registry:define("library.saveComponent", "cmd_library_save_component", function(ctx, name: any, scope: any)
		local where = if scope == nil then "place" else scope
		if not validScope(where) then
			return fail("error_bad_args")
		end
		local source: GuiObject? = nil
		for _, instance in SelectionService:Get() do
			if instance:IsA("GuiObject") then
				source = instance
				break
			end
		end
		if source == nil then
			return fail("error_library_no_component")
		end
		if not source.Archivable then
			return fail("result_library_not_archivable", source.Name)
		end
		local cleaned = LibraryData.cleanName(if type(name) == "string" and name ~= "" then name else source.Name)
		if cleaned == nil then
			return fail("error_library_bad_name")
		end
		local taken: { [string]: any } = if where == "place" then placeComponents() else global(ctx).components
		local clean = LibraryData.freeName(cleaned, function(candidate: string): boolean
			return taken[candidate] ~= nil
		end)
		local copy = source:Clone() :: GuiObject
		copy.Name = clean
		local rendered = Gui.renderedParent(source) ~= nil and source.AbsoluteSize.X > 0 and source.AbsoluteSize.Y > 0
		copy:SetAttribute(SIZE_ATTRIBUTE, if rendered then source.AbsoluteSize else nil)
		local failure: any
		if where == "global" then
			local data, problem = serialize(copy)
			copy:Destroy()
			if data == nil then
				return problem
			end
			failure = writeComponent(ctx, clean, data)
		else
			failure = placeComponent(ctx, "library.saveComponent", clean, copy)
			if failure then
				copy:Destroy()
			end
		end
		if failure then
			return failure
		end
		return finish(ctx, "result_library_saved", clean, scopeLabel(ctx, where))
	end)

	registry:define("library.insertComponent", "cmd_library_insert_component", function(ctx, name: any, scope: any)
		local clean = componentName(name)
		if clean == nil or not validScope(scope) then
			return fail("error_bad_args")
		end
		local copy: GuiObject? = nil
		if scope == "place" then
			local found = placeComponents()[clean]
			copy = if found and found.Archivable then found:Clone() :: GuiObject else nil
		else
			copy = deserialize(global(ctx).components[clean])
		end
		if copy == nil then
			return fail("error_library_missing", clean)
		end
		local inserted = copy :: GuiObject
		inserted.Name = clean
		local container = insertTarget()
		local runtime: Installer.Report? = nil
		local ok, cause = History.record("library.insertComponent", function()
			local parent = container
			if parent == nil then
				local screen = Instance.new("ScreenGui")
				screen.Parent = StarterGui
				parent = screen
			end
			local size = inserted:GetAttribute(SIZE_ATTRIBUTE)
			inserted:SetAttribute(SIZE_ATTRIBUTE, nil)
			inserted.Parent = parent
			if typeof(size) == "Vector2" and Gui.renderedParent(inserted) ~= nil then
				local origin, box = Gui.contentBox(Gui.renderParent(inserted))
				Gui.setBox(inserted, origin + (box - size) / 2, size)
			end
			if Installer.needed(inserted) then
				runtime = Installer.install()
			end
			return 1
		end, { nested = ctx.fromHook })
		if not ok then
			inserted:Destroy()
			return failed("library.insertComponent", cause)
		end
		SelectionService:Set({ inserted })
		ctx.notify(ctx.t("result_library_inserted", clean, (inserted.Parent :: Instance).Name), "success")
		ToolsPlus.announceRuntime(ctx, runtime)
		return { ok = true, count = 1 }
	end)

	registry:define("library.removeComponent", "cmd_library_remove_component", function(ctx, name: any, scope: any)
		local clean = componentName(name)
		if clean == nil or not validScope(scope) then
			return fail("error_bad_args")
		end
		local present = if scope == "place" then placeComponents()[clean] ~= nil else global(ctx).components[clean] ~= nil
		if not present then
			return fail("error_library_missing", clean)
		end
		local failure = if scope == "place"
			then placeComponent(ctx, "library.removeComponent", clean, nil)
			else writeComponent(ctx, clean, nil)
		if failure then
			return failure
		end
		return finish(ctx, "result_library_removed", clean, scopeLabel(ctx, scope))
	end)

	registry:define("library.copyComponent", "cmd_library_copy_component", function(ctx, name: any, to: any)
		local clean = componentName(name)
		if clean == nil or not validScope(to) then
			return fail("error_bad_args")
		end
		local failure: any
		if to == "global" then
			local found = placeComponents()[clean]
			if found == nil then
				return fail("error_library_missing", clean)
			end
			local data, problem = serialize(found)
			if data == nil then
				return problem
			end
			failure = writeComponent(ctx, clean, data)
		else
			local copy = deserialize(global(ctx).components[clean])
			if copy == nil then
				return fail("error_library_missing", clean)
			end
			failure = placeComponent(ctx, "library.copyComponent", clean, copy)
			if failure then
				copy:Destroy()
			end
		end
		if failure then
			return failure
		end
		return finish(ctx, "result_library_copied", clean, scopeLabel(ctx, to))
	end)
end

local function exportFolder(ctx: any): (Folder, number)
	local folder = Instance.new("Folder")
	folder.Name = ROOT
	local tokens = Instance.new("Configuration")
	tokens.Name = TOKENS
	tokens.Parent = folder
	local components = Instance.new("Folder")
	components.Name = COMPONENTS
	components.Parent = folder
	local listing = Library.listing(ctx.store)
	local placed = placeComponents()
	local count = 0
	for _, item in listing.tokens do
		tokens:SetAttribute(item.key, HttpService:JSONEncode(item.value))
		count += 1
	end
	for _, item in listing.components do
		local source = placed[item.key]
		local copy: Instance? = if item.scope == "place" and source and source.Archivable
			then source:Clone()
			else deserialize(global(ctx).components[item.key])
		if copy then
			copy.Name = item.key
			copy.Parent = components
			count += 1
		end
	end
	return folder, count
end

type Merged = { tokens: number, components: number, skipped: number, runtime: boolean }

local function mergeInto(roots: { Instance }): Merged
	local merged: Merged = { tokens = 0, components = 0, skipped = 0, runtime = false }
	for _, root in roots do
		local tokenSource = childOf(root, TOKENS, "Configuration")
		local componentSource = childOf(root, COMPONENTS, "Folder")
		local candidates: { Instance } = if componentSource then componentSource:GetChildren() else {}
		if tokenSource == nil and componentSource == nil and root:IsA("GuiObject") then
			candidates = { root }
		end
		if tokenSource then
			for key, text in tokenSource:GetAttributes() do
				local kind = LibraryData.parseKey(key)
				local value = if kind then decode(kind, text) else nil
				if value ~= nil then
					local tokens = placeHolder(TOKENS, "Configuration")
					if tokens:GetAttribute(key) ~= nil then
						merged.skipped += 1
					else
						tokens:SetAttribute(key, HttpService:JSONEncode(value))
						merged.tokens += 1
					end
				end
			end
		end
		for _, candidate in candidates do
			local clean = LibraryData.cleanName(candidate.Name)
			if clean and candidate:IsA("GuiObject") and candidate.Archivable then
				if placeComponents()[clean] then
					merged.skipped += 1
				else
					local copy = candidate:Clone()
					copy.Name = clean
					copy.Parent = placeHolder(COMPONENTS, "Folder")
					merged.components += 1
					merged.runtime = merged.runtime or Installer.needed(copy)
				end
			end
		end
	end
	return merged
end

local function registerFiles(registry: any)
	registry:define("library.export", "cmd_library_export", function(ctx, buildOnly: any)
		if Files.isExporting() then
			return fail("error_busy")
		end
		local folder, count = exportFolder(ctx)
		local measured, bytes = pcall(function(): number
			return buffer.len(SerializationService:SerializeInstancesAsync({ folder }))
		end)
		if measured and bytes > Files.MAX_FILE_BYTES then
			folder:Destroy()
			return fail("error_library_export_too_big", math.ceil(bytes / KILOBYTE), Files.MAX_FILE_BYTES // KILOBYTE)
		end
		if count == 0 or buildOnly == true or ctx.plugin == nil then
			folder:Destroy()
			if count == 0 then
				return fail("error_library_empty")
			end
			return if buildOnly == true then { ok = true, count = count } else fail("error_command_failed")
		end
		local ok, saved = Files.exportFolder(ctx.plugin, folder)
		if not ok then
			warn("[Quadro] library.export: " .. tostring(saved))
			return fail("error_library_export_failed")
		end
		if saved ~= true then
			ctx.notify(ctx.t("result_gradient_cancelled"), "info")
			return { ok = true, count = 0 }
		end
		ctx.notify(ctx.t("result_library_exported", count), "success")
		return { ok = true, count = count }
	end)

	registry:define("library.import", "cmd_library_import", function(ctx, source: any)
		local roots: { Instance }
		local owned = typeof(source) ~= "Instance"
		if owned then
			local found, errorKey, detail = Files.importInstances()
			if errorKey then
				return fail(errorKey, detail or "")
			end
			if found == nil then
				ctx.notify(ctx.t("result_gradient_cancelled"), "info")
				return { ok = true, count = 0 }
			end
			roots = found
		else
			roots = { source }
		end
		local merged: Merged = { tokens = 0, components = 0, skipped = 0, runtime = false }
		local runtime: Installer.Report? = nil
		local ok, cause = History.record("library.import", function()
			merged = mergeInto(roots)
			if merged.runtime then
				runtime = Installer.install()
			end
			return merged.tokens + merged.components
		end, { nested = ctx.fromHook })
		if owned then
			for _, root in roots do
				root:Destroy()
			end
		end
		if not ok then
			return failed("library.import", cause)
		end
		local added = merged.tokens + merged.components
		if added == 0 then
			return if merged.skipped > 0 then fail("result_library_import_skipped", merged.skipped) else fail("error_library_import_empty")
		end
		Library.refresh(ctx.store)
		ctx.notify(ctx.t("result_library_imported", merged.tokens, merged.components), "success")
		if merged.skipped > 0 then
			ctx.notify(ctx.t("result_library_import_skipped", merged.skipped), "warning")
		end
		ToolsPlus.announceRuntime(ctx, runtime)
		return { ok = true, count = added }
	end)
end

function Library.register(registry: any)
	registerTokens(registry)
	registerComponents(registry)
	registerFiles(registry)
end

return Library
