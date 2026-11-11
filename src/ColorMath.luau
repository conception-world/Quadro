--!strict
local Stops = require("./Gradients/Stops")

local ColorMath = {}

ColorMath.RIM = 1.5

local TAU = 2 * math.pi

function ColorMath.toRgb(h: number, s: number, v: number): (number, number, number)
	local sector = (h % 1) * 6
	local index = math.floor(sector)
	local f = sector - index
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local u = v * (1 - s * (1 - f))
	if index == 0 then
		return v, u, p
	elseif index == 1 then
		return q, v, p
	elseif index == 2 then
		return p, v, u
	elseif index == 3 then
		return p, q, v
	elseif index == 4 then
		return u, p, v
	end
	return v, p, q
end

function ColorMath.fromRgb(r: number, g: number, b: number): (number, number, number)
	local high = math.max(r, g, b)
	local delta = high - math.min(r, g, b)
	local sector = 0
	if delta > 0 then
		if high == r then
			sector = ((g - b) / delta) % 6
		elseif high == g then
			sector = (b - r) / delta + 2
		else
			sector = (r - g) / delta + 4
		end
	end
	return sector / 6, if high > 0 then delta / high else 0, high
end

function ColorMath.toHex(h: number, s: number, v: number): string
	local r, g, b = ColorMath.toRgb(h, s, v)
	return Stops.hex(r * 255, g * 255, b * 255)
end

function ColorMath.fromHex(hex: string): (number, number, number)
	local r, g, b = Stops.rgb(hex)
	return ColorMath.fromRgb(r / 255, g / 255, b / 255)
end

function ColorMath.polar(x: number, y: number): (number, number)
	return (math.atan2(-y, x) / TAU) % 1, math.min(math.sqrt(x * x + y * y), 1)
end

function ColorMath.point(h: number, s: number): (number, number)
	local angle = h * TAU
	return s * math.cos(angle), -s * math.sin(angle)
end

function ColorMath.wheel(size: number): buffer
	local pixels = buffer.create(size * size * 4)
	local radius = size / 2
	for row = 0, size - 1 do
		local y = (row + 0.5 - radius) / radius
		for column = 0, size - 1 do
			local x = (column + 0.5 - radius) / radius
			local h, s = ColorMath.polar(x, y)
			local r, g, b = ColorMath.toRgb(h, s, 1)
			local alpha = math.clamp((1 - math.sqrt(x * x + y * y)) * radius / ColorMath.RIM, 0, 1)
			local offset = (row * size + column) * 4
			buffer.writeu8(pixels, offset, math.round(r * 255))
			buffer.writeu8(pixels, offset + 1, math.round(g * 255))
			buffer.writeu8(pixels, offset + 2, math.round(b * 255))
			buffer.writeu8(pixels, offset + 3, math.round(alpha * 255))
		end
	end
	return pixels
end

return ColorMath
