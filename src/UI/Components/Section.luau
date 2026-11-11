--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Card = require(script.Parent.Card)
local Heading = require(script.Parent.Heading)

type Props = {
	title: string?,
	subtitle: string?,
	accessory: any?,
	layoutOrder: number?,
	open: boolean?,
	onToggle: (() -> ())?,
	children: { [any]: any },
}

local CHEVRON = "›"
local CHEVRON_OPEN = 90

local Section = Roact.Component:extend("QuadroSection")

function Section:init()
	self.frame = Roact.createRef()
end

function Section:didUpdate(previous: Props)
	local props: Props = self.props
	if props.onToggle == nil or props.open ~= true or previous.open == true then
		return
	end
	task.defer(function()
		task.wait()
		local frame = self.frame:getValue() :: GuiObject?
		local scroller = if frame then frame:FindFirstAncestorWhichIsA("ScrollingFrame") else nil
		if frame == nil or scroller == nil then
			return
		end
		local scale = scroller:FindFirstChildOfClass("UIScale")
		local factor = if scale and scale.Scale > 0 then scale.Scale else 1
		local delta = (frame.AbsolutePosition.Y - scroller.AbsolutePosition.Y) / factor
		scroller.CanvasPosition = Vector2.new(0, math.max(scroller.CanvasPosition.Y + delta - theme.spacing.sm, 0))
	end)
end

local function header(props: Props): any
	local open = props.open == true
	return Roact.createElement("TextButton", {
		Size = UDim2.new(1, 0, 0, theme.sizes.row),
		BackgroundColor3 = theme.colors.surface,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 0,
		[Roact.Event.MouseEnter] = function(button: TextButton)
			button.BackgroundTransparency = 0
		end,
		[Roact.Event.MouseLeave] = function(button: TextButton)
			button.BackgroundTransparency = 1
		end,
		[Roact.Event.Activated] = function()
			local toggle = props.onToggle
			if toggle then
				toggle()
			end
		end,
	}, {
		corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.spacing.sm),
			PaddingRight = UDim.new(0, theme.spacing.sm),
		}),
		title = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, -theme.sizes.row, 1, 0),
			BackgroundTransparency = 1,
			Text = props.title or "",
			TextColor3 = theme.colors.text,
			Font = theme.typography.title.font,
			TextSize = theme.typography.title.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		chevron = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(theme.sizes.chip, theme.sizes.chip),
			BackgroundTransparency = 1,
			Rotation = if open then CHEVRON_OPEN else 0,
			Text = CHEVRON,
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.title.font,
			TextSize = theme.typography.title.size,
		}),
	})
end

function Section.folded(openIds: { [string]: boolean }, toggle: (id: string) -> (), id: string, props: { [string]: any }): { [string]: any }
	props.open = openIds[id] == true
	props.onToggle = function()
		toggle(id)
	end
	return props
end

function Section:render()
	local props: Props = self.props
	local accordion = props.onToggle ~= nil
	local children: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.md),
		}),
	}
	if accordion then
		children.heading = header(props)
		if props.open == true and props.subtitle ~= nil then
			children.subtitle = Roact.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = props.subtitle,
				TextColor3 = theme.colors.textMuted,
				Font = theme.typography.caption.font,
				TextSize = theme.typography.caption.size,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				LayoutOrder = 1,
			})
		end
	elseif props.title ~= nil then
		children.heading = Roact.createElement(Heading, {
			title = props.title,
			subtitle = props.subtitle,
			accessory = props.accessory,
			layoutOrder = 1,
		})
	end
	if not accordion or props.open == true then
		for key, child in props.children do
			children[key] = child
		end
	end
	return Roact.createElement(Card, {
		layoutOrder = props.layoutOrder,
		padding = if accordion then theme.spacing.md else nil,
		ref = self.frame,
		children = children,
	})
end

return Section
