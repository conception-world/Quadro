--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local Button = require(script.Parent.Parent.Components.Button)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local Stepper = require(script.Parent.Parent.Components.Stepper)

type Translate = (key: string, ...any) -> string

type Props = {
	settings: { [string]: any },
	applicable: { [string]: boolean }?,
	t: Translate,
	run: (id: string, ...any) -> (),
	setSetting: (key: string, value: any) -> (),
	openSection: { [string]: boolean },
	toggleSection: (id: string) -> (),
	presets: (id: string) -> { open: boolean, toggle: () -> () },
	firstOrder: number,
}

type Entry = { text: string, enabled: boolean, onClick: () -> () }

local function fold(props: Props, id: string, section: { [string]: any }): { [string]: any }
	return Section.folded(props.openSection, props.toggleSection, id, section)
end

local CLAMP_PRESETS = {
	{ id = "wide", min = 0.5, max = 2 },
	{ id = "mid", min = 0.75, max = 1.5 },
	{ id = "tight", min = 0.9, max = 1.1 },
}

local Hybrid = Roact.Component:extend("QuadroHybridCard")

function Hybrid:init()
	self:setState({ target = "both" })
end

function Hybrid:render()
	local props: Props = self.props.tools
	local t = props.t
	local enabled = props.applicable ~= nil and props.applicable.hybrid == true
	local function percent(key: string): number
		return math.round((props.settings[key] :: number) * 100)
	end
	return Roact.createElement(Section, fold(props, "hybrid", {
		title = t("card_hybrid"),
		subtitle = t("hybrid_sub"),
		layoutOrder = props.firstOrder,
		children = {
			x = Roact.createElement(Stepper, {
				label = t("hybrid_x"),
				value = percent("hybridX"),
				min = 0,
				max = 100,
				step = 5,
				suffix = "%",
				layoutOrder = 2,
				onChange = function(value: number)
					props.setSetting("hybridX", value / 100)
				end,
			}),
			y = Roact.createElement(Stepper, {
				label = t("hybrid_y"),
				value = percent("hybridY"),
				min = 0,
				max = 100,
				step = 5,
				suffix = "%",
				layoutOrder = 3,
				onChange = function(value: number)
					props.setSetting("hybridY", value / 100)
				end,
			}),
			target = Roact.createElement(Pills, {
				options = {
					{ id = "size", label = t("hybrid_size") },
					{ id = "position", label = t("hybrid_position") },
					{ id = "both", label = t("hybrid_both") },
				},
				value = self.state.target,
				layoutOrder = 4,
				onSelect = function(id: string)
					self:setState({ target = id })
				end,
			}),
			apply = Roact.createElement(Button, {
				text = t("btn_apply"),
				variant = "primary",
				compact = true,
				disabled = not enabled,
				layoutOrder = 5,
				onClick = function()
					props.run("transform.hybrid", props.settings.hybridX, props.settings.hybridY, self.state.target)
				end,
			}),
		},
	}))
end

local function buttons(order: number, entries: { Entry }): any
	local children: { [any]: any } = {}
	for index, entry in entries do
		children["b" .. index] = Roact.createElement(Button, {
			text = entry.text,
			variant = "ghost",
			compact = true,
			disabled = not entry.enabled,
			layoutOrder = index,
			onClick = entry.onClick,
		})
	end
	return Roact.createElement(Flow, { layoutOrder = order, children = children })
end

local function modeEntries(props: Props, prefix: string, modes: { string }, enabled: boolean, id: string): { Entry }
	local entries: { Entry } = {}
	for _, mode in modes do
		table.insert(entries, {
			text = props.t(prefix .. mode),
			enabled = enabled,
			onClick = function()
				props.run(id, mode)
			end,
		})
	end
	return entries
end

local function ToolsPlus(props: Props): any
	local t = props.t
	local applicable = props.applicable or {}
	local base = props.firstOrder

	local clampEntries: { Entry } = {}
	for _, preset in CLAMP_PRESETS do
		table.insert(clampEntries, {
			text = t("clamp_" .. preset.id),
			enabled = applicable.responsive == true,
			onClick = function()
				props.run("responsive.clamp", preset.min, preset.max)
			end,
		})
	end
	local clamps = props.presets("clampPresets")

	return Roact.createFragment({
		hybrid = Roact.createElement(Hybrid, { tools = props }),
		stroke = Roact.createElement(Section, fold(props, "stroke", {
			title = t("card_stroke"),
			layoutOrder = base + 1,
			children = {
				body = buttons(2, modeEntries(props, "stroke_", { "px", "object", "screen" }, applicable.stroke == true, "stroke.convert")),
			},
		})),
		corner = Roact.createElement(Section, fold(props, "corner", {
			title = t("card_corner"),
			layoutOrder = base + 2,
			children = {
				body = buttons(2, modeEntries(props, "corner_", { "px", "scale", "percent", "hybrid" }, applicable.corner == true, "corner.convert")),
			},
		})),
		padding = Roact.createElement(Section, fold(props, "padding", {
			title = t("card_padding"),
			layoutOrder = base + 3,
			children = {
				body = buttons(2, modeEntries(props, "padding_", { "scale", "offset" }, applicable.padding == true, "padding.convert")),
			},
		})),
		textFit = Roact.createElement(Section, fold(props, "textFit", {
			title = t("card_text_fit"),
			layoutOrder = base + 4,
			children = {
				min = Roact.createElement(Stepper, {
					label = t("text_min"),
					value = props.settings.textMin,
					min = 1,
					max = 100,
					step = 1,
					layoutOrder = 2,
					onChange = function(value: number)
						props.setSetting("textMin", value)
						if value > props.settings.textMax then
							props.setSetting("textMax", value)
						end
					end,
				}),
				max = Roact.createElement(Stepper, {
					label = t("text_max"),
					value = props.settings.textMax,
					min = 1,
					max = 100,
					step = 1,
					layoutOrder = 3,
					onChange = function(value: number)
						props.setSetting("textMax", value)
						if value < props.settings.textMin then
							props.setSetting("textMin", value)
						end
					end,
				}),
				apply = Roact.createElement(Button, {
					text = t("btn_apply"),
					variant = "primary",
					compact = true,
					disabled = applicable.text ~= true,
					layoutOrder = 4,
					onClick = function()
						props.run("text.fit", props.settings.textMin, props.settings.textMax)
					end,
				}),
			},
		})),
		responsive = Roact.createElement(Section, fold(props, "responsive", {
			title = t("card_responsive"),
			layoutOrder = base + 5,
			children = {
				body = buttons(2, {
					{
						text = t("scale_root"),
						enabled = applicable.scaleRoot == true,
						onClick = function()
							props.run("responsive.scaleRoot")
						end,
					},
				}),
				presets = Roact.createElement(Disclosure, {
					label = t("presets_show"),
					expandedLabel = t("presets_hide"),
					expanded = clamps.open,
					onToggle = clamps.toggle,
					layoutOrder = 3,
					children = { clamps = buttons(1, clampEntries) },
				}),
			},
		})),
	})
end

return ToolsPlus
