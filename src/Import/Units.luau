--!strict
local Geometry = require("../Geometry")

local Units = {}

function Units.size(w: number, h: number, innerW: number, innerH: number): (number, number)
	return Geometry.toScale(w, innerW), Geometry.toScale(h, innerH)
end

function Units.position(
	x: number, y: number, w: number, h: number,
	pad: { number }, innerW: number, innerH: number, ax: number, ay: number
): (number, number)
	return Geometry.toScale(x - pad[4] + w * ax, innerW), Geometry.toScale(y - pad[1] + h * ay, innerH)
end

local EDGE: { [string]: number } = { MIN = 0, MAX = 1 }

function Units.anchor(constraints: { h: string, v: string }?, isRootChild: boolean): (number, number, string?)
	if not isRootChild or not constraints then
		return 0.5, 0.5, nil
	end
	local ax = EDGE[constraints.h] or 0.5
	local ay = EDGE[constraints.v] or 0.5
	return ax, ay, if ax ~= 0.5 or ay ~= 0.5 then "pinned to screen edge" else nil
end

function Units.corner(radius: { number }, w: number, h: number): { number }
	local out = {}
	for i = 1, 4 do
		out[i] = Geometry.cornerScale(radius[i] or 0, w, h)
	end
	return out
end

function Units.stroke(weight: number, w: number, h: number): number
	return Geometry.strokeScale(weight, w, h)
end

function Units.padding(pad: { number }, w: number, h: number): { number }
	return {
		Geometry.toScale(pad[1], h),
		Geometry.toScale(pad[2], w),
		Geometry.toScale(pad[3], h),
		Geometry.toScale(pad[4], w),
	}
end

function Units.gap(gap: number, dir: string, innerW: number, innerH: number): number
	return Geometry.toScale(gap, if dir == "H" then innerW else innerH)
end

function Units.fullScreen(w: number, h: number): boolean
	return h > 0 and math.abs(w / h - 16 / 9) < 0.01
end

function Units.textMax(size: number): number
	return math.floor(size * 1.5)
end

function Units.shadow(effect: any, w: number, h: number): { x: number, y: number, blur: number, spread: number, transparency: number }
	local side = math.min(w, h)
	return {
		x = Geometry.toScale(effect.x or 0, w),
		y = Geometry.toScale(effect.y or 0, h),
		blur = Geometry.toScale(effect.blur or 0, side),
		spread = Geometry.toScale(effect.spread or 0, side),
		transparency = Geometry.round4(1 - (effect.a or 1)),
	}
end

function Units.hexToRgb(hex: string): (number, number, number)
	local r = tonumber(string.sub(hex, 1, 2), 16) or 0
	local g = tonumber(string.sub(hex, 3, 4), 16) or 0
	local b = tonumber(string.sub(hex, 5, 6), 16) or 0
	return r / 255, g / 255, b / 255
end

return Units
