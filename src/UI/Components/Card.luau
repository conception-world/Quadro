--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	padding: number?,
	color: Color3?,
	radius: number?,
	automaticSize: Enum.AutomaticSize?,
	ref: any?,
	children: { [any]: any }?,
}

local function Card(props: Props)
	local padding = props.padding or theme.spacing.lg
	local children: { [any]: any } = {
		__corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, props.radius or theme.radius.lg),
		}),
		__padding = Roact.createElement("UIPadding", {
			PaddingTop = UDim.new(0, padding),
			PaddingBottom = UDim.new(0, padding),
			PaddingLeft = UDim.new(0, padding),
			PaddingRight = UDim.new(0, padding),
		}),
	}
	if props.children ~= nil then
		for key, child in props.children do
			children[key] = child
		end
	end
	return Roact.createElement("Frame", {
		Size = props.size or UDim2.fromScale(1, 0),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = props.color or theme.colors.card,
		BorderSizePixel = 0,
		AutomaticSize = props.automaticSize or Enum.AutomaticSize.Y,
		[Roact.Ref] = props.ref,
	}, children)
end

return Card
