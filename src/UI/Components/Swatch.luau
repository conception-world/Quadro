--!strict
local TweenService = game:GetService("TweenService")
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Codec = require(script.Parent.Parent.Parent.Gradients.Codec)

local SETTLE_CHIP = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE = 0.25

type Props = {
	data: Codec.Data,
	label: string,
	animate: boolean,
	renaming: boolean,
	onClick: () -> (),
	onRightClick: () -> (),
	onRename: (text: string?) -> (),
	layoutOrder: number?,
}

local Swatch = Roact.Component:extend("QuadroSwatch")

function Swatch:init()
	self.gradientRef = Roact.createRef()
	self.boxRef = Roact.createRef()
	self.tween = nil :: Tween?
end

function Swatch:slideTo(delta: number)
	local gradient = self.gradientRef:getValue() :: UIGradient?
	if not gradient then
		return
	end
	local props: Props = self.props
	if self.tween then
		self.tween:Cancel()
	end
	local base = Vector2.new(props.data.offset[1], props.data.offset[2])
	local target = Vector2.new(math.clamp(base.X + delta, -1, 1), base.Y)
	local tween = TweenService:Create(gradient, SETTLE_CHIP, { Offset = target })
	self.tween = tween
	tween:Play()
end

function Swatch:focusRename()
	local box = self.boxRef:getValue() :: TextBox?
	if box and self.props.renaming then
		box:CaptureFocus()
	end
end

function Swatch:didMount()
	self:focusRename()
end

function Swatch:didUpdate(previous: { renaming: boolean })
	if self.props.renaming and not previous.renaming then
		self:focusRename()
	end
end

function Swatch:willUnmount()
	if self.tween then
		self.tween:Cancel()
	end
end

function Swatch:render()
	local props: Props = self.props
	local data = props.data
	local colorPoints: { ColorSequenceKeypoint } = {}
	for _, stop in data.color do
		table.insert(colorPoints, ColorSequenceKeypoint.new(stop.t, Color3.fromHex(stop.c)))
	end
	local transparencyPoints: { NumberSequenceKeypoint } = {}
	for _, point in data.transparency do
		table.insert(transparencyPoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	local sizes = theme.sizes
	local labelPosition = UDim2.fromOffset(0, sizes.swatchHeight + theme.spacing.tight)
	local label: any
	if props.renaming then
		label = Roact.createElement("TextBox", {
			Size = UDim2.new(1, 0, 0, sizes.swatchLabel - theme.spacing.tight),
			Position = labelPosition,
			BackgroundColor3 = theme.colors.surface,
			BorderSizePixel = 0,
			Text = data.name,
			ClearTextOnFocus = false,
			TextColor3 = theme.colors.text,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			[Roact.Ref] = self.boxRef,
			[Roact.Event.FocusLost] = function(box: TextBox, enterPressed: boolean)
				props.onRename(if enterPressed then box.Text else nil)
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		})
	else
		label = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, sizes.swatchLabel),
			Position = labelPosition,
			BackgroundTransparency = 1,
			Text = props.label,
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	return Roact.createElement("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		face = Roact.createElement("TextButton", {
			Size = UDim2.new(1, 0, 0, sizes.swatchHeight),
			BackgroundColor3 = theme.colors.gradientBase,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			[Roact.Event.Activated] = props.onClick,
			[Roact.Event.MouseButton2Click] = props.onRightClick,
			[Roact.Event.MouseEnter] = function()
				if props.animate then
					self:slideTo(SLIDE)
				end
			end,
			[Roact.Event.MouseLeave] = function()
				if props.animate then
					self:slideTo(0)
				end
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.md) }),
			gradient = Roact.createElement("UIGradient", {
				Color = ColorSequence.new(colorPoints),
				Transparency = NumberSequence.new(transparencyPoints),
				Rotation = data.rotation,
				Offset = Vector2.new(data.offset[1], data.offset[2]),
				[Roact.Ref] = self.gradientRef,
			}),
		}),
		label = label,
	})
end

return Swatch
