--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local Button = require(script.Parent.Button)
local Flow = require(script.Parent.Flow)

type Option = { id: string, label: string }

type Props = {
	options: { Option },
	value: string,
	layoutOrder: number?,
	onSelect: (id: string) -> (),
}

local function Pills(props: Props)
	local buttons: { [any]: any } = {}
	for index, option in props.options do
		buttons[option.id] = Roact.createElement(Button, {
			text = option.label,
			variant = if option.id == props.value then "primary" else "ghost",
			compact = true,
			layoutOrder = index,
			onClick = function()
				props.onSelect(option.id)
			end,
		})
	end
	return Roact.createElement(Flow, { layoutOrder = props.layoutOrder, children = buttons })
end

return Pills
