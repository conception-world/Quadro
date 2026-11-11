--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Badge = require(script.Parent.Parent.Components.Badge)
local Button = require(script.Parent.Parent.Components.Button)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local field = require(script.Parent.Parent.Components.Field)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local LibraryData = require(script.Parent.Parent.Parent.LibraryData)
local Picker = require(script.Parent.Parent.Parent.App.ColorPicker)
local ColorPicker = require(script.Parent.Parent.Components.ColorPicker)

type Translate = (key: string, ...any) -> string

type Props = {
	t: Translate,
	run: (id: string, ...any) -> (),
	picker: Picker.Handle,
	library: { tokens: { LibraryData.Item }, components: { LibraryData.Item } },
	pending: any,
	remove: (section: string, scope: string, key: string) -> (),
	openSection: { [string]: boolean },
	toggleSection: (id: string) -> (),
	presets: (id: string) -> { open: boolean, toggle: () -> () },
}

local function caption(text: string, order: number): any
	return Roact.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = theme.colors.textMuted,
		Font = theme.typography.caption.font,
		TextSize = theme.typography.caption.size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order,
	})
end

local function block(order: number, children: { [any]: any }): any
	local content: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.sm),
		}),
	}
	for key, child in children do
		content[key] = child
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, content)
end

local function options(t: Translate, prefix: string, ids: { string }): { { id: string, label: string } }
	local list = {}
	for _, id in ids do
		table.insert(list, { id = id, label = t(prefix .. id) })
	end
	return list
end

type Row = {
	label: string,
	swatch: string?,
	onRecolor: ((hex: string) -> ())?,
	useText: string,
	onUse: () -> (),
	onCopy: (to: string) -> (),
}

local function itemRow(props: Props, section: string, item: LibraryData.Item, row: Row, order: number): any
	local t = props.t
	local other = if item.scope == "place" then "global" else "place"
	local pending = props.pending
	local confirming = type(pending) == "table" and pending.id == section .. ":" .. item.scope .. ":" .. item.key
	local children: { [any]: any } = {
		name = Roact.createElement("TextLabel", {
			Size = UDim2.fromOffset(0, theme.sizes.row),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = row.label,
			TextColor3 = theme.colors.text,
			Font = theme.typography.label.font,
			TextSize = theme.typography.label.size,
			LayoutOrder = 2,
		}),
		scope = Roact.createElement(Badge, {
			text = t("library_scope_" .. item.scope),
			color = if item.scope == "place" then theme.colors.accentAccept else theme.colors.accentInfo,
			layoutOrder = 3,
		}),
		use = Roact.createElement(Button, { text = row.useText, compact = true, layoutOrder = 4, onClick = row.onUse }),
		copy = Roact.createElement(Button, {
			text = t("library_to_" .. other),
			variant = "ghost",
			compact = true,
			layoutOrder = 5,
			onClick = function()
				row.onCopy(other)
			end,
		}),
		remove = Roact.createElement(Button, {
			text = if confirming then t("library_confirm") else t("library_remove"),
			variant = if confirming then "danger" else "ghost",
			compact = true,
			layoutOrder = 6,
			onClick = function()
				props.remove(section, item.scope, item.key)
			end,
		}),
	}
	local hex, onRecolor = row.swatch, row.onRecolor
	if hex == nil or onRecolor == nil then
		return Roact.createElement(Flow, { layoutOrder = order, children = children })
	end
	local picker = props.picker
	local owner = "token:" .. item.scope .. ":" .. item.key
	local open = Picker.isOpen(picker.state, owner)
	children.swatch = ColorPicker.circle(Picker.shown(picker.state, owner, hex), open, function()
		picker.api.toggle(owner, hex)
	end, 1)
	if not open then
		return Roact.createElement(Flow, { layoutOrder = order, children = children })
	end
	return block(order, {
		line = Roact.createElement(Flow, { layoutOrder = 1, children = children }),
		picker = Roact.createElement(ColorPicker, { picker = picker, t = t, onCommit = onRecolor, layoutOrder = 2 }),
	})
end

local function list(props: Props, id: string, rows: { any }, order: number, empty: string): any
	if #rows == 0 then
		return caption(empty, order)
	end
	local shown: { [any]: any } = {}
	local rest: { [any]: any } = {}
	for index, row in rows do
		if index <= LibraryData.LIST_LIMIT then
			shown["item" .. index] = row
		else
			rest["item" .. index] = row
		end
	end
	if #rows > LibraryData.LIST_LIMIT then
		local more = props.presets(id)
		shown.more = Roact.createElement(Disclosure, {
			label = props.t("library_show_all", #rows),
			expandedLabel = props.t("library_show_less"),
			expanded = more.open,
			onToggle = more.toggle,
			layoutOrder = LibraryData.LIST_LIMIT + 1,
			children = rest,
		})
	end
	return block(order, shown)
end

local LibraryTab = Roact.Component:extend("QuadroLibraryTab")

function LibraryTab:init()
	self:setState({
		kind = LibraryData.KINDS[1],
		property = LibraryData.COLOR_PROPERTIES[1],
		tokenName = "",
		tokenScope = "place",
		componentName = "",
		componentScope = "place",
	})
end

function LibraryTab:render()
	local props: Props = self.props
	local t = props.t
	local state = self.state
	local kind: string = state.kind
	local function fold(id: string, section: { [string]: any }): { [string]: any }
		return Section.folded(props.openSection, props.toggleSection, id, section)
	end
	local tokenRows = {}
	for _, item in props.library.tokens do
		local itemKind, name = LibraryData.parseKey(item.key)
		if itemKind == kind and name then
			table.insert(tokenRows, itemRow(props, "token", item, {
				label = name,
				swatch = if kind == "color" then item.value else nil,
				onRecolor = function(hex: string)
					props.run("library.setTokenColor", name, item.scope, hex)
				end,
				useText = t("library_apply"),
				onUse = function()
					props.run("library.applyToken", kind, name, state.property)
				end,
				onCopy = function(to: string)
					props.run("library.copyToken", kind, name, to)
				end,
			}, #tokenRows + 1))
		end
	end
	local componentRows = {}
	for _, item in props.library.components do
		table.insert(componentRows, itemRow(props, "component", item, {
			label = item.key,
			useText = t("library_insert"),
			onUse = function()
				props.run("library.insertComponent", item.key, item.scope)
			end,
			onCopy = function(to: string)
				props.run("library.copyComponent", item.key, to)
			end,
		}, #componentRows + 1))
	end
	local scopes = options(t, "library_scope_", LibraryData.SCOPES)
	return Roact.createFragment({
		tokens = Roact.createElement(Section, fold("tokens", {
			title = t("library_tokens"),
			layoutOrder = 1,
			children = {
				save = block(2, {
					kind = Roact.createElement(Pills, {
						options = options(t, "library_kind_", LibraryData.KINDS),
						value = kind,
						layoutOrder = 1,
						onSelect = function(id: string)
							self:setState({ kind = id })
						end,
					}),
					hint = caption(t("library_hint_" .. kind), 2),
					property = if kind == "color"
						then Roact.createElement(Pills, {
							options = options(t, "library_property_", LibraryData.COLOR_PROPERTIES),
							value = state.property,
							layoutOrder = 3,
							onSelect = function(id: string)
								self:setState({ property = id })
							end,
						})
						else nil,
					name = field("tokenName", t("library_name"), state.tokenName, theme.sizes.nameFieldWidth, 4, function(typed: string)
						self:setState({ tokenName = typed })
					end),
					scope = Roact.createElement(Pills, {
						options = scopes,
						value = state.tokenScope,
						layoutOrder = 5,
						onSelect = function(id: string)
							self:setState({ tokenScope = id })
						end,
					}),
					apply = Roact.createElement(Flow, {
						layoutOrder = 6,
						children = {
							apply = Roact.createElement(Button, {
								text = t("library_save_token"),
								compact = true,
								onClick = function()
									props.run("library.saveToken", kind, state.tokenName, nil, state.tokenScope, state.property)
								end,
							}),
						},
					}),
				}),
				list = list(props, "libraryTokensAll", tokenRows, 3, t("library_empty_tokens")),
			},
		})),
		components = Roact.createElement(Section, fold("components", {
			title = t("library_components"),
			layoutOrder = 2,
			children = {
				save = block(2, {
					hint = caption(t("library_components_hint"), 1),
					name = field("componentName", t("library_name"), state.componentName, theme.sizes.nameFieldWidth, 2, function(typed: string)
						self:setState({ componentName = typed })
					end),
					scope = Roact.createElement(Pills, {
						options = scopes,
						value = state.componentScope,
						layoutOrder = 3,
						onSelect = function(id: string)
							self:setState({ componentScope = id })
						end,
					}),
					apply = Roact.createElement(Flow, {
						layoutOrder = 4,
						children = {
							apply = Roact.createElement(Button, {
								text = t("library_save_component"),
								compact = true,
								onClick = function()
									props.run("library.saveComponent", state.componentName, state.componentScope)
								end,
							}),
						},
					}),
				}),
				list = list(props, "libraryComponentsAll", componentRows, 3, t("library_empty_components")),
			},
		})),
		file = Roact.createElement(Section, fold("file", {
			title = t("library_file"),
			layoutOrder = 3,
			children = {
				body = block(2, {
					hint = caption(t("library_file_hint"), 1),
					actions = Roact.createElement(Flow, {
						layoutOrder = 2,
						children = {
							export = Roact.createElement(Button, {
								text = t("library_export"),
								compact = true,
								layoutOrder = 1,
								onClick = function()
									props.run("library.export")
								end,
							}),
							import = Roact.createElement(Button, {
								text = t("library_import"),
								variant = "ghost",
								compact = true,
								layoutOrder = 2,
								onClick = function()
									props.run("library.import")
								end,
							}),
						},
					}),
				}),
			},
		})),
	})
end

return LibraryTab
