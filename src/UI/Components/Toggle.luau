--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	title: string,
	subtitle: string?,
	value: boolean,
	onChange: (value: boolean) -> (),
	layoutOrder: number?,
}

local function Toggle(props: Props)
	local sizes = theme.sizes
	local inset = sizes.toggleKnobInset
	local travel = sizes.toggleWidth - sizes.toggleKnob - inset * 2
	local texts: { [string]: any } = {
		layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, sizes.toggleTrackGap),
		}),
		title = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.typography.body.size + sizes.toggleTitleExtra),
			BackgroundTransparency = 1,
			Text = props.title,
			TextColor3 = theme.colors.text,
			Font = theme.typography.body.font,
			TextSize = theme.typography.body.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
		}),
	}
	if props.subtitle ~= nil then
		texts.subtitle = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.typography.caption.size * 3),
			BackgroundTransparency = 1,
			Text = props.subtitle,
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, if props.subtitle ~= nil then sizes.toggleRowTall else sizes.row),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		texts = Roact.createElement("Frame", {
			Size = UDim2.new(1, -(sizes.toggleWidth + theme.spacing.md), 1, 0),
			BackgroundTransparency = 1,
		}, texts),
		track = Roact.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(sizes.toggleWidth, sizes.toggleHeight),
			BackgroundColor3 = if props.value then theme.colors.accentPrimary else theme.colors.surfaceActive,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			[Roact.Event.Activated] = function()
				props.onChange(not props.value)
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.pill) }),
			knob = Roact.createElement("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, if props.value then inset + travel else inset, 0.5, 0),
				Size = UDim2.fromOffset(sizes.toggleKnob, sizes.toggleKnob),
				BackgroundColor3 = theme.colors.text,
				BorderSizePixel = 0,
			}, {
				corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.pill) }),
			}),
		}),
	})
end

return Toggle
