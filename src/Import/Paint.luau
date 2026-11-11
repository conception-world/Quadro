--!strict
local Spec = require("./Spec")
local Units = require("./Units")

local Paint = {}

local MAX_STOPS = Spec.MAX_STOPS

export type Library = { lookup: (name: string) -> any?, write: (gradient: UIGradient, data: any) -> boolean }

local STROKE_POSITIONS: { [string]: Enum.BorderStrokePosition } = {
	I = Enum.BorderStrokePosition.Inner,
	C = Enum.BorderStrokePosition.Center,
	O = Enum.BorderStrokePosition.Outer,
}

local function color(hex: string): Color3
	local r, g, b = Units.hexToRgb(hex)
	return Color3.new(r, g, b)
end

function Paint.gradient(parent: Instance, rotation: number, stops: { Spec.Stop }, opacity: number)
	if #stops == 0 then
		return
	end
	local list: { Spec.Stop } = table.clone(stops)
	if list[1].t > 0 then
		table.insert(list, 1, { t = 0, hex = list[1].hex, a = list[1].a })
	end
	local last = list[#list]
	if last.t < 1 then
		table.insert(list, { t = 1, hex = last.hex, a = last.a })
	end
	while #list > MAX_STOPS do
		table.remove(list, 2)
	end
	local colors: { ColorSequenceKeypoint } = {}
	local alphas: { NumberSequenceKeypoint } = {}
	for _, stop in list do
		local t = math.clamp(stop.t, 0, 1)
		table.insert(colors, ColorSequenceKeypoint.new(t, color(stop.hex)))
		table.insert(alphas, NumberSequenceKeypoint.new(t, math.clamp(1 - stop.a * opacity, 0, 1)))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Color = ColorSequence.new(colors)
	gradient.Transparency = NumberSequence.new(alphas)
	gradient.Parent = parent
end

function Paint.background(gui: GuiObject, fill: Spec.Fill?, opacity: number, tokens: { [string]: Spec.Linear }, library: Library, warnings: { string }, tint: string?)
	gui.BackgroundColor3 = if tint and fill and (fill.kind == "linear" or fill.kind == "token") then color(tint) else Color3.new(1, 1, 1)
	gui.BackgroundTransparency = 1
	if fill == nil then
		return
	end
	if fill.kind == "token" then
		local wanted = string.lower(string.match(fill.name, "^%s*(.-)%s*$") or "")
		local preset = library.lookup(wanted)
		if preset then
			gui.BackgroundTransparency = 0
			local gradient = Instance.new("UIGradient")
			library.write(gradient, preset)
			gradient.Parent = gui
			return
		end
		local literal = tokens[fill.name]
		if literal == nil then
			table.insert(warnings, gui.Name .. ": gradient token '" .. fill.name .. "' not found")
			return
		end
		gui.BackgroundTransparency = 0
		Paint.gradient(gui, literal.rotation, literal.stops, opacity)
	elseif fill.kind == "solid" then
		gui.BackgroundColor3 = color(fill.hex)
		gui.BackgroundTransparency = math.clamp(1 - fill.a * opacity, 0, 1)
	elseif fill.kind == "linear" then
		gui.BackgroundTransparency = 0
		Paint.gradient(gui, fill.rotation, fill.stops, opacity)
	end
end

function Paint.corner(gui: GuiObject, radius: { number }, w: number, h: number, warnings: { string })
	local scales = Units.corner(radius, w, h)
	if scales[1] == 0 and scales[2] == 0 and scales[3] == 0 and scales[4] == 0 then
		return
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scales[1], 0)
	if scales[1] ~= scales[2] or scales[1] ~= scales[3] or scales[1] ~= scales[4] then
		local c: any = corner
		local applied, problem = pcall(function()
			c.TopLeftRadius = UDim.new(scales[1], 0)
			c.TopRightRadius = UDim.new(scales[2], 0)
			c.BottomRightRadius = UDim.new(scales[3], 0)
			c.BottomLeftRadius = UDim.new(scales[4], 0)
		end)
		if not applied then
			corner.CornerRadius = UDim.new(scales[1], 0)
			table.insert(warnings, gui.Name .. ": per-corner radius unavailable, using uniform radius (" .. tostring(problem) .. ")")
		end
	end
	corner.Parent = gui
end

function Paint.stroke(
	gui: Instance,
	spec: { hex: string?, a: number, weight: number, align: string?, linear: Spec.Linear? },
	w: number,
	h: number,
	opacity: number,
	contextual: boolean
)
	if spec.weight <= 0 or (spec.hex == nil and spec.linear == nil) then
		return
	end
	local stroke = Instance.new("UIStroke")
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = math.clamp(Units.stroke(spec.weight, w, h), 0, 1)
	stroke.Color = color(spec.hex or "ffffff")
	stroke.Transparency = math.clamp(1 - spec.a * opacity, 0, 1)
	if contextual then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	else
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.BorderStrokePosition = STROKE_POSITIONS[spec.align or "I"] or Enum.BorderStrokePosition.Inner
	end
	if spec.linear then
		Paint.gradient(stroke, spec.linear.rotation, spec.linear.stops, opacity)
	end
	stroke.Parent = gui
end

function Paint.effects(gui: GuiObject, effects: { Spec.Effect }, w: number, h: number, opacity: number, warnings: { string })
	for _, effect in effects do
		if effect.kind == "dropShadow" and gui:IsA("TextLabel") then
			table.insert(warnings, gui.Name .. ": sombra em texto ignorada")
		elseif effect.kind == "dropShadow" then
			local measured = Units.shadow(effect, w, h)
			local ui = Instance.new("UIShadow")
			ui.Color = color(effect.hex or "000000")
			ui.Transparency = math.clamp(1 - (effect.a or 1) * opacity, 0, 1)
			ui.Offset = UDim2.fromScale(measured.x, measured.y)
			ui.BlurRadius = UDim.new(measured.blur, 0)
			ui.Spread = UDim2.fromScale(measured.spread, measured.spread)
			ui.Parent = gui
		else
			table.insert(warnings, gui.Name .. ": inner shadow/blur not supported natively")
		end
	end
end

return Paint
