--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Section = require(script.Parent.Parent.Components.Section)
local Flow = require(script.Parent.Parent.Components.Flow)
local Toggle = require(script.Parent.Parent.Components.Toggle)
local AnchorGrid = require(script.Parent.Parent.Components.AnchorGrid)
local ToolsPlus = require(script.Parent.ToolsPlus)
local Convert = require(script.Parent.Parent.Parent.Commands.Convert)

type Translate = (key: string, ...any) -> string

type Props = {
	settings: { [string]: any },
	applicable: { [string]: boolean }?,
	t: Translate,
	labelKeys: { [string]: string },
	run: (id: string, ...any) -> (),
	setSetting: (key: string, value: any) -> (),
	openSection: { [string]: boolean },
	toggleSection: (id: string) -> (),
	presets: (id: string) -> { open: boolean, toggle: () -> () },
}

local TRANSFORM_IDS = {
	{ id = "transform.posScale", variant = "primary" },
	{ id = "transform.posOffset", variant = "ghost" },
	{ id = "transform.sizeScale", variant = "primary" },
	{ id = "transform.sizeOffset", variant = "ghost" },
}
local LAYOUT_IDS = {
	"layout.group",
	"layout.groupButton",
	"layout.groupEach",
	"layout.ungroup",
	"layout.fit",
	"layout.expand",
}
local TEXT_IDS = { "text.scale", "constraint.aspect" }

local function commandButton(props: Props, id: string, variant: Button.Variant, order: number, size: UDim2?)
	return Roact.createElement(Button, {
		text = props.t(props.labelKeys[id]),
		variant = variant,
		compact = true,
		size = size,
		layoutOrder = order,
		onClick = function()
			props.run(id)
		end,
	})
end

local function commandFlow(props: Props, ids: { string }, variant: Button.Variant, order: number)
	local buttons: { [any]: any } = {}
	for index, id in ids do
		buttons[id] = commandButton(props, id, variant, index)
	end
	return Roact.createElement(Flow, { layoutOrder = order, children = buttons })
end

local function Tools(props: Props)
	local t = props.t
	local quickIds: { string } = props.settings.quickActions
	local quickBody: any
	if #quickIds == 0 then
		quickBody = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.typography.caption.size + 4),
			BackgroundTransparency = 1,
			Text = t("quick_empty"),
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		})
	else
		local known: { string } = {}
		for _, id in quickIds do
			if props.labelKeys[id] then
				table.insert(known, id)
			end
		end
		quickBody = commandFlow(props, known, "ghost", 2)
	end

	local transformCells: { [any]: any } = {
		grid = Roact.createElement("UIGridLayout", {
			CellSize = UDim2.new(0.5, -theme.spacing.sm / 2, 0, theme.sizes.row),
			CellPadding = UDim2.fromOffset(theme.spacing.sm, theme.spacing.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, entry in TRANSFORM_IDS do
		transformCells[entry.id] = commandButton(props, entry.id, entry.variant :: Button.Variant, index, UDim2.fromOffset(0, theme.sizes.row))
	end

	local convertButtons: { [any]: any } = {}
	for index, className in Convert.CLASSES do
		convertButtons[className] = Roact.createElement(Button, {
			text = t("conv_" .. string.lower(className)),
			variant = "ghost",
			compact = true,
			layoutOrder = index,
			onClick = function()
				props.run("convert.to", className)
			end,
		})
	end

	local gridWidth = theme.sizes.anchorCell * 3 + theme.spacing.sm * 2
	local function fold(id: string, section: { [string]: any }): { [string]: any }
		return Section.folded(props.openSection, props.toggleSection, id, section)
	end

	return Roact.createFragment({
		quick = Roact.createElement(Section, fold("quick", {
			title = t("card_quick"),
			layoutOrder = 1,
			children = { body = quickBody },
		})),
		transform = Roact.createElement(Section, fold("transform", {
			title = t("card_transform"),
			layoutOrder = 2,
			children = {
				body = Roact.createElement("Frame", {
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, transformCells),
			},
		})),
		anchor = Roact.createElement(Section, fold("anchor", {
			title = t("card_anchor"),
			layoutOrder = 3,
			children = {
				body = Roact.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, gridWidth),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					grid = Roact.createElement(AnchorGrid, {
						onPick = function(x: number, y: number)
							props.run("anchor.set", x, y)
						end,
					}),
					preserve = Roact.createElement("Frame", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(1, 0.5),
						Size = UDim2.new(1, -(gridWidth + theme.spacing.lg), 0, theme.sizes.anchorToggleHeight),
						BackgroundTransparency = 1,
					}, {
						toggle = Roact.createElement(Toggle, {
							title = t("anchor_preserve"),
							subtitle = t("anchor_preserve_sub"),
							value = props.settings.anchorPreserve == true,
							onChange = function(value: boolean)
								props.setSetting("anchorPreserve", value)
							end,
						}),
					}),
				}),
			},
		})),
		convert = Roact.createElement(Section, fold("convert", {
			title = t("card_convert"),
			layoutOrder = 4,
			children = { body = Roact.createElement(Flow, { layoutOrder = 2, children = convertButtons }) },
		})),
		layout = Roact.createElement(Section, fold("layout", {
			title = t("card_layout"),
			layoutOrder = 5,
			children = { body = commandFlow(props, LAYOUT_IDS, "ghost", 2) },
		})),
		text = Roact.createElement(Section, fold("text", {
			title = t("card_text"),
			layoutOrder = 6,
			children = { body = commandFlow(props, TEXT_IDS, "ghost", 2) },
		})),
		plus = Roact.createElement(ToolsPlus, {
			settings = props.settings,
			applicable = props.applicable,
			t = t,
			run = props.run,
			setSetting = props.setSetting,
			openSection = props.openSection,
			toggleSection = props.toggleSection,
			presets = props.presets,
			firstOrder = 7,
		}),
	})
end

return Tools
