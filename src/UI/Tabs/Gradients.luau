--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local Section = require(script.Parent.Parent.Components.Section)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Swatch = require(script.Parent.Parent.Components.Swatch)
local Codec = require(script.Parent.Parent.Parent.Gradients.Codec)
local Library = require(script.Parent.Parent.Parent.Gradients.Library)
local Menu = require(script.Parent.Parent.Parent.Studio.Menu)

type Translate = (key: string, ...any) -> string
type Fold = { open: boolean, toggle: () -> () }

type Props = {
	state: { [string]: any },
	t: Translate,
	plugin: Plugin?,
	run: (id: string, ...any) -> (),
	saveData: (data: Codec.Data) -> (),
	layoutOrder: number,
	open: boolean,
	onToggle: () -> (),
	list: Fold,
	more: Fold,
}

type Entry = { signature: string, data: Codec.Data, label: string, uses: number }

local function storeView(props: Props): any
	return {
		get = function()
			return props.state
		end,
	}
end

local Gradients = Roact.Component:extend("QuadroGradientsTab")

function Gradients:init()
	self.menuOpen = false
	self.unmounted = false
	self:setState({ view = "saved", renaming = nil })
end

function Gradients:willUnmount()
	self.unmounted = true
end

function Gradients:entries(): { Entry }
	local props: Props = self.props
	local out: { Entry } = {}
	if self.state.view == "saved" then
		local uses: { [string]: number } = {}
		for _, group in props.state.gradientScan do
			uses[group.signature] = group.uses
		end
		for _, data in Library.list(storeView(props)) do
			local signature = Codec.signature(data)
			table.insert(out, { signature = signature, data = data, label = data.name, uses = uses[signature] or 0 })
		end
	else
		for _, group in props.state.gradientScan do
			table.insert(out, {
				signature = group.signature,
				data = group.data,
				label = props.t("gradient_uses", group.name, group.uses),
				uses = group.uses,
			})
		end
	end
	return out
end

function Gradients:openMenu(entry: Entry)
	local props: Props = self.props
	local plugin = props.plugin
	if not plugin or self.menuOpen then
		return
	end
	self.menuOpen = true
	local t = props.t
	local saved = self.state.view == "saved"
	local items: { Menu.Item } = { { id = "apply", text = t("gradient_menu_apply") } }
	if saved then
		table.insert(items, { id = "rename", text = t("gradient_menu_rename") })
	elseif Library.find(storeView(props), entry.signature) == nil then
		table.insert(items, { id = "save", text = t("gradient_menu_save") })
	end
	if entry.uses > 0 then
		table.insert(items, { id = "select", text = t("gradient_menu_select", entry.uses) })
	end
	if saved then
		table.insert(items, { separator = true })
		table.insert(items, { id = "delete", text = t("gradient_menu_delete") })
	end
	task.spawn(function()
		local choice = Menu.show(plugin, items)
		self.menuOpen = false
		if self.unmounted then
			return
		end
		if choice == "apply" then
			props.run("gradient.apply", entry.signature)
		elseif choice == "rename" then
			self:setState({ renaming = entry.signature })
		elseif choice == "save" then
			props.saveData(entry.data)
		elseif choice == "select" then
			props.run("gradient.select", entry.signature)
		elseif choice == "delete" then
			props.run("gradient.delete", entry.signature)
		end
	end)
end

function Gradients:render()
	local props: Props = self.props
	local t = props.t
	local view: string = self.state.view
	local animate = props.state.settings.swatchAnimation == true
	local entries = self:entries()

	local cells: { [any]: any } = {
		grid = Roact.createElement("UIGridLayout", {
			CellSize = UDim2.fromOffset(theme.sizes.swatchWidth, theme.sizes.swatchHeight + theme.spacing.tight + theme.sizes.swatchLabel),
			CellPadding = UDim2.fromOffset(theme.spacing.sm, theme.spacing.md),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, entry in entries do
		cells[entry.signature] = Roact.createElement(Swatch, {
			data = entry.data,
			label = entry.label,
			animate = animate,
			renaming = self.state.renaming == entry.signature,
			layoutOrder = index,
			onClick = function()
				props.run("gradient.apply", entry.signature)
			end,
			onRightClick = function()
				self:openMenu(entry)
			end,
			onRename = function(text: string?)
				if not self.unmounted then
					self:setState({ renaming = Roact.None })
				end
				if text ~= nil then
					props.run("gradient.rename", entry.signature, text)
				end
			end,
		})
	end

	local body: any
	if #entries == 0 then
		body = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.sizes.emptyStateHeight),
			BackgroundTransparency = 1,
			Text = t(if view == "saved" then "gradient_empty_saved" else "gradient_empty_game"),
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.body.font,
			TextSize = theme.typography.body.size,
			LayoutOrder = 1,
		})
	else
		body = Roact.createElement("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, cells)
	end

	local function barButton(key: string, id: string, variant: Button.Variant, order: number)
		return Roact.createElement(Button, {
			text = t(key),
			variant = variant,
			compact = true,
			layoutOrder = order,
			onClick = function()
				props.run(id)
			end,
		})
	end

	return Roact.createElement(Section, {
		title = t("effects_gradient_library"),
		layoutOrder = props.layoutOrder,
		open = props.open,
		onToggle = props.onToggle,
		children = {
			tabs = Roact.createElement(Pills, {
				options = {
					{ id = "saved", label = t("gradient_saved") },
					{ id = "game", label = t("gradient_game") },
				},
				value = view,
				layoutOrder = 2,
				onSelect = function(id: string)
					self:setState({ view = id, renaming = Roact.None })
				end,
			}),
			presets = Roact.createElement(Disclosure, {
				label = t("presets_show"),
				expandedLabel = t("presets_hide"),
				expanded = props.list.open,
				onToggle = props.list.toggle,
				layoutOrder = 3,
				children = { body = body },
			}),
			actions = Roact.createElement(Disclosure, {
				label = t("more_show"),
				expandedLabel = t("more_hide"),
				expanded = props.more.open,
				onToggle = props.more.toggle,
				layoutOrder = 4,
				leading = barButton("gradient_add", "gradient.save", "primary", 1),
				children = {
					extra = Roact.createElement(Flow, {
						layoutOrder = 1,
						children = {
							export = barButton("btn_export", "gradient.export", "ghost", 1),
							import = barButton("btn_import", "gradient.import", "ghost", 2),
							refresh = barButton("btn_refresh", "gradient.refresh", "ghost", 3),
						},
					}),
				},
			}),
		},
	})
end

return Gradients
