--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Flow = require(script.Parent.Flow)

type Props = {
	colors: { string },
	onPick: (hex: string) -> (),
	layoutOrder: number?,
}

local CHIP_MAX = 12

local ColorChips = {}

function ColorChips.merge(sources: { { string } }): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for _, source in sources do
		for _, hex in source do
			if not seen[hex] and #list < CHIP_MAX then
				seen[hex] = true
				table.insert(list, hex)
			end
		end
	end
	return list
end

function ColorChips.render(props: Props): any
	local children: { [any]: any } = {}
	for index, hex in props.colors do
		children["chip" .. index] = Roact.createElement("TextButton", {
			Size = UDim2.fromOffset(theme.sizes.chip, theme.sizes.chip),
			BackgroundColor3 = Color3.fromHex(hex),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = index,
			[Roact.Event.Activated] = function()
				props.onPick(hex)
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			stroke = Roact.createElement("UIStroke", {
				Color = theme.colors.stroke,
				Thickness = theme.sizes.chipStroke,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return Roact.createElement(Flow, { layoutOrder = props.layoutOrder, children = children })
end

return ColorChips
