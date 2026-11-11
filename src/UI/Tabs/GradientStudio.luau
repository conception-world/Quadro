--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Badge = require(script.Parent.Parent.Components.Badge)
local Button = require(script.Parent.Parent.Components.Button)
local ColorChips = require(script.Parent.Parent.Components.ColorChips)
local Disclosure = require(script.Parent.Parent.Components.Disclosure)
local field = require(script.Parent.Parent.Components.Field)
local Flow = require(script.Parent.Parent.Components.Flow)
local Pills = require(script.Parent.Parent.Components.Pills)
local Section = require(script.Parent.Parent.Components.Section)
local Stepper = require(script.Parent.Parent.Components.Stepper)
local Codec = require(script.Parent.Parent.Parent.Gradients.Codec)
local Library = require(script.Parent.Parent.Parent.Gradients.Library)
local Stops = require(script.Parent.Parent.Parent.Gradients.Stops)
local GradientEditor = require(script.Parent.Parent.Parent.App.GradientEditor)
local Picker = require(script.Parent.Parent.Parent.App.ColorPicker)
local ColorPicker = require(script.Parent.Parent.Components.ColorPicker)

type Translate = (key: string, ...any) -> string

type Props = {
	editor: GradientEditor.State,
	api: GradientEditor.Api,
	picker: Picker.Handle,
	t: Translate,
	libraryColors: { string },
	saveData: (data: Codec.Data) -> (),
	layoutOrder: number,
	open: boolean,
	onToggle: () -> (),
	colors: { open: boolean, toggle: () -> () },
}

type TrackProps = {
	kind: GradientEditor.Kind,
	points: { any },
	selected: number?,
	canAdd: boolean,
	dragging: boolean,
	api: GradientEditor.Api,
	layoutOrder: number,
}

local ROTATION_MIN = -180
local ROTATION_MAX = 180
local ROTATION_STEP = 15
local INSET = theme.sizes.stopMarkerActive / 2
local SIDE = theme.sizes.row + theme.spacing.sm

local function stopOwner(editor: GradientEditor.State, index: number): string
	return "stop:" .. editor.target .. ":" .. index
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

local Track = Roact.Component:extend("QuadroStopTrack")

function Track:init()
	self.rail = Roact.createRef()
end

function Track:fraction(x: number): number?
	local rail = self.rail:getValue() :: Frame?
	if rail == nil or rail.AbsoluteSize.X <= 0 then
		return nil
	end
	return (x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X
end

function Track:nearest(x: number): number?
	local props: TrackProps = self.props
	local rail = self.rail:getValue() :: Frame?
	local t = self:fraction(x)
	if rail == nil or t == nil then
		return nil
	end
	local best: number? = nil
	local bestDistance = theme.sizes.stopMarkerActive
	for index, point in props.points do
		local time = if props.kind == "color" then point.t else point[1]
		local distance = math.abs(time - t) * rail.AbsoluteSize.X
		if distance <= bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

function Track:willUnmount()
	if (self.props :: TrackProps).dragging then
		self.props.api.dragCancel()
	end
end

function Track:render()
	local props: TrackProps = self.props
	local markers: { [any]: any } = {}
	for index, point in props.points do
		local active = props.selected == index
		local size = if active then theme.sizes.stopMarkerActive else theme.sizes.stopMarker
		local time: number, fill: Color3, transparency: number
		if props.kind == "color" then
			time, fill, transparency = point.t, Color3.fromHex(point.c), 0
		else
			time, fill, transparency = point[1], theme.colors.text, point[2]
		end
		markers["stop" .. index] = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(time, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = fill,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = if active then 3 else 2,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			stroke = Roact.createElement("UIStroke", {
				Color = if active then theme.colors.accentPrimary else theme.colors.text,
				Thickness = if active then theme.sizes.markerStrokeActive else theme.sizes.markerStroke,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, theme.sizes.stopTrack),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		track = Roact.createElement("TextButton", {
			Size = UDim2.new(1, -SIDE, 1, 0),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			[Roact.Event.InputBegan] = function(_: TextButton, input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				props.api.dragEnd()
				local index = self:nearest(input.Position.X)
				if index then
					props.api.dragBegin(props.kind, index, self.rail:getValue())
				end
			end,
			[Roact.Event.InputEnded] = function(_: TextButton, input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					props.api.dragEnd()
				end
			end,
		}, {
			line = Roact.createElement("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, INSET, 0.5, 0),
				Size = UDim2.new(1, -2 * INSET, 0, theme.sizes.trackLine),
				BackgroundColor3 = theme.colors.surfaceActive,
				BorderSizePixel = 0,
			}),
			rail = Roact.createElement("Frame", {
				Position = UDim2.fromOffset(INSET, 0),
				Size = UDim2.new(1, -2 * INSET, 1, 0),
				BackgroundTransparency = 1,
				[Roact.Ref] = self.rail,
			}, markers),
		}),
		add = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(theme.sizes.row, theme.sizes.stopTrack),
			BackgroundTransparency = 1,
		}, {
			button = Roact.createElement(Button, {
				text = "+",
				variant = "ghost",
				compact = true,
				size = UDim2.fromScale(1, 1),
				disabled = not props.canAdd,
				onClick = function()
					props.api.addStop(props.kind)
				end,
			}),
		}),
	})
end

local function chips(props: Props, order: number): any
	local list = ColorChips.merge({ props.editor.recent, props.libraryColors })
	if #list == 0 then
		return nil
	end
	return Roact.createElement(Disclosure, {
		label = props.t("presets_show"),
		expandedLabel = props.t("presets_hide"),
		expanded = props.colors.open,
		onToggle = props.colors.toggle,
		layoutOrder = order,
		children = {
			chips = Roact.createElement(ColorChips.render, { colors = list, onPick = props.api.setColor, layoutOrder = 1 }),
		},
	})
end

local function stopPanel(props: Props, data: Codec.Data, picked: GradientEditor.Picked, order: number): any
	local t = props.t
	local api = props.api
	local point = Stops.list(data, picked.kind)[picked.index]
	if point == nil then
		return nil
	end
	local time = if picked.kind == "color" then point.t else point[1]
	local fields: { [any]: any } = {}
	local picker: any = nil
	if picked.kind == "color" then
		local hex: string = point.c
		local r, g, b = Stops.rgb(hex)
		local function channel(which: number): (typed: string) -> ()
			return function(typed: string)
				local value = tonumber(typed)
				if value == nil then
					return
				end
				local channels = { r, g, b }
				channels[which] = value
				api.setColor(Stops.hex(channels[1], channels[2], channels[3]))
			end
		end
		local owner = stopOwner(props.editor, picked.index)
		local open = Picker.isOpen(props.picker.state, owner)
		fields.hex = field("hexBox", t("studio_hex"), hex, theme.sizes.hexFieldWidth, 1, api.setColor)
		fields.swatch = ColorPicker.circle(Picker.shown(props.picker.state, owner, hex), open, function()
			props.picker.api.toggle(owner, hex)
		end, 2)
		fields.r = field("rBox", "R", tostring(r), theme.sizes.fieldWidth, 3, channel(1))
		fields.g = field("gBox", "G", tostring(g), theme.sizes.fieldWidth, 4, channel(2))
		fields.b = field("bBox", "B", tostring(b), theme.sizes.fieldWidth, 5, channel(3))
		if open then
			picker = Roact.createElement(ColorPicker, {
				picker = props.picker,
				t = t,
				onCommit = api.setColor,
				subject = function(): any
					return GradientEditor.subject(props.editor.target)
				end,
				chips = ColorChips.merge({ props.editor.recent, props.libraryColors }),
				layoutOrder = 3,
			})
		end
	else
		fields.value = field("valueBox", t("studio_value"), tostring(point[2]), theme.sizes.fieldWidth, 1, function(typed: string)
			local value = tonumber(typed)
			if value ~= nil then
				api.setValue(math.clamp(value, 0, 1))
			end
		end)
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.sm),
		}),
		info = caption(t("studio_stop", picked.index, math.round(time * 100)), 1),
		fields = Roact.createElement(Flow, { layoutOrder = 2, children = fields }),
		picker = picker,
		chips = if picked.kind == "color" then chips(props, 4) else nil,
		remove = Roact.createElement(Flow, {
			layoutOrder = 5,
			children = {
				remove = Roact.createElement(Button, {
					text = t("studio_remove"),
					variant = "ghost",
					compact = true,
					disabled = Stops.isEndpoint(data, picked.kind, picked.index),
					onClick = api.removeStop,
				}),
			},
		}),
	})
end

local function strip(data: Codec.Data, order: number): any
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, theme.sizes.gradientStrip),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		preview = Roact.createElement("Frame", {
			Position = UDim2.fromOffset(INSET, 0),
			Size = UDim2.new(1, -(SIDE + 2 * INSET), 1, 0),
			BackgroundColor3 = theme.colors.gradientBase,
			BorderSizePixel = 0,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.md) }),
			gradient = Roact.createElement("UIGradient", {
				Color = Library.colorSequence(data.color),
				Transparency = Library.numberSequence(data.transparency),
			}),
		}),
	})
end

local function typeGroup(props: Props, order: number): { [any]: any }
	local t = props.t
	local options = {}
	for _, name in Library.GRADIENT_TYPES do
		table.insert(options, { id = name, label = t("type_" .. string.lower(name)) })
	end
	return {
		typeHead = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, theme.sizes.badgeHeight),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {
			layout = Roact.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, theme.spacing.sm),
			}),
			label = Roact.createElement("TextLabel", {
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Text = t("studio_type"),
				TextColor3 = theme.colors.text,
				Font = theme.typography.body.font,
				TextSize = theme.typography.body.size,
				LayoutOrder = 1,
			}),
			beta = Roact.createElement(Badge, {
				text = t("studio_beta"),
				color = theme.colors.accentWarning,
				layoutOrder = 2,
			}),
		}),
		typePills = Roact.createElement(Pills, {
			options = options,
			value = props.editor.gradientType,
			layoutOrder = order + 1,
			onSelect = props.api.setType,
		}),
		typeWarning = caption(t("studio_type_warning"), order + 2),
	}
end

local function GradientStudio(props: Props)
	local t = props.t
	local editor = props.editor
	local api = props.api
	local children: { [any]: any } = {
		target = Roact.createElement(Pills, {
			options = {
				{ id = "fill", label = t("studio_fill") },
				{ id = "stroke", label = t("studio_stroke") },
			},
			value = editor.target,
			layoutOrder = 2,
			onSelect = api.setTarget,
		}),
	}
	local data = editor.data
	if editor.status == "none" or (editor.status == "ready" and data == nil) then
		children.status = caption(t("studio_none"), 3)
	elseif editor.status == "missing" then
		children.status = caption(t(if editor.target == "stroke" then "studio_missing_stroke" else "studio_missing_fill"), 3)
		children.create = Roact.createElement(Flow, {
			layoutOrder = 4,
			children = {
				create = Roact.createElement(Button, {
					text = t("studio_create"),
					variant = "primary",
					compact = true,
					onClick = api.create,
				}),
			},
		})
	elseif data then
		local selected = editor.selected
		local shown = data
		if selected and selected.kind == "color" and Picker.isOpen(props.picker.state, stopOwner(editor, selected.index)) then
			shown = Stops.set(data, "color", selected.index, Picker.hex(props.picker.state))
		end
		children.strip = strip(shown, 3)
		children.colorLabel = caption(t("studio_colors"), 4)
		children.colors = Roact.createElement(Track, {
			kind = "color",
			points = shown.color,
			selected = if selected and selected.kind == "color" then selected.index else nil,
			canAdd = #data.color < Codec.MAX_KEYPOINTS,
			dragging = editor.dragging ~= nil and editor.dragging.kind == "color",
			api = api,
			layoutOrder = 5,
		})
		children.alphaLabel = caption(t("studio_transparency"), 6)
		children.alphas = Roact.createElement(Track, {
			kind = "transparency",
			points = data.transparency,
			selected = if selected and selected.kind == "transparency" then selected.index else nil,
			canAdd = #data.transparency < Codec.MAX_KEYPOINTS,
			dragging = editor.dragging ~= nil and editor.dragging.kind == "transparency",
			api = api,
			layoutOrder = 7,
		})
		if selected then
			children.stop = stopPanel(props, data, selected, 8)
		end
		children.rotation = Roact.createElement(Stepper, {
			label = t("studio_rotation"),
			value = data.rotation,
			min = ROTATION_MIN,
			max = ROTATION_MAX,
			step = ROTATION_STEP,
			suffix = "°",
			editable = true,
			layoutOrder = 9,
			onChange = api.setRotation,
		})
		if Library.typeSupported then
			for key, element in typeGroup(props, 10) do
				children[key] = element
			end
		end
		children.actions = Roact.createElement(Flow, {
			layoutOrder = 13,
			children = {
				save = Roact.createElement(Button, {
					text = t("studio_save"),
					variant = "primary",
					compact = true,
					onClick = function()
						props.saveData(data)
					end,
				}),
			},
		})
	end
	return Roact.createElement(Section, {
		title = t("effects_gradient_studio"),
		subtitle = t("studio_sub"),
		layoutOrder = props.layoutOrder,
		open = props.open,
		onToggle = props.onToggle,
		children = children,
	})
end

return GradientStudio
