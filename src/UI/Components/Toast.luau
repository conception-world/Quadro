--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	text: string,
	kind: string,
	layoutOrder: number?,
}

local KIND_COLORS: { [string]: Color3 } = {
	info = theme.colors.accentInfo,
	success = theme.colors.accentAccept,
	warning = theme.colors.accentWarning,
	error = theme.colors.accentDecline,
}

local function Toast(props: Props)
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(0, theme.sizes.toastHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.colors.surface,
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
			Size = UDim2.fromOffset(theme.sizes.toastDot, theme.sizes.toastDot),
			BackgroundColor3 = KIND_COLORS[props.kind] or theme.colors.accentInfo,
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
			Font = theme.typography.body.font,
			TextSize = theme.typography.body.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		}),
	})
end

return Toast
