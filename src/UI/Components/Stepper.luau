--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)

type Props = {
	label: string,
	value: number,
	min: number,
	max: number,
	step: number,
	suffix: string?,
	editable: boolean?,
	layoutOrder: number?,
	onChange: (value: number) -> (),
}

local BUTTON_WIDTH = 32
local VALUE_WIDTH = 56

local function Stepper(props: Props)
	local function nudge(direction: number)
		props.onChange(math.clamp(props.value + direction * props.step, props.min, props.max))
	end
	local display = tostring(props.value) .. (props.suffix or "")
	local value: any
	if props.editable == true then
		value = Roact.createElement("TextBox", {
			Size = UDim2.fromOffset(VALUE_WIDTH, theme.sizes.row),
			BackgroundColor3 = theme.colors.surface,
			BorderSizePixel = 0,
			Text = display,
			ClearTextOnFocus = false,
			TextColor3 = theme.colors.text,
			Font = theme.typography.label.font,
			TextSize = theme.typography.label.size,
			LayoutOrder = 2,
			[Roact.Event.FocusLost] = function(box: TextBox)
				local typed = tonumber((string.gsub(box.Text, "[^%d%.%-]", "")))
				box.Text = display
				if typed ~= nil and typed == typed then
					props.onChange(math.clamp(typed, props.min, props.max))
				end
			end,
		}, {
			corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		})
	else
		value = Roact.createElement("TextLabel", {
			Size = UDim2.fromOffset(VALUE_WIDTH, theme.sizes.row),
			BackgroundTransparency = 1,
			Text = display,
			TextColor3 = theme.colors.text,
			Font = theme.typography.label.font,
			TextSize = theme.typography.label.size,
			LayoutOrder = 2,
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, theme.sizes.row),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		label = Roact.createElement("TextLabel", {
			Size = UDim2.new(1, -(BUTTON_WIDTH * 2 + VALUE_WIDTH + theme.spacing.sm * 2), 1, 0),
			BackgroundTransparency = 1,
			Text = props.label,
			TextColor3 = theme.colors.text,
			Font = theme.typography.body.font,
			TextSize = theme.typography.body.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		controls = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, BUTTON_WIDTH * 2 + VALUE_WIDTH + theme.spacing.sm * 2, 1, 0),
			BackgroundTransparency = 1,
		}, {
			layout = Roact.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, theme.spacing.sm),
			}),
			down = Roact.createElement(Button, {
				text = "-",
				variant = "ghost",
				compact = true,
				size = UDim2.fromOffset(BUTTON_WIDTH, theme.sizes.row),
				disabled = props.value <= props.min,
				layoutOrder = 1,
				onClick = function()
					nudge(-1)
				end,
			}),
			value = value,
			up = Roact.createElement(Button, {
				text = "+",
				variant = "ghost",
				compact = true,
				size = UDim2.fromOffset(BUTTON_WIDTH, theme.sizes.row),
				disabled = props.value >= props.max,
				layoutOrder = 3,
				onClick = function()
					nudge(1)
				end,
			}),
		}),
	})
end

return Stepper
