--!strict
local UserInputService = game:GetService("UserInputService")
local Catalog = require(script.Parent.Catalog)
local Menu = require(script.Parent.Parent.Studio.Menu)

local Actions = {}

type Registry = any
type Context = any
type Run = (id: string, ...any) -> any

function Actions.runner(registry: Registry, context: Context): Run
	return function(id: string, ...: any): any
		local before = context.store:get().toasts
		local result = registry:run(id, context, ...)
		if not result.ok and result.message and context.store:get().toasts == before then
			context.notify(context.t(result.message, table.unpack(result.args or {})), "error")
		end
		return result
	end
end

local function ctrlAltHeld(): boolean
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
	return ctrl and alt
end

function Actions.mount(plugin: Plugin, registry: Registry, context: Context, run: Run): () -> ()
	local created: { PluginAction } = {}
	local connections: { RBXScriptConnection } = {}

	local function define(actionId: string, text: string, callback: () -> ())
		local ok, action = pcall(function()
			return plugin:CreatePluginAction(actionId, text, text, "", true)
		end)
		if not ok or not action then
			warn("[Quadro] could not register action " .. actionId .. ": " .. tostring(action))
			return
		end
		table.insert(created, action)
		table.insert(connections, action.Triggered:Connect(callback))
	end

	for _, command in registry:list() do
		if not Catalog.NEEDS_ARGUMENTS[command.id] then
			define("Quadro_" .. command.id, "Quadro: " .. context.t(command.labelKey), function()
				run(command.id)
			end)
		end
	end

	local menuOpen = false
	local function openMenu()
		if menuOpen then
			return
		end
		menuOpen = true
		local items: { Menu.Item } = {}
		local labels: { [string]: string } = {}
		for _, command in registry:list() do
			labels[command.id] = context.t(command.labelKey)
		end
		for _, id in Catalog.SELECTION_IDS do
			table.insert(items, { id = id, text = labels[id] })
		end
		local choice = Menu.show(plugin, items)
		menuOpen = false
		if choice then
			run(choice)
		end
	end
	define("Quadro_OpenMenu", "Quadro: " .. context.t("menu_open"), function()
		task.spawn(openMenu)
	end)

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if UserInputService:GetFocusedTextBox() ~= nil or not ctrlAltHeld() then
				return
			end
			local shortcuts: { [string]: string } = context.store:get().settings.shortcuts
			for id, keyName in shortcuts do
				if keyName == input.KeyCode.Name then
					run(id)
					return
				end
			end
		end)
	)

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, action in created do
			pcall(action.Destroy, action)
		end
		table.clear(created)
	end
end

return Actions
