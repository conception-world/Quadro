--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	text: string,
	color: Color3,
	layoutOrder: number?,
	backgroundColor: Color3?,
}

local function Badge(props: Props)
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = props.backgroundColor or theme.colors.surface,
		BorderSizePixel = 0,
	}, {
		corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, theme.radius.pill),
		}),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.spacing.md),
			PaddingRight = UDim.new(0, theme.spacing.md),
		}),
		layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, theme.spacing.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		dot = Roact.createElement("Frame", {
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = props.color,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, {
			corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		label = Roact.createElement("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = props.text,
			TextColor3 = theme.colors.text,
			Font = theme.typography.label.font,
			TextSize = theme.typography.label.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		}),
	})
end

return Badge
