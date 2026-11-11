--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)
local Flow = require(script.Parent.Flow)

type Props = {
	label: string,
	expandedLabel: string,
	expanded: boolean,
	onToggle: () -> (),
	layoutOrder: number?,
	leading: any?,
	children: { [any]: any }?,
}

local function Disclosure(props: Props)
	local toggle = Roact.createElement(Button, {
		text = if props.expanded then props.expandedLabel else props.label,
		variant = "ghost",
		compact = true,
		layoutOrder = if props.leading ~= nil then 2 else 1,
		onClick = props.onToggle,
	})
	local children: { [any]: any } = {
		__disclosureLayout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.sm),
		}),
	}
	if props.leading ~= nil then
		children.row = Roact.createElement(Flow, {
			layoutOrder = 1,
			children = { leading = props.leading, toggle = toggle },
		})
	else
		children.toggle = toggle
	end
	if props.expanded then
		local content: { [any]: any } = {
			__disclosureLayout = Roact.createElement("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, theme.spacing.sm),
			}),
		}
		for key, child in props.children or {} do
			content[key] = child
		end
		children.content = Roact.createElement("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, content)
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

return Disclosure
