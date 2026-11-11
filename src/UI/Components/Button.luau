--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)

export type Variant = "primary" | "danger" | "ghost" | "accept"

type Props = {
	text: string,
	onClick: () -> (),
	variant: Variant?,
	size: UDim2?,
	layoutOrder: number?,
	disabled: boolean?,
	compact: boolean?,
}

local function colorsFor(variant: Variant, disabled: boolean): (Color3, Color3)
	if disabled then
		return theme.colors.surface, theme.colors.textMuted
	end
	if variant == "danger" then
		return theme.colors.accentDecline, theme.colors.text
	elseif variant == "ghost" then
		return theme.colors.surface, theme.colors.text
	elseif variant == "accept" then
		return theme.colors.accentAccept, theme.colors.textInverse
	end
	return theme.colors.accentPrimary, theme.colors.text
end

local function Button(props: Props)
	local variant: Variant = props.variant or "primary"
	local disabled = props.disabled == true
	local bg, fg = colorsFor(variant, disabled)
	local children: { [string]: any } = {
		corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, theme.radius.pill),
		}),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, if props.compact == true then theme.spacing.md else theme.spacing.lg),
			PaddingRight = UDim.new(0, if props.compact == true then theme.spacing.md else theme.spacing.lg),
			PaddingTop = UDim.new(0, theme.spacing.sm),
			PaddingBottom = UDim.new(0, theme.spacing.sm),
		}),
	}
	if variant == "ghost" then
		children.stroke = Roact.createElement("UIStroke", {
			Color = if disabled then theme.colors.stroke else theme.colors.surfaceActive,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end
	return Roact.createElement("TextButton", {
		Size = props.size or UDim2.fromOffset(0, 32),
		AutomaticSize = if props.size ~= nil then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
		AutoButtonColor = not disabled,
		Active = not disabled,
		Text = props.text,
		TextColor3 = fg,
		Font = theme.typography.label.font,
		TextSize = theme.typography.label.size,
		[Roact.Event.Activated] = function()
			if disabled then
				return
			end
			local ok, err = pcall(props.onClick)
			if not ok then
				warn(string.format("[Quadro] Button onClick threw: %s", tostring(err)))
			end
		end,
	}, children)
end

return Button
