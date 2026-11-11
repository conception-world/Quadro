--!strict
local AssetService = game:GetService("AssetService")
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)
local ColorChips = require(script.Parent.ColorChips)
local field = require(script.Parent.Field)
local Flow = require(script.Parent.Flow)
local ColorMath = require(script.Parent.Parent.Parent.ColorMath)
local Picker = require(script.Parent.Parent.Parent.App.ColorPicker)

type Translate = (key: string, ...any) -> string

type Props = {
	picker: Picker.Handle,
	t: Translate,
	onCommit: (hex: string) -> (),
	subject: (() -> any)?,
	chips: { string }?,
	layoutOrder: number?,
}

local WHEEL = theme.sizes.pickerWheel
local SLIDER = theme.sizes.pickerSlider
local MARKER = theme.sizes.pickerMarker
local SWATCH = theme.sizes.pickerSwatch
local RING = theme.sizes.markerStrokeActive
local OUTLINE = theme.sizes.chipStroke

local editable: EditableImage? = nil
local unavailable = false

local function wheelContent(): Content?
	if editable == nil and not unavailable then
		local ok, made = pcall(function(): EditableImage
			local image = AssetService:CreateEditableImage({ Size = Vector2.new(WHEEL, WHEEL) })
			image:WritePixelsBuffer(Vector2.zero, Vector2.new(WHEEL, WHEEL), ColorMath.wheel(WHEEL))
			return image
		end)
		if ok and made then
			editable = made
		else
			unavailable = true
			warn("[Quadro] color wheel unavailable: " .. tostring(made))
		end
	end
	return if editable then Content.fromObject(editable) else nil
end

local function round(): any
	return Roact.createElement("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function ring(position: UDim2, fill: Color3): any
	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(MARKER, MARKER),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 3,
	}, {
		corner = round(),
		stroke = Roact.createElement("UIStroke", {
			Color = theme.colors.text,
			Thickness = RING,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		outline = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * RING, 1, 2 * RING),
			BackgroundTransparency = 1,
			Active = false,
		}, {
			corner = round(),
			stroke = Roact.createElement("UIStroke", {
				Color = theme.colors.background,
				Thickness = OUTLINE,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	})
end

local function disc(color: Color3, order: number, onClick: (() -> ())?): any
	return Roact.createElement(if onClick then "TextButton" else "Frame", {
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		LayoutOrder = order,
		AutoButtonColor = if onClick then false else nil,
		Text = if onClick then "" else nil,
		[Roact.Event.Activated] = onClick,
	}, {
		corner = round(),
		stroke = Roact.createElement("UIStroke", {
			Color = theme.colors.stroke,
			Thickness = OUTLINE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

local ColorPicker = Roact.Component:extend("QuadroColorPicker")

function ColorPicker.circle(hex: string, active: boolean, onClick: () -> (), order: number): any
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(theme.sizes.chip, theme.sizes.fieldHeight),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		dot = Roact.createElement("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(theme.sizes.chip, theme.sizes.chip),
			BackgroundColor3 = Color3.fromHex(hex),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			[Roact.Event.Activated] = onClick,
		}, {
			corner = round(),
			stroke = Roact.createElement("UIStroke", {
				Color = if active then theme.colors.accentPrimary else theme.colors.stroke,
				Thickness = if active then theme.sizes.markerStrokeActive else theme.sizes.chipStroke,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	})
end

function ColorPicker.release()
	if editable then
		editable:Destroy()
		editable = nil
	end
end

function ColorPicker:init()
	self.handlers = {
		commit = function(hex: string)
			if self:identity() == self.subject then
				self.props.onCommit(hex)
			end
		end,
	} :: Picker.Handlers
	self.unbind = nil :: (() -> ())?
end

function ColorPicker:identity(): any
	local subject = (self.props :: Props).subject
	return if subject then subject() else nil
end

function ColorPicker:attach()
	local props: Props = self.props
	if self.unbind then
		self.unbind()
	end
	self.unbind = props.picker.api.bind(props.picker.state.owner, self.handlers)
	self.owner = props.picker.state.owner
	self.subject = self:identity()
end

function ColorPicker:didMount()
	self:attach()
end

function ColorPicker:didUpdate()
	if self.owner ~= self.props.picker.state.owner then
		self:attach()
	elseif self:identity() ~= self.subject then
		task.defer(self.props.picker.api.release, self.owner, true)
	end
end

function ColorPicker:willUnmount()
	if self.unbind then
		self.unbind()
		self.unbind = nil
	end
	task.defer(self.props.picker.api.release, self.owner)
end

function ColorPicker:render()
	local props: Props = self.props
	local t = props.t
	local state = props.picker.state
	local api = props.picker.api
	local hex = Picker.hex(state)
	local color = Color3.fromHex(hex)
	local x, y = ColorMath.point(state.h, state.s)
	local hr, hg, hb = ColorMath.toRgb(state.h, state.s, 1)
	local function press(kind: Picker.Kind): (GuiObject, InputObject) -> ()
		return function(area: GuiObject, input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				api.dragBegin(kind, area)
				api.dragTo(input.Position.X, input.Position.Y)
			end
		end
	end
	local function release(_: GuiObject, input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			api.dragEnd()
		end
	end
	local recent = ColorChips.merge({ state.recent, props.chips or {} })
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.colors.background,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.md) }),
		padding = Roact.createElement("UIPadding", {
			PaddingTop = UDim.new(0, theme.spacing.sm),
			PaddingBottom = UDim.new(0, theme.spacing.sm),
			PaddingLeft = UDim.new(0, theme.spacing.sm),
			PaddingRight = UDim.new(0, theme.spacing.sm),
		}),
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.sm),
		}),
		header = Roact.createElement(Flow, {
			layoutOrder = 1,
			children = {
				swatches = Roact.createElement("Frame", {
					Size = UDim2.fromOffset(0, theme.sizes.fieldHeight),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				}, {
					layout = Roact.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, theme.spacing.tight),
					}),
					old = disc(Color3.fromHex(state.original), 1, function()
						api.setHex(state.original)
					end),
					new = disc(color, 2, nil),
				}),
				hex = field("pickerHex", t("studio_hex"), hex, theme.sizes.hexFieldWidth, 2, api.setHex),
				ok = Roact.createElement(Button, {
					text = t("picker_ok"),
					variant = "primary",
					compact = true,
					layoutOrder = 3,
					onClick = function()
						api.commit(self.handlers)
					end,
				}),
				cancel = Roact.createElement(Button, {
					text = t("picker_cancel"),
					variant = "ghost",
					compact = true,
					layoutOrder = 4,
					onClick = api.cancel,
				}),
			},
		}),
		body = Roact.createElement("Frame", {
			Size = UDim2.fromOffset(WHEEL + theme.spacing.md + SLIDER, WHEEL),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			wheel = Roact.createElement("ImageLabel", {
				Size = UDim2.fromOffset(WHEEL, WHEEL),
				BackgroundTransparency = 1,
				ImageContent = wheelContent(),
				Active = true,
				[Roact.Event.InputBegan] = press("wheel"),
				[Roact.Event.InputEnded] = release,
			}, {
				shade = Roact.createElement("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = theme.colors.shade,
					BackgroundTransparency = state.v,
					BorderSizePixel = 0,
					Active = false,
					ZIndex = 2,
				}, {
					corner = round(),
					stroke = Roact.createElement("UIStroke", {
						Color = theme.colors.stroke,
						Thickness = OUTLINE,
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					}),
				}),
				marker = ring(UDim2.fromScale(0.5 + x / 2, 0.5 + y / 2), color),
			}),
			value = Roact.createElement("Frame", {
				Position = UDim2.fromOffset(WHEEL + theme.spacing.md, 0),
				Size = UDim2.fromOffset(SLIDER, WHEEL),
				BackgroundColor3 = theme.colors.gradientBase,
				BorderSizePixel = 0,
				Active = true,
				[Roact.Event.InputBegan] = press("value"),
				[Roact.Event.InputEnded] = release,
			}, {
				corner = round(),
				stroke = Roact.createElement("UIStroke", {
					Color = theme.colors.stroke,
					Thickness = OUTLINE,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				gradient = Roact.createElement("UIGradient", {
					Color = ColorSequence.new(Color3.new(hr, hg, hb), theme.colors.shade),
					Rotation = 90,
				}),
				marker = ring(UDim2.fromScale(0.5, 1 - state.v), color),
			}),
		}),
		recent = if #recent > 0 then Roact.createElement(ColorChips.render, { colors = recent, onPick = api.setHex, layoutOrder = 3 }) else nil,
	})
end

return ColorPicker
