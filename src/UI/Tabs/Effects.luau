--!strict
local SelectionService = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local Selection = require(script.Parent.Parent.Parent.Studio.Selection)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local ColorChips = require(script.Parent.Parent.Components.ColorChips)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local field = require(script.Parent.Parent.Components.Field)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local Stepper = require(script.Parent.Parent.Components.Stepper)
local Toggle = require(script.Parent.Parent.Components.Toggle)
local Gradients = require(script.Parent.Gradients)
local GradientStudio = require(script.Parent.GradientStudio)
local Codec = require(script.Parent.Parent.Parent.Gradients.Codec)
local Library = require(script.Parent.Parent.Parent.Gradients.Library)
local Stops = require(script.Parent.Parent.Parent.Gradients.Stops)
local EffectPresets = require(script.Parent.Parent.Parent.EffectPresets)
local GradientEditor = require(script.Parent.Parent.Parent.App.GradientEditor)
local SliceEditor = require(script.Parent.Parent.Parent.App.SliceEditor)
local Picker = require(script.Parent.Parent.Parent.App.ColorPicker)
local ColorPicker = require(script.Parent.Parent.Components.ColorPicker)

type Translate = (key: string, ...any) -> string
type Run = (id: string, ...any) -> ()

type Props = {
	state: { [string]: any },
	t: Translate,
	plugin: Plugin?,
	run: Run,
	saveData: (data: Codec.Data) -> (),
	editor: GradientEditor.Api,
	slice: SliceEditor.Api,
	picker: Picker.Handle,
	disclose: (id: string, open: boolean) -> (),
	openSection: { [string]: boolean },
	toggleSection: (id: string) -> (),
}

type Presets = { open: boolean, toggle: () -> () }

local MASK_SIDES = { "top", "bottom", "left", "right", "edges" }
local MASK_LENGTH_MIN = 5
local MASK_LENGTH_MAX = 50
local MASK_LENGTH_STEP = 5
local MASK_LENGTH_DEFAULT = 30
local LIBRARY_COLORS = 8
local PERCENT = 100
local TENTHS = 10
local SPEED_MIN = 0.1
local SPEED_MAX = 5
local SPEED_STEP = 0.1
local RANGE_MIN = 0.1
local RANGE_MAX = 2
local RANGE_STEP = 0.1
local INTERVAL_MIN = 0.4
local INTERVAL_MAX = 10
local INTERVAL_STEP = 0.2
local DURATION_MIN = 0.2
local DURATION_MAX = 3
local DURATION_STEP = 0.1
local WIDTH_MIN = 2
local WIDTH_MAX = 96
local WIDTH_STEP = 2
local ANGLE_MIN = -180
local ANGLE_MAX = 180
local ANGLE_STEP = 5

local function tenths(value: number): number
	return math.round(value * TENTHS) / TENTHS
end

local function caption(text: string, order: number, color: Color3?): any
	return Roact.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color or theme.colors.textMuted,
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

local function action(text: string, order: number, onClick: () -> (), disabled: boolean?): any
	return Roact.createElement(Flow, {
		layoutOrder = order,
		children = {
			apply = Roact.createElement(Button, {
				text = text,
				variant = "primary",
				compact = true,
				disabled = disabled,
				onClick = onClick,
			}),
		},
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

local function presetList(t: Translate, presets: Presets, order: number, children: { [any]: any }): any
	return Roact.createElement(Disclosure, {
		label = t("presets_show"),
		expandedLabel = t("presets_hide"),
		expanded = presets.open,
		onToggle = presets.toggle,
		layoutOrder = order,
		children = children,
	})
end

local memoSource: any = nil
local memoColors: { string } = {}

local function libraryColors(state: { [string]: any }): { string }
	local source = state.settings.gradients
	if source == memoSource then
		return memoColors
	end
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local view = {
		get = function()
			return state
		end,
	}
	for _, data in Library.list(view) do
		for _, stop in data.color do
			if not seen[stop.c] and #out < LIBRARY_COLORS then
				seen[stop.c] = true
				table.insert(out, stop.c)
			end
		end
	end
	memoSource, memoColors = source, out
	return out
end

type MaskProps = { t: Translate, run: Run, layoutOrder: number }

local FadingMask = Roact.Component:extend("QuadroFadingMaskCard")

function FadingMask:init()
	self:setState({ side = "bottom", axis = "h", length = MASK_LENGTH_DEFAULT })
end

function FadingMask:render()
	local props: MaskProps = self.props
	local t = props.t
	local side: string = self.state.side
	local sides = {}
	for _, id in MASK_SIDES do
		table.insert(sides, { id = id, label = t("mask_" .. id) })
	end
	return block(props.layoutOrder, {
		title = subheading(t("mask_title"), 1),
		hint = caption(t("mask_sub"), 2),
		side = Roact.createElement(Pills, {
			options = sides,
			value = side,
			layoutOrder = 3,
			onSelect = function(id: string)
				self:setState({ side = id })
			end,
		}),
		axis = if side == "edges"
			then Roact.createElement(Pills, {
				options = {
					{ id = "h", label = t("mask_axis_h") },
					{ id = "v", label = t("mask_axis_v") },
				},
				value = self.state.axis,
				layoutOrder = 4,
				onSelect = function(id: string)
					self:setState({ axis = id })
				end,
			})
			else nil,
		length = Roact.createElement(Stepper, {
			label = t("mask_length"),
			value = self.state.length,
			min = MASK_LENGTH_MIN,
			max = MASK_LENGTH_MAX,
			step = MASK_LENGTH_STEP,
			suffix = "%",
			layoutOrder = 5,
			onChange = function(value: number)
				self:setState({ length = value })
			end,
		}),
		apply = action(t("mask_apply"), 6, function()
			props.run("effect.fadingMask", side, self.state.length / PERCENT, self.state.axis)
		end),
	})
end

type ShadowProps = { t: Translate, run: Run, presets: Presets, layoutOrder: number, open: boolean, onToggle: () -> () }

local ShadowStudio = Roact.Component:extend("QuadroShadowStudio")

function ShadowStudio:init()
	self:setState({ preset = EffectPresets.SHADOW_DEFAULT })
end

function ShadowStudio:render()
	local props: ShadowProps = self.props
	local t = props.t
	local preset: string = self.state.preset
	local options = {}
	for _, id in EffectPresets.SHADOW_ORDER do
		table.insert(options, { id = id, label = t("shadow_" .. id) })
	end
	return Roact.createElement(Section, {
		title = t("effects_shadow"),
		layoutOrder = props.layoutOrder,
		open = props.open,
		onToggle = props.onToggle,
		children = {
			title = subheading(t("shadow_title"), 2),
			hint = caption(t("shadow_sub"), 3),
			presets = presetList(t, props.presets, 4, {
				pills = Roact.createElement(Pills, {
					options = options,
					value = preset,
					layoutOrder = 1,
					onSelect = function(id: string)
						self:setState({ preset = id })
					end,
				}),
			}),
			actions = Roact.createElement(Flow, {
				layoutOrder = 5,
				children = {
					apply = Roact.createElement(Button, {
						text = t("shadow_apply", t("shadow_" .. preset)),
						variant = "primary",
						compact = true,
						layoutOrder = 1,
						onClick = function()
							props.run("effect.shadow", preset)
						end,
					}),
					remove = Roact.createElement(Button, {
						text = t("effect_remove"),
						variant = "ghost",
						compact = true,
						layoutOrder = 2,
						onClick = function()
							props.run("effect.shadow", "none")
						end,
					}),
				},
			}),
		},
	})
end

type NeonProps = { t: Translate, run: Run, presets: Presets, colors: { string }, picker: Picker.Handle, layoutOrder: number }

local NEON_OWNER = "neon"

local NeonOutline = Roact.Component:extend("QuadroNeonOutline")

function NeonOutline:init()
	self:setState({ hex = EffectPresets.NEON_COLOR, layers = EffectPresets.NEON_LAYERS })
end

function NeonOutline:render()
	local props: NeonProps = self.props
	local t = props.t
	local hex: string = self.state.hex
	local function pick(typed: string)
		local clean = Stops.parseHex(typed)
		if clean then
			self:setState({ hex = clean })
		end
	end
	local picker = props.picker
	local open = Picker.isOpen(picker.state, NEON_OWNER)
	return block(props.layoutOrder, {
		title = subheading(t("neon_title"), 1),
		hint = caption(t("neon_sub"), 2),
		color = Roact.createElement(Flow, {
			layoutOrder = 3,
			children = {
				hex = field("neonHex", t("neon_color"), hex, theme.sizes.hexFieldWidth, 1, pick),
				swatch = ColorPicker.circle(Picker.shown(picker.state, NEON_OWNER, hex), open, function()
					picker.api.toggle(NEON_OWNER, hex)
				end, 2),
			},
		}),
		picker = if open
			then Roact.createElement(ColorPicker, { picker = picker, t = t, onCommit = pick, chips = props.colors, layoutOrder = 4 })
			else nil,
		intensity = Roact.createElement(Stepper, {
			label = t("neon_intensity"),
			value = self.state.layers,
			min = 1,
			max = EffectPresets.NEON_MAX_LAYERS,
			step = 1,
			layoutOrder = 5,
			onChange = function(value: number)
				self:setState({ layers = value })
			end,
		}),
		presets = if #props.colors > 0
			then presetList(t, props.presets, 6, {
				chips = Roact.createElement(ColorChips.render, { colors = props.colors, onPick = pick, layoutOrder = 1 }),
			})
			else nil,
		actions = Roact.createElement(Flow, {
			layoutOrder = 7,
			children = {
				apply = Roact.createElement(Button, {
					text = t("neon_apply"),
					variant = "primary",
					compact = true,
					layoutOrder = 1,
					onClick = function()
						props.run("effect.neonOutline", hex, self.state.layers)
					end,
				}),
				remove = Roact.createElement(Button, {
					text = t("effect_remove"),
					variant = "ghost",
					compact = true,
					layoutOrder = 2,
					onClick = function()
						props.run("effect.neonOutline", "none")
					end,
				}),
			},
		}),
	})
end

type SliceProps = { t: Translate, slice: SliceEditor.State, api: SliceEditor.Api, layoutOrder: number }

local function NineSlice(props: SliceProps)
	local t = props.t
	local state = props.slice
	local api = props.api
	local target: any = state.target
	local w: number?, h: number? = state.w, state.h
	local rect: { number }?, problem: string? = nil, "slice_error_size"
	if w and h then
		rect, problem = EffectPresets.sliceRect(state.l, state.t, state.r, state.b, w, h)
	end
	local function number(key: string): (typed: string) -> ()
		return function(typed: string)
			local value = tonumber(typed)
			if value ~= nil then
				api.set(key, value)
			end
		end
	end
	local function text(value: number?): string
		return if value == nil then "" else tostring(value)
	end
	local width = theme.sizes.fieldWidth
	local preview: any = nil
	if target ~= nil and rect ~= nil then
		preview = Roact.createElement("ImageLabel", {
			Size = UDim2.fromOffset(theme.sizes.slicePreviewWidth, theme.sizes.slicePreviewHeight),
			BackgroundColor3 = theme.colors.surface,
			BorderSizePixel = 0,
			Image = target.Image,
			ImageRectOffset = target.ImageRectOffset,
			ImageRectSize = target.ImageRectSize,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(rect[1], rect[2], rect[3], rect[4]),
			SliceScale = state.scale / PERCENT,
			LayoutOrder = 3,
		})
	end
	return block(props.layoutOrder, {
		title = subheading(t("slice_title"), 1),
		hint = caption(t("slice_sub"), 2),
		status = if target == nil then caption(t("slice_none"), 3) else nil,
		slicePreview = preview,
		size = Roact.createElement(Flow, {
			layoutOrder = 4,
			children = {
				w = field("sliceW", t("slice_width"), text(w), width, 1, number("w")),
				h = field("sliceH", t("slice_height"), text(h), width, 2, number("h")),
			},
		}),
		margins = Roact.createElement(Flow, {
			layoutOrder = 5,
			children = {
				l = field("sliceL", t("slice_left"), text(state.l), width, 1, number("l")),
				t = field("sliceT", t("slice_top"), text(state.t), width, 2, number("t")),
				r = field("sliceR", t("slice_right"), text(state.r), width, 3, number("r")),
				b = field("sliceB", t("slice_bottom"), text(state.b), width, 4, number("b")),
			},
		}),
		scale = Roact.createElement(Stepper, {
			label = t("slice_scale"),
			value = state.scale,
			min = EffectPresets.SLICE_SCALE_MIN,
			max = EffectPresets.SLICE_SCALE_MAX,
			step = EffectPresets.SLICE_SCALE_STEP,
			suffix = "%",
			editable = true,
			layoutOrder = 6,
			onChange = function(value: number)
				api.set("scale", value)
			end,
		}),
		problem = if problem then caption(t(problem), 7, theme.colors.accentDecline) else nil,
		apply = action(t("slice_apply"), 8, api.apply, rect == nil),
	})
end

local function removeButton(t: Translate, order: number, onClick: () -> ()): any
	return Roact.createElement(Button, {
		text = t("effect_remove"),
		variant = "ghost",
		compact = true,
		layoutOrder = order,
		onClick = onClick,
	})
end

local function actions(order: number, apply: any, remove: any): any
	return Roact.createElement(Flow, { layoutOrder = order, children = { apply = apply, remove = remove } })
end

local function applyButton(text: string, onClick: () -> ()): any
	return Roact.createElement(Button, {
		text = text,
		variant = "primary",
		compact = true,
		layoutOrder = 1,
		onClick = onClick,
	})
end

type MotionProps = { t: Translate, run: Run, more: Presets, layoutOrder: number }

local function firstTagged(tag: string): Instance?
	for _, target in Selection.candidates() do
		if CollectionService:HasTag(target, tag) then
			return target
		end
	end
	return nil
end

local function attributeOr(target: Instance?, name: string, fallback: any): any
	local value = if target then target:GetAttribute(name) else nil
	if value ~= nil and typeof(value) == typeof(fallback) then
		return value
	end
	return fallback
end

local function followSelection(component: any, load: (required: boolean) -> { [string]: any }?)
	component.selectionConnection = SelectionService.SelectionChanged:Connect(function()
		local values = load(true)
		if values then
			component:setState(values)
		end
	end)
end

local function stopFollowing(component: any)
	if component.selectionConnection then
		component.selectionConnection:Disconnect()
		component.selectionConnection = nil
	end
end

local function loadMotion(required: boolean): { [string]: any }?
	local target = firstTagged("QuadroAnimatedGradient")
	if required and target == nil then
		return nil
	end
	local motion = attributeOr(target, "QuadroMotion", EffectPresets.MOTION_DEFAULT)
	return {
		motion = if table.find(EffectPresets.MOTIONS, motion) then motion else EffectPresets.MOTION_DEFAULT,
		speed = tenths(attributeOr(target, "QuadroSpeed", EffectPresets.MOTION_SPEED)),
		range = tenths(attributeOr(target, "QuadroRange", EffectPresets.MOTION_RANGE)),
		pingPong = attributeOr(target, "QuadroPingPong", false),
	}
end

local function loadShine(required: boolean): { [string]: any }?
	local target = firstTagged("QuadroShine")
	if required and target == nil then
		return nil
	end
	return {
		interval = tenths(attributeOr(target, "QuadroShineInterval", EffectPresets.SHINE_INTERVAL)),
		duration = tenths(attributeOr(target, "QuadroShineDuration", EffectPresets.SHINE_DURATION)),
		width = math.round(attributeOr(target, "QuadroShineWidth", EffectPresets.SHINE_WIDTH) * PERCENT),
		angle = attributeOr(target, "QuadroShineAngle", EffectPresets.SHINE_ANGLE),
	}
end

local GradientMotion = Roact.Component:extend("QuadroGradientMotionCard")

function GradientMotion:init()
	self:setState(loadMotion(false) :: { [string]: any })
end

function GradientMotion:didMount()
	followSelection(self, loadMotion)
end

function GradientMotion:willUnmount()
	stopFollowing(self)
end

function GradientMotion:render()
	local props: MotionProps = self.props
	local t = props.t
	local options = {}
	for _, id in EffectPresets.MOTIONS do
		table.insert(options, { id = id, label = t("motion_" .. id) })
	end
	return block(props.layoutOrder, {
		title = subheading(t("motion_title"), 1),
		hint = caption(t("motion_sub"), 2),
		motion = Roact.createElement(Pills, {
			options = options,
			value = self.state.motion,
			layoutOrder = 3,
			onSelect = function(id: string)
				self:setState({ motion = id })
			end,
		}),
		speed = Roact.createElement(Stepper, {
			label = t("motion_speed"),
			value = self.state.speed,
			min = SPEED_MIN,
			max = SPEED_MAX,
			step = SPEED_STEP,
			layoutOrder = 4,
			onChange = function(value: number)
				self:setState({ speed = tenths(value) })
			end,
		}),
		more = Roact.createElement(Disclosure, {
			label = t("more_show"),
			expandedLabel = t("more_hide"),
			expanded = props.more.open,
			onToggle = props.more.toggle,
			layoutOrder = 5,
			children = {
				range = Roact.createElement(Stepper, {
					label = t("motion_range"),
					value = self.state.range,
					min = RANGE_MIN,
					max = RANGE_MAX,
					step = RANGE_STEP,
					layoutOrder = 1,
					onChange = function(value: number)
						self:setState({ range = tenths(value) })
					end,
				}),
				pingPong = Roact.createElement(Toggle, {
					title = t("motion_pingpong"),
					value = self.state.pingPong,
					layoutOrder = 2,
					onChange = function(value: boolean)
						self:setState({ pingPong = value })
					end,
				}),
			},
		}),
		actions = actions(
			6,
			applyButton(t("motion_apply"), function()
				props.run("effect.animatedGradient", self.state.motion, self.state.speed, self.state.range, self.state.pingPong)
			end),
			removeButton(t, 2, function()
				props.run("effect.animatedGradient", "none")
			end)
		),
	})
end

local ShineSweep = Roact.Component:extend("QuadroShineSweepCard")

function ShineSweep:init()
	self:setState(loadShine(false) :: { [string]: any })
end

function ShineSweep:didMount()
	followSelection(self, loadShine)
end

function ShineSweep:willUnmount()
	stopFollowing(self)
end

function ShineSweep:render()
	local props: MotionProps = self.props
	local t = props.t
	local function stepper(key: string, label: string, min: number, max: number, step: number, order: number, suffix: string?, round: boolean): any
		return Roact.createElement(Stepper, {
			label = t(label),
			value = self.state[key],
			min = min,
			max = max,
			step = step,
			suffix = suffix,
			layoutOrder = order,
			onChange = function(value: number)
				self:setState({ [key] = if round then tenths(value) else value })
			end,
		})
	end
	return block(props.layoutOrder, {
		title = subheading(t("shine_title"), 1),
		hint = caption(t("shine_sub"), 2),
		interval = stepper("interval", "shine_interval", INTERVAL_MIN, INTERVAL_MAX, INTERVAL_STEP, 3, "s", true),
		more = Roact.createElement(Disclosure, {
			label = t("more_show"),
			expandedLabel = t("more_hide"),
			expanded = props.more.open,
			onToggle = props.more.toggle,
			layoutOrder = 4,
			children = {
				duration = stepper("duration", "shine_duration", DURATION_MIN, DURATION_MAX, DURATION_STEP, 1, "s", true),
				width = stepper("width", "shine_width", WIDTH_MIN, WIDTH_MAX, WIDTH_STEP, 2, "%", false),
				angle = stepper("angle", "shine_angle", ANGLE_MIN, ANGLE_MAX, ANGLE_STEP, 3, "°", false),
			},
		}),
		actions = actions(
			5,
			applyButton(t("shine_apply"), function()
				props.run("effect.shine", self.state.interval, self.state.duration, self.state.width / PERCENT, self.state.angle)
			end),
			removeButton(t, 2, function()
				props.run("effect.shine", "none")
			end)
		),
	})
end

local function Effects(props: Props)
	local t = props.t
	local editorState: GradientEditor.State = props.state.gradientEditor or GradientEditor.initial()
	local open: { [string]: boolean } = props.state.disclosures or {}
	local function presets(id: string): Presets
		return {
			open = open[id] == true,
			toggle = function()
				props.disclose(id, open[id] ~= true)
			end,
		}
	end
	local function fold(id: string, section: { [string]: any }): { [string]: any }
		return Section.folded(props.openSection, props.toggleSection, id, section)
	end
	return Roact.createFragment({
		studio = Roact.createElement(
			GradientStudio,
			fold("studio", {
				editor = editorState,
				api = props.editor,
				picker = props.picker,
				t = t,
				libraryColors = libraryColors(props.state),
				saveData = props.saveData,
				colors = presets("studioColors"),
				layoutOrder = 1,
			})
		),
		library = Roact.createElement(
			Gradients,
			fold("library", {
				state = props.state,
				t = t,
				plugin = props.plugin,
				run = props.run,
				saveData = props.saveData,
				list = presets("libraryPresets"),
				more = presets("libraryMore"),
				layoutOrder = 2,
			})
		),
		strokeGlow = Roact.createElement(Section, fold("strokeGlow", {
			title = t("effects_stroke_glow"),
			layoutOrder = 3,
			children = {
				title = subheading(t("stroke_gradient_title"), 2),
				hint = caption(t("stroke_gradient_sub"), 3),
				apply = action(t("stroke_gradient_apply"), 4, function()
					props.run("effect.gradientStroke", editorState.data)
				end),
				neon = Roact.createElement(NeonOutline, {
					t = t,
					run = props.run,
					presets = presets("neonColors"),
					colors = ColorChips.merge({ editorState.recent, libraryColors(props.state) }),
					picker = props.picker,
					layoutOrder = 5,
				}),
			},
		})),
		shadow = Roact.createElement(
			ShadowStudio,
			fold("shadow", {
				t = t,
				run = props.run,
				presets = presets("shadowPresets"),
				layoutOrder = 4,
			})
		),
		motion = Roact.createElement(Section, fold("motion", {
			title = t("effects_motion"),
			layoutOrder = 5,
			children = {
				gradientMotion = Roact.createElement(GradientMotion, { t = t, run = props.run, more = presets("motionMore"), layoutOrder = 2 }),
				shine = Roact.createElement(ShineSweep, { t = t, run = props.run, more = presets("shineMore"), layoutOrder = 3 }),
			},
		})),
		textMask = Roact.createElement(Section, fold("textMask", {
			title = t("effects_text_mask"),
			layoutOrder = 6,
			children = {
				mask = Roact.createElement(FadingMask, { t = t, run = props.run, layoutOrder = 2 }),
				hollow = block(3, {
					title = subheading(t("hollow_title"), 1),
					hint = caption(t("hollow_sub"), 2),
					apply = action(t("hollow_apply"), 3, function()
						props.run("effect.hollowText")
					end),
				}),
			},
		})),
		nineSlice = Roact.createElement(Section, fold("nineSlice", {
			title = t("effects_nine_slice"),
			layoutOrder = 7,
			children = {
				helper = Roact.createElement(NineSlice, {
					t = t,
					slice = props.state.sliceEditor or SliceEditor.initial(),
					api = props.slice,
					layoutOrder = 2,
				}),
			},
		})),
	})
end

return Effects
