--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local ColorChips = require(script.Parent.Parent.Components.ColorChips)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local field = require(script.Parent.Parent.Components.Field)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local Stepper = require(script.Parent.Parent.Components.Stepper)
local BuilderMath = require(script.Parent.Parent.Parent.BuilderMath)
local Stops = require(script.Parent.Parent.Parent.Gradients.Stops)
local Picker = require(script.Parent.Parent.Parent.App.ColorPicker)
local ColorPicker = require(script.Parent.Parent.Components.ColorPicker)

type Translate = (key: string, ...any) -> string

type Props = {
	t: Translate,
	run: (id: string, ...any) -> (),
	picker: Picker.Handle,
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

local function subheading(text: string, order: number): any
	return Roact.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, theme.typography.subtitle.size + 4),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = theme.colors.text,
		Font = theme.typography.subtitle.font,
		TextSize = theme.typography.subtitle.size,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	})
end

local function block(order: number, children: { [any]: any }): any
	local content: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.md),
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

local function apply(text: string, order: number, onClick: () -> ()): any
	return Roact.createElement(Flow, {
		layoutOrder = order,
		children = {
			apply = Roact.createElement(Button, {
				text = text,
				variant = "primary",
				compact = true,
				onClick = onClick,
			}),
		},
	})
end

local function options(t: Translate, prefix: string, ids: { string }): { { id: string, label: string } }
	local list = {}
	for _, id in ids do
		table.insert(list, { id = id, label = t(prefix .. id) })
	end
	return list
end

local PATH_OWNER = "path"

local BuildersTab = Roact.Component:extend("QuadroBuildersTab")

function BuildersTab:init()
	self:setState({
		preset = BuilderMath.PRESET_DEFAULT,
		thickness = BuilderMath.THICKNESS_DEFAULT,
		hex = BuilderMath.COLOR_DEFAULT,
		count = BuilderMath.SAMPLE_DEFAULT,
		drag = BuilderMath.DRAG_DEFAULT,
	})
end

function BuildersTab:render()
	local props: Props = self.props
	local t = props.t
	local state = self.state
	local hex: string = state.hex
	local pathPresets = props.presets("pathPresets")
	local function fold(id: string, section: { [string]: any }): { [string]: any }
		return Section.folded(props.openSection, props.toggleSection, id, section)
	end
	local function pickColor(typed: string)
		local clean = Stops.parseHex(typed)
		if clean then
			self:setState({ hex = clean })
		end
	end
	local picker = props.picker
	local pickerOpen = Picker.isOpen(picker.state, PATH_OWNER)
	return Roact.createFragment({
		path = Roact.createElement(Section, fold("path", {
			title = t("builders_path"),
			layoutOrder = 1,
			children = {
				path = block(2, {
					title = subheading(t("cmd_path"), 1),
					hint = caption(t("path_sub"), 2),
					thickness = Roact.createElement(Stepper, {
						label = t("path_thickness"),
						value = state.thickness,
						min = BuilderMath.THICKNESS_MIN,
						max = BuilderMath.THICKNESS_MAX,
						step = 1,
						layoutOrder = 3,
						onChange = function(value: number)
							self:setState({ thickness = value })
						end,
					}),
					color = Roact.createElement(Flow, {
						layoutOrder = 4,
						children = {
							hex = field("pathHex", t("path_color"), hex, theme.sizes.hexFieldWidth, 1, pickColor),
							swatch = ColorPicker.circle(Picker.shown(picker.state, PATH_OWNER, hex), pickerOpen, function()
								picker.api.toggle(PATH_OWNER, hex)
							end, 2),
						},
					}),
					picker = if pickerOpen
						then Roact.createElement(ColorPicker, {
							picker = picker,
							t = t,
							onCommit = pickColor,
							chips = BuilderMath.COLORS,
							layoutOrder = 5,
						})
						else nil,
					presets = Roact.createElement(Disclosure, {
						label = t("presets_show"),
						expandedLabel = t("presets_hide"),
						expanded = pathPresets.open,
						onToggle = pathPresets.toggle,
						layoutOrder = 6,
						children = {
							shape = Roact.createElement(Pills, {
								options = options(t, "preset_", BuilderMath.PRESETS),
								value = state.preset,
								layoutOrder = 1,
								onSelect = function(id: string)
									self:setState({ preset = id })
								end,
							}),
							chips = Roact.createElement(ColorChips.render, { colors = BuilderMath.COLORS, onPick = pickColor, layoutOrder = 2 }),
						},
					}),
					apply = apply(t("path_apply"), 7, function()
						props.run("builder.path", state.preset, state.thickness, hex)
					end),
				}),
				sample = block(3, {
					title = subheading(t("sample_title"), 1),
					hint = caption(t("sample_sub"), 2),
					count = Roact.createElement(Stepper, {
						label = t("sample_count"),
						value = state.count,
						min = BuilderMath.SAMPLE_MIN,
						max = BuilderMath.SAMPLE_MAX,
						step = 1,
						editable = true,
						layoutOrder = 3,
						onChange = function(value: number)
							self:setState({ count = value })
						end,
					}),
					apply = apply(t("sample_apply"), 4, function()
						props.run("builder.pathSample", state.count)
					end),
				}),
			},
		})),
		drag = Roact.createElement(Section, fold("drag", {
			title = t("builders_drag"),
			layoutOrder = 2,
			children = {
				drag = block(2, {
					title = subheading(t("drag_title"), 1),
					hint = caption(t("drag_sub"), 2),
					preset = Roact.createElement(Pills, {
						options = options(t, "drag_", BuilderMath.DRAG_PRESETS),
						value = state.drag,
						layoutOrder = 3,
						onSelect = function(id: string)
							self:setState({ drag = id })
						end,
					}),
					apply = apply(t("drag_apply"), 4, function()
						props.run("builder.drag", state.drag)
					end),
				}),
			},
		})),
		pages = Roact.createElement(Section, fold("pages", {
			title = t("builders_pages"),
			layoutOrder = 3,
			children = {
				pages = block(2, {
					title = subheading(t("pages_title"), 1),
					hint = caption(t("pages_sub"), 2),
					apply = apply(t("pages_apply"), 3, function()
						props.run("builder.pages")
					end),
				}),
			},
		})),
	})
end

return BuildersTab
