--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

local function field(name: string, label: string, text: string, width: number, order: number, onCommit: (typed: string) -> ()): any
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(0, theme.sizes.fieldHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.tight),
		}),
		label = Roact.createElement("TextLabel", {
			Size = UDim2.fromOffset(0, theme.sizes.fieldHeight),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = label,
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			LayoutOrder = 1,
		}),
		[name] = Roact.createElement("TextBox", {
			Size = UDim2.fromOffset(width, theme.sizes.fieldHeight),
			BackgroundColor3 = theme.colors.surface,
			BorderSizePixel = 0,
			Text = text,
			ClearTextOnFocus = false,
			TextColor3 = theme.colors.text,
			Font = theme.typography.body.font,
			TextSize = theme.typography.body.size,
			LayoutOrder = 2,
			[Roact.Event.FocusLost] = function(box: TextBox)
				local typed = box.Text
				box.Text = text
				onCommit(typed)
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		}),
	})
end

return field
