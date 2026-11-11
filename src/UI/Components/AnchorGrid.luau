--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

type Props = {
	onPick: (x: number, y: number) -> (),
	layoutOrder: number?,
}

local STEPS = { 0, 0.5, 1 }

local function inset(fraction: number): number
	if fraction == 0 then
		return theme.sizes.anchorDotInset
	elseif fraction == 1 then
		return -theme.sizes.anchorDotInset
	end
	return 0
end

local function AnchorGrid(props: Props)
	local cell = theme.sizes.anchorCell
	local gap = theme.spacing.sm
	local children: { [string]: any } = {
		grid = Roact.createElement("UIGridLayout", {
			CellSize = UDim2.fromOffset(cell, cell),
			CellPadding = UDim2.fromOffset(gap, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for row, y in STEPS do
		for column, x in STEPS do
			children["cell" .. row .. column] = Roact.createElement("TextButton", {
				LayoutOrder = (row - 1) * 3 + column,
				BackgroundColor3 = theme.colors.surface,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				[Roact.Event.Activated] = function()
					props.onPick(x, y)
				end,
			}, {
				corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
				dot = Roact.createElement("Frame", {
					AnchorPoint = Vector2.new(x, y),
					Position = UDim2.new(x, inset(x), y, inset(y)),
					Size = UDim2.fromOffset(theme.sizes.anchorDot, theme.sizes.anchorDot),
					BackgroundColor3 = theme.colors.accentPrimary,
					BorderSizePixel = 0,
				}, {
					corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				}),
			})
		end
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(cell * 3 + gap * 2, cell * 3 + gap * 2),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

return AnchorGrid
