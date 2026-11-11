--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	title: string,
	subtitle: string?,
	accessory: any?,
	layoutOrder: number?,
}

local function Heading(props: Props)
	local children: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.tight),
		}),
		title = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.typography.title.size + 4),
			BackgroundTransparency = 1,
			Text = props.title,
			TextColor3 = theme.colors.text,
			Font = theme.typography.title.font,
			TextSize = theme.typography.title.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}, {
			accessory = if props.accessory ~= nil
				then Roact.createElement("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromOffset(0, theme.sizes.badgeHeight),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
				}, { content = props.accessory })
				else nil,
		}),
	}
	if props.subtitle ~= nil then
		children.subtitle = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, theme.typography.caption.size + 4),
			BackgroundTransparency = 1,
			Text = props.subtitle,
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

return Heading
