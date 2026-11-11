--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local Stepper = require(script.Parent.Parent.Components.Stepper)

type Translate = (key: string, ...any) -> string

type Props = {
	t: Translate,
	run: (id: string, ...any) -> (),
	openSection: { [string]: boolean },
	toggleSection: (id: string) -> (),
	presets: (id: string) -> { open: boolean, toggle: () -> () },
}

local EDGES = { "left", "hcenter", "right", "top", "vcenter", "bottom" }
local FLEX_ALIGNMENTS = { "none", "fill", "spaceAround", "spaceBetween", "spaceEvenly" }
local FLEX_ITEMS = { "none", "fill", "grow", "shrink" }
local GAP_MAX = 500
local GAP_STEP = 4

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

local LayoutTab = Roact.Component:extend("QuadroLayoutTab")

function LayoutTab:init()
	self:setState({
		reference = "selection",
		flexDir = "h",
		flexItem = "fill",
		hFlex = "none",
		vFlex = "none",
		wraps = false,
		distributeAxis = "h",
		matchWhich = "both",
		spacingAxis = "h",
		gap = nil,
		constraintKind = "both",
	})
end

function LayoutTab:render()
	local props: Props = self.props
	local t = props.t
	local state = self.state
	local function fold(id: string, section: { [string]: any }): { [string]: any }
		return Section.folded(props.openSection, props.toggleSection, id, section)
	end
	local function pills(prefix: string, ids: { string }, key: string, order: number): any
		return Roact.createElement(Pills, {
			options = options(t, prefix, ids),
			value = state[key],
			layoutOrder = order,
			onSelect = function(id: string)
				self:setState({ [key] = id })
			end,
		})
	end
	local flexMore = props.presets("flexMore")
	local spacingMore = props.presets("spacingMore")
	local edgeButtons: { [any]: any } = {}
	for index, edge in EDGES do
		edgeButtons[edge] = Roact.createElement(Button, {
			text = t("align_" .. edge),
			variant = "ghost",
			compact = true,
			layoutOrder = index,
			onClick = function()
				props.run("layout.align", edge, state.reference == "first")
			end,
		})
	end
	return Roact.createFragment({
		organize = Roact.createElement(Section, fold("organize", {
			title = t("layout_organize"),
			layoutOrder = 1,
			children = {
				grid = block(2, {
					title = subheading(t("cmd_auto_grid"), 1),
					hint = caption(t("grid_sub"), 2),
					apply = apply(t("btn_apply"), 3, function()
						props.run("layout.autoGrid")
					end),
				}),
				flex = block(3, {
					title = subheading(t("cmd_flex"), 1),
					hint = caption(t("flex_sub"), 2),
					dir = pills("flex_", { "h", "v" }, "flexDir", 3),
					item = pills("flex_item_", FLEX_ITEMS, "flexItem", 4),
					more = Roact.createElement(Disclosure, {
						label = t("more_show"),
						expandedLabel = t("more_hide"),
						expanded = flexMore.open,
						onToggle = flexMore.toggle,
						layoutOrder = 5,
						children = {
							hLabel = caption(t("flex_alignment_h"), 1),
							hFlex = pills("flex_", FLEX_ALIGNMENTS, "hFlex", 2),
							vLabel = caption(t("flex_alignment_v"), 3),
							vFlex = pills("flex_", FLEX_ALIGNMENTS, "vFlex", 4),
							wraps = Roact.createElement(Pills, {
								options = {
									{ id = "no", label = t("flex_nowrap") },
									{ id = "yes", label = t("flex_wraps") },
								},
								value = if state.wraps then "yes" else "no",
								layoutOrder = 5,
								onSelect = function(id: string)
									self:setState({ wraps = id == "yes" })
								end,
							}),
						},
					}),
					apply = apply(t("btn_apply"), 6, function()
						props.run("layout.flex", state.flexDir, state.hFlex, state.vFlex, state.wraps, state.flexItem)
					end),
				}),
			},
		})),
		align = Roact.createElement(Section, fold("align", {
			title = t("layout_align"),
			layoutOrder = 2,
			children = {
				align = block(2, {
					hint = caption(t("align_sub"), 1),
					reference = Roact.createElement(Pills, {
						options = {
							{ id = "selection", label = t("align_ref_selection") },
							{ id = "first", label = t("align_ref_first") },
						},
						value = state.reference,
						layoutOrder = 2,
						onSelect = function(id: string)
							self:setState({ reference = id })
						end,
					}),
					edges = Roact.createElement(Flow, { layoutOrder = 3, children = edgeButtons }),
				}),
				distribute = block(3, {
					title = subheading(t("cmd_distribute"), 1),
					hint = caption(t("distribute_sub"), 2),
					axis = pills("distribute_", { "h", "v" }, "distributeAxis", 3),
					apply = apply(t("btn_apply"), 4, function()
						props.run("layout.distribute", state.distributeAxis)
					end),
				}),
			},
		})),
		match = Roact.createElement(Section, fold("match", {
			title = t("layout_match"),
			layoutOrder = 3,
			children = {
				size = block(2, {
					title = subheading(t("cmd_match_size"), 1),
					hint = caption(t("size_sub"), 2),
					which = pills("size_", { "w", "h", "both" }, "matchWhich", 3),
					apply = apply(t("btn_apply"), 4, function()
						props.run("layout.matchSize", state.matchWhich)
					end),
				}),
				spacing = block(3, {
					title = subheading(t("cmd_match_spacing"), 1),
					hint = caption(t("spacing_sub"), 2),
					axis = pills("distribute_", { "h", "v" }, "spacingAxis", 3),
					more = Roact.createElement(Disclosure, {
						label = t("more_show"),
						expandedLabel = t("more_hide"),
						expanded = spacingMore.open,
						onToggle = spacingMore.toggle,
						layoutOrder = 4,
						children = {
							gap = Roact.createElement(Stepper, {
								label = t("spacing_gap"),
								value = state.gap or 0,
								min = 0,
								max = GAP_MAX,
								step = GAP_STEP,
								editable = true,
								layoutOrder = 1,
								onChange = function(value: number)
									self:setState({ gap = value })
								end,
							}),
							average = Roact.createElement(Flow, {
								layoutOrder = 2,
								children = {
									average = Roact.createElement(Button, {
										text = t("spacing_average"),
										variant = if state.gap == nil then "primary" else "ghost",
										compact = true,
										onClick = function()
											self:setState({ gap = Roact.None })
										end,
									}),
								},
							}),
						},
					}),
					apply = apply(t("btn_apply"), 5, function()
						props.run("layout.matchSpacing", state.spacingAxis, state.gap)
					end),
				}),
			},
		})),
		structure = Roact.createElement(Section, fold("structure", {
			title = t("layout_structure"),
			layoutOrder = 4,
			children = {
				reparent = block(2, {
					title = subheading(t("cmd_reparent"), 1),
					hint = caption(t("reparent_sub"), 2),
					apply = apply(t("btn_apply"), 3, function()
						props.run("layout.reparent")
					end),
				}),
				constraints = block(3, {
					title = subheading(t("cmd_constraints"), 1),
					hint = caption(t("constraints_sub"), 2),
					kind = pills("constraints_", { "size", "aspect", "both" }, "constraintKind", 3),
					apply = apply(t("btn_apply"), 4, function()
						props.run("layout.constraints", state.constraintKind)
					end),
				}),
			},
		})),
	})
end

return LayoutTab
