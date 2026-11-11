--!strict
if not plugin then
	error("Quadro must run as a Studio plugin", 0)
end

local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Roact = require(script.Packages.Roact)
local Store = require(script.App.Store)
local Settings = require(script.Studio.Settings)
local Notify = require(script.App.Notify)
local Registry = require(script.App.Registry)
local DevHook = require(script.Studio.DevHook)
local Transform = require(script.Commands.Transform)
local Anchor = require(script.Commands.Anchor)
local Convert = require(script.Commands.Convert)
local Constraint = require(script.Commands.Constraint)
local Text = require(script.Commands.Text)
local ToolsPlus = require(script.Commands.ToolsPlus)
local EffectsCommands = require(script.Commands.Effects)
local Layout = require(script.Commands.Layout)
local LayoutTab = require(script.Commands.LayoutTab)
local Builders = require(script.Commands.Builders)
local Nudge = require(script.Commands.Nudge)
local GradientCommands = require(script.Commands.Gradient)
local ImportCommands = require(script.Commands.Import)
local LibraryCommands = require(script.Commands.Library)
local LibraryData = require(script.LibraryData)
local Library = require(script.Gradients.Library)
local GradientEditor = require(script.App.GradientEditor)
local SliceEditor = require(script.App.SliceEditor)
local ColorPicker = require(script.App.ColorPicker)
local ColorPickerView = require(script.UI.Components.ColorPicker)
local History = require(script.Studio.History)
local Client = require(script.Bridge.Client)
local Resolve = require(script.Bridge.Resolve)
local Session = require(script.Bridge.Session)
local Codec = require(script.Gradients.Codec)
local Actions = require(script.App.Actions)
local Strings = require(script.UI.Strings)
local App = require(script.UI.App)
local Preview = require(script.Runtime.Preview)
local RuntimeSource = require(script.Import.RuntimeSource)

local VERSION = "0.2.0"
print("[Quadro] plugin loaded v" .. VERSION)

local private = script:GetAttribute("QuadroPrivate") == true
local saved = Settings.load(plugin)
local store = Store.new({
	lang = saved.lang,
	tab = if saved.tab == "figma" and not private then "tools" else saved.tab,
	selectionCount = #Selection:Get(),
	applicable = {},
	panelOpen = false,
	toasts = {},
	gradientScan = {},
	gradientEditor = GradientEditor.initial(),
	disclosures = {},
	sliceEditor = SliceEditor.initial(),
	colorPicker = ColorPicker.initial(),
	library = { tokens = {}, components = {} },
	libraryPending = false,
	settings = saved,
})

local registry = Registry.new()

local function translate(key: string, ...: any): string
	return Strings.get(store:get().lang, key, ...)
end

local context: Registry.Context = {
	store = store,
	plugin = plugin,
	t = translate,
	notify = function(text: string, kind: Registry.Kind)
		if kind == "error" or store:get().settings.notifications then
			Notify.push(store, text, kind, os.clock())
		end
	end,
}

local function currentSettings(): { [string]: any }
	return store:get().settings
end

Transform.register(registry, currentSettings)
Anchor.register(registry, currentSettings)
Convert.register(registry)
Constraint.register(registry)
Text.register(registry)
ToolsPlus.register(registry, currentSettings)
Layout.register(registry)
Builders.register(registry)
LayoutTab.register(registry)
GradientCommands.register(registry)
EffectsCommands.register(registry)
ImportCommands.register(registry)
LibraryCommands.register(registry)
local isEdit = RunService:IsEdit()
local detachNudge: () -> () = if isEdit
	then Nudge.attach(plugin, currentSettings, function(key: string, kind: string)
		context.notify(translate(key), kind :: Registry.Kind)
	end)
	else function() end

local run = Actions.runner(registry, context)

local editor = GradientEditor.bind({ store = store, run = run })
local slice = SliceEditor.bind({ store = store, run = run })
local picker = ColorPicker.bind(store)

local labelKeys: { [string]: string } = {}
for _, command in registry:list() do
	labelKeys[command.id] = command.labelKey
end

local function setSetting(key: string, value: any)
	if not Settings.save(plugin, key, value) then
		context.notify(translate("error_setting_not_saved"), "error")
	end
	local nextSettings = table.clone(store:get().settings)
	nextSettings[key] = value
	local patch: { [string]: any } = { settings = nextSettings }
	if key == "lang" then
		patch.lang = value
	end
	store:set(patch)
end

local function saveData(data: Codec.Data)
	local added, duplicates, failure = Library.add(context, { data })
	if failure then
		context.notify(translate(failure), "error")
	elseif added == 0 then
		context.notify(translate("result_gradient_duplicates", duplicates), "warning")
	else
		context.notify(translate("result_gradient_saved", added), "success")
	end
end

local function disclose(id: string, open: boolean)
	local nextOpen = table.clone(store:get().disclosures)
	nextOpen[id] = open
	store:set({ disclosures = nextOpen })
end

local function setOpenSection(tab: string, id: string, open: boolean, persist: boolean)
	local nextOpen = table.clone(store:get().settings.openSections)
	local set = table.clone(nextOpen[tab] or {})
	set[id] = if open then true else nil
	nextOpen[tab] = set
	if persist then
		setSetting("openSections", nextOpen)
		return
	end
	local nextSettings = table.clone(store:get().settings)
	nextSettings.openSections = nextOpen
	store:set({ settings = nextSettings })
end

local function toggleSection(tab: string, id: string)
	local current = store:get().settings.openSections[tab]
	setOpenSection(tab, id, not (current and current[id] == true), true)
end

local function requestRemove(section: string, scope: string, key: string, runCommand: (id: string, ...any) -> any): any
	local id = section .. ":" .. scope .. ":" .. key
	local now = os.clock()
	if LibraryData.confirms(store:get().libraryPending, id, now) then
		store:set({ libraryPending = false })
		if section == "token" then
			local kind, name = LibraryData.parseKey(key)
			return runCommand("library.removeToken", kind, name, scope)
		end
		return runCommand("library.removeComponent", key, scope)
	end
	local pending: LibraryData.Pending = { id = id, at = now }
	store:set({ libraryPending = pending })
	task.delay(LibraryData.CONFIRM_WINDOW, function()
		if store:get().libraryPending == pending then
			store:set({ libraryPending = false })
		end
	end)
	return nil
end

local function libraryRemove(section: string, scope: string, key: string)
	requestRemove(section, scope, key, run)
end

local function refreshApplicable()
	local state = store:get()
	if state.panelOpen == true and state.tab == "tools" then
		store:set({ applicable = ToolsPlus.applicable() })
	end
end

local function effectsVisible(state: { [string]: any }): boolean
	return state.panelOpen == true and state.tab == "effects"
end

local function showTab(id: string)
	store:set({ tab = id })
	refreshApplicable()
	if id == "library" then
		LibraryCommands.refresh(store)
	end
end

local librarySandbox = false
local bridgeSandbox = false
local cannedHits: { [string]: number } = {}

local function setBridgeSetting(key: string, value: any)
	if not bridgeSandbox then
		setSetting(key, value)
		return
	end
	local nextSettings = table.clone(store:get().settings)
	nextSettings[key] = value
	store:set({ settings = nextSettings })
end

local bridgeSession = Session.new({
	store = store,
	setSetting = setBridgeSetting,
	t = translate,
	notify = context.notify,
})

local importingPush = false

local function importPush(id: string, runCommand: (command: string, json: string) -> any, refresh: boolean): any
	if importingPush then
		context.notify(translate("error_busy"), "warning")
		return { ok = false, message = "error_busy" }
	end
	importingPush = true
	local ok, result = pcall(function(): any
		local json, reason = bridgeSession.prepare(id)
		if not json then
			context.notify(translate("bridge_import_failed", translate("bridge_status_" .. tostring(reason))), "error")
			return { ok = false, message = tostring(reason) }
		end
		return runCommand("import.spec", json)
	end)
	importingPush = false
	if not ok then
		local safe = Session.redact(tostring(result), store:get().settings.bridgeToken)
		warn("[Quadro] bridge import: " .. safe)
		context.notify(translate("bridge_import_failed", safe), "error")
		return { ok = false, message = "exception" }
	end
	if refresh then
		task.spawn(bridgeSession.poll, false)
	end
	return result
end

local bridgeActions = {
	importPush = function(id: string)
		importPush(id, function(command: string, json: string): any
			return run(command, json)
		end, true)
	end,
	setToken = function(token: string)
		setBridgeSetting("bridgeToken", token)
		task.spawn(bridgeSession.poll, false)
	end,
}

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 420, 560, 420, 400)
local widget = plugin:CreateDockWidgetPluginGuiAsync("Quadro_Panel", info)
widget.Title = "Quadro v" .. VERSION
widget.Name = "Quadro_Panel"

local function render(state: { [string]: any })
	local lang: string = state.lang
	return Roact.createElement(App, {
		state = state,
		showFigma = private,
		t = function(key: string, ...: any): string
			return Strings.get(lang, key, ...)
		end,
		plugin = plugin,
		labelKeys = labelKeys,
		run = run,
		setSetting = setSetting,
		saveData = saveData,
		notify = context.notify,
		bridge = bridgeActions,
		editor = editor,
		slice = slice,
		picker = picker,
		disclose = disclose,
		toggleSection = toggleSection,
		libraryRemove = libraryRemove,
		onSelectTab = function(id: string)
			showTab(id)
			Settings.save(plugin, "tab", id)
		end,
	})
end

local tree = Roact.mount(render(store:get()), widget, "Content")
local mirrorTree: any = nil
local unsubscribe = store:subscribe(function(state)
	Roact.update(tree, render(state))
	if mirrorTree then
		local mirrored, problem = pcall(Roact.update, mirrorTree, render(state))
		if not mirrored then
			warn("[Quadro] mirror: " .. tostring(problem))
		end
	end
end)

local function unmirror()
	if mirrorTree then
		Roact.unmount(mirrorTree)
		mirrorTree = nil
	end
end

if isEdit then
	local migrated = Library.migrateFromEasel(context)
	if migrated > 0 then
		context.notify(translate("gradient_migrated", migrated), "success")
	end
	task.defer(function()
		local ok, err = pcall(GradientCommands.refresh, store)
		if not ok then
			warn("[Quadro] gradient refresh: " .. tostring(err))
		end
		local listed, problem = pcall(LibraryCommands.refresh, store)
		if not listed then
			warn("[Quadro] library refresh: " .. tostring(problem))
		end
	end)
end

local function publicSettings(settings: { [string]: any }): { [string]: any }
	local copy = table.clone(settings)
	copy.bridgeToken = nil
	copy.globalLibrary = nil
	copy.hasBridgeToken = settings.bridgeToken ~= ""
	return copy
end

local unmountHook: () -> () = if not isEdit or not private then function() end else DevHook.mount({
	ping = function(): any
		return "pong " .. VERSION
	end,
	state = function(): any
		local state = store:get()
		return HttpService:JSONEncode({
			lang = state.lang,
			tab = state.tab,
			selectionCount = state.selectionCount,
			toastCount = #state.toasts,
			historyCommits = History.commits,
			editorWrites = GradientEditor.writes,
			settings = publicSettings(state.settings),
			bridge = {
				status = if state.bridge then state.bridge.status else nil,
				pushes = if state.bridge then #state.bridge.pushes else 0,
				uploads = if state.bridge then state.bridge.uploads else nil,
				loopPolls = bridgeSession.loopPolls(),
			},
		})
	end,
	run = function(id: string, ...: any): any
		local hookContext = table.clone(context)
		hookContext.fromHook = true
		if librarySandbox then
			hookContext.plugin = nil
		end
		return HttpService:JSONEncode(registry:run(id, hookContext, ...))
	end,
	librarySandbox = function(on: any): any
		if type(on) ~= "boolean" then
			return false
		end
		librarySandbox = on
		local nextSettings = table.clone(store:get().settings)
		nextSettings.globalLibrary = if on then { tokens = {}, components = {} } else Settings.load(plugin).globalLibrary
		store:set({ settings = nextSettings })
		LibraryCommands.refresh(store)
		return true
	end,
	library = function(): any
		LibraryCommands.refresh(store)
		local state = store:get()
		local sizes = {}
		for name, data in state.settings.globalLibrary.components do
			sizes[name] = #data
		end
		return HttpService:JSONEncode({ listing = state.library, globalSizes = sizes, pending = state.libraryPending })
	end,
	libraryRemove = function(section: any, scope: any, key: any): any
		if type(section) ~= "string" or type(scope) ~= "string" or type(key) ~= "string" then
			return false
		end
		local result = requestRemove(section, scope, key, function(id: string, ...: any): any
			local hookContext = table.clone(context)
			hookContext.fromHook = true
			if librarySandbox then
				hookContext.plugin = nil
			end
			return registry:run(id, hookContext, ...)
		end)
		return HttpService:JSONEncode(if result == nil then { pending = true } else result)
	end,
	import = function(json: any): any
		local hookContext = table.clone(context)
		hookContext.fromHook = true
		local before = store:get().lastImport
		local result = registry:run("import.spec", hookContext, json)
		local summary = store:get().lastImport
		if summary == before then
			summary = { ok = false, crashed = true, issues = { tostring(result.message) }, warnings = {} }
		end
		return HttpService:JSONEncode(summary)
	end,
	editor = function(method: any, ...: any): any
		local hookEditor = GradientEditor.bind({
			store = store,
			run = function(id: string, ...: any): any
				local hookContext = table.clone(context)
				hookContext.fromHook = true
				return registry:run(id, hookContext, ...)
			end,
		}) :: any
		local fn = hookEditor[method]
		if type(fn) ~= "function" then
			return "unknown editor method"
		end
		GradientEditor.load(store)
		fn(...)
		return HttpService:JSONEncode(store:get().gradientEditor)
	end,
	slice = function(method: any, ...: any): any
		local hookSlice = SliceEditor.bind({
			store = store,
			run = function(id: string, ...: any): any
				local hookContext = table.clone(context)
				hookContext.fromHook = true
				return registry:run(id, hookContext, ...)
			end,
		}) :: any
		local fn = hookSlice[method]
		if type(fn) ~= "function" then
			return "unknown slice method"
		end
		SliceEditor.pick(store)
		fn(...)
		return HttpService:JSONEncode(SliceEditor.public(store:get().sliceEditor))
	end,
	picker = function(method: any, ...: any): any
		local fn = (picker :: any)[method]
		if type(fn) ~= "function" then
			return "unknown picker method"
		end
		local hookContext = context :: any
		hookContext.fromHook = true
		local ok, problem = pcall(fn, ...)
		hookContext.fromHook = nil
		if not ok then
			return "picker error: " .. tostring(problem)
		end
		local state: ColorPicker.State = store:get().colorPicker
		return HttpService:JSONEncode({
			open = state.open,
			owner = state.owner,
			original = state.original,
			hex = ColorPicker.hex(state),
			h = state.h,
			s = state.s,
			v = state.v,
			dragging = state.dragging,
			recent = state.recent,
		})
	end,
	gradients = function(): any
		local entries = {}
		for _, data in Library.list(store) do
			table.insert(entries, { signature = Codec.signature(data), name = data.name })
		end
		local inGame = {}
		for _, group in store:get().gradientScan do
			table.insert(inGame, { signature = group.signature, uses = group.uses })
		end
		return HttpService:JSONEncode({ saved = entries, inGame = inGame })
	end,
	bridgeCanned = function(json: any): any
		bridgeSandbox = true
		local canned = HttpService:JSONDecode(json)
		cannedHits = {}
		Client.setTransport(function(request: Client.Request): Client.Response
			local path = string.match(request.Url, "^http://127%.0%.0%.1:%d+(.*)$") or ""
			cannedHits[path] = (cannedHits[path] or 0) + 1
			local entry = canned[path]
			if entry == nil then
				return { StatusCode = 404, Body = "{}" }
			end
			if type(entry) == "table" and entry.offline == true then
				error("canned network failure")
			end
			if type(entry) == "table" and entry.denied == true then
				error("Http requests are not enabled. Enable via game settings")
			end
			if type(entry) == "table" and entry.status == 401 then
				return { StatusCode = 401, Body = "{}" }
			end
			if type(entry) == "table" and entry.__delay ~= nil then
				task.wait(entry.__delay)
				entry = table.clone(entry)
				entry.__delay = nil
			end
			return { StatusCode = 200, Body = HttpService:JSONEncode(entry) }
		end)
		return true
	end,
	bridgeLoader = function(json: any, delay: any): any
		bridgeSandbox = true
		local map = HttpService:JSONDecode(json)
		Resolve.setLoader(function(decalId: number): number?
			if type(delay) == "number" then
				task.wait(delay)
			end
			return map[tostring(decalId)]
		end)
		return true
	end,
	bridgeSettings = function(json: any): any
		bridgeSandbox = true
		for key, value in HttpService:JSONDecode(json) do
			if key == "bridgeToken" or key == "resolvedImages" then
				setBridgeSetting(key, value)
			end
		end
		return true
	end,
	bridgeHits = function(): any
		return HttpService:JSONEncode(cannedHits)
	end,
	bridgeSavedHash = function(): any
		local persisted = Settings.load(plugin)
		local count = 0
		for _ in persisted.resolvedImages do
			count += 1
		end
		local sum = 0
		for index = 1, #persisted.bridgeToken do
			sum = (sum * 31 + string.byte(persisted.bridgeToken, index)) % 1000003
		end
		return string.format("%d:%d:%d", #persisted.bridgeToken, sum, count)
	end,
	bridgeReset = function(): any
		Client.reset()
		Resolve.reset()
		bridgeSandbox = false
		local persisted = Settings.load(plugin)
		local nextSettings = table.clone(store:get().settings)
		nextSettings.bridgeToken = persisted.bridgeToken
		nextSettings.resolvedImages = persisted.resolvedImages
		store:set({ settings = nextSettings })
		return true
	end,
	bridgePort = function(port: any): any
		if type(port) ~= "number" or port ~= math.floor(port) or port < 1 or port > 65535 then
			return false
		end
		setSetting("bridgePort", port)
		return true
	end,
	bridgePoll = function(single: any): any
		local summary = bridgeSession.poll(true)
		if single ~= false and Resolve.busy() then
			Resolve.waitIdle(5)
			local again = bridgeSession.poll(true)
			summary.filled += again.filled
		end
		return HttpService:JSONEncode(summary)
	end,
	bridgeImport = function(id: any): any
		local result = importPush(id, function(command: string, json: string): any
			local hookContext = table.clone(context)
			hookContext.fromHook = true
			return registry:run(command, hookContext, json)
		end, false)
		local last = store:get().lastImport
		return HttpService:JSONEncode({
			ok = result.ok,
			message = result.message,
			count = result.count,
			pendingImages = if last then last.pendingImages else nil,
		})
	end,
	bridgeSpec = function(id: any): any
		local settings = store:get().settings
		local result = Client.push({ token = settings.bridgeToken, port = settings.bridgePort }, tostring(id))
		if not result.ok then
			return "ERR " .. result.reason
		end
		for _, image in result.data.images or {} do
			image.asset = nil
			image.error = nil
		end
		return HttpService:JSONEncode(result.data)
	end,
	migrateTab = function(raw: any): any
		local probe = {
			GetSetting = function(_: any, key: string): any
				if key == "Quadro_tab" then
					return raw
				end
				return nil
			end,
		}
		return Settings.load(probe :: any).tab
	end,
	mirror = function(container: any): any
		unmirror()
		if typeof(container) ~= "Instance" then
			return false
		end
		mirrorTree = Roact.mount(render(store:get()), container, "Content")
		return true
	end,
	disclose = function(id: any, open: any): any
		if type(id) ~= "string" or type(open) ~= "boolean" then
			return false
		end
		disclose(id, open)
		return true
	end,
	openSection = function(tab: any, id: any, persist: any): any
		if not Settings.sectionValid(tab, id) then
			return false
		end
		setOpenSection(tab, id, true, persist == true)
		return true
	end,
	closeSection = function(tab: any, id: any, persist: any): any
		if not Settings.sectionValid(tab, id) then
			return false
		end
		setOpenSection(tab, id, false, persist == true)
		return true
	end,
	sectionsRoundTrip = function(raw: any): any
		local stored: { [string]: any } = {}
		local probe = {
			SetSetting = function(_: any, key: string, value: any)
				stored[key] = value
			end,
			GetSetting = function(_: any, key: string): any
				return stored[key]
			end,
		}
		if type(raw) == "string" then
			stored.Quadro_openSections = raw
		else
			Settings.save(probe :: any, "openSections", store:get().settings.openSections)
		end
		local loaded = Settings.load(probe :: any).openSections
		local nextSettings = table.clone(store:get().settings)
		nextSettings.openSections = loaded
		store:set({ settings = nextSettings })
		return HttpService:JSONEncode(loaded)
	end,
	setTab = function(id: string): any
		if not table.find(Settings.TAB_IDS, id) then
			return false
		end
		showTab(id)
		return true
	end,
	runtimeSource = function(): any
		return RuntimeSource
	end,
	previewEffects = function(value: any): any
		if type(value) ~= "boolean" then
			return false
		end
		local nextSettings = table.clone(store:get().settings)
		nextSettings.previewEffects = value
		store:set({ settings = nextSettings })
		return true
	end,
})

local running = true
task.spawn(function()
	while running do
		task.wait(0.5)
		Notify.expire(store, os.clock(), 3)
	end
end)

local stopBridge = bridgeSession.start(function()
	return private and isEdit and widget.Enabled and store:get().tab == "figma"
end)

local preview: Preview.Controller? = if isEdit
	then Preview.mount(function(): boolean
		local state = store:get()
		return not registry:held()
			and widget.Enabled
			and state.settings.previewEffects == true
			and (state.tab == "effects" or state.tab == "tools")
	end)
	else nil
if preview then
	registry.onHold = preview.suspend
end

store:set({ panelOpen = widget.Enabled })
refreshApplicable()
local stopEditor: () -> () = if isEdit then GradientEditor.watch(store, effectsVisible) else function() end
local stopSlice: () -> () = if isEdit then SliceEditor.watch(store, effectsVisible) else function() end

local function refreshLibrary()
	if store:get().tab == "library" then
		LibraryCommands.refresh(store)
	end
end
local undoConnection = ChangeHistoryService.OnUndo:Connect(refreshLibrary)
local redoConnection = ChangeHistoryService.OnRedo:Connect(refreshLibrary)

local selectionConnection = Selection.SelectionChanged:Connect(function()
	picker.cancel()
	store:set({ selectionCount = #Selection:Get() })
	refreshApplicable()
end)

local unmountActions = Actions.mount(plugin, registry, context, run)

local toolbar = plugin:CreateToolbar("Quadro")
local openButton = toolbar:CreateButton("QuadroOpen", Strings.get(saved.lang, "toolbar_tooltip"), "rbxassetid://71631667036318", "Quadro")
openButton.ClickableWhenViewportHidden = true
openButton:SetActive(widget.Enabled)
openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
local enabledConnection = widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
	store:set({ panelOpen = widget.Enabled })
	refreshApplicable()
	if not widget.Enabled then
		editor.dragEnd()
		picker.dragEnd()
	end
end)
local focusConnection = widget.WindowFocusReleased:Connect(function()
	editor.dragEnd()
	picker.dragEnd()
end)

plugin.Unloading:Connect(function()
	running = false
	if preview then
		preview.unmount()
	end
	stopBridge()
	stopEditor()
	stopSlice()
	detachNudge()
	unmountActions()
	unmountHook()
	unsubscribe()
	unmirror()
	selectionConnection:Disconnect()
	undoConnection:Disconnect()
	redoConnection:Disconnect()
	enabledConnection:Disconnect()
	focusConnection:Disconnect()
	Roact.unmount(tree)
	ColorPickerView.release()
end)
