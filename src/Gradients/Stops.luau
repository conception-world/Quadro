--!strict
local Codec = require("./Codec")

export type Kind = "color" | "transparency"

local Stops = {}

Stops.DEFAULT = table.freeze({
	name = "Gradient",
	rotation = 0,
	offset = { 0, 0 },
	color = { { t = 0, c = "ffffff", a = 0 }, { t = 1, c = "000000", a = 0 } },
	transparency = { { 0, 0 }, { 1, 0 } },
}) :: Codec.Data

Stops.MIN_INNER = 0.01
Stops.MAX_INNER = 0.99
Stops.MASK_MIN = 0.05
Stops.MASK_MAX = 0.5

function Stops.snap(t: number): number
	return math.clamp(math.round(t * 100) / 100, 0, 1)
end

local function timeOf(kind: Kind, point: any): number
	return if kind == "color" then point.t else point[1]
end

local function withTime(kind: Kind, point: any, t: number): any
	if kind == "color" then
		return { t = t, c = point.c, a = point.a }
	end
	return { t, point[2] }
end

local function listOf(data: Codec.Data, kind: Kind): { any }
	return if kind == "color" then data.color else data.transparency
end

local function replaced(data: Codec.Data, kind: Kind, list: { any }): Codec.Data
	return {
		name = data.name,
		rotation = data.rotation,
		offset = data.offset,
		color = if kind == "color" then list else data.color,
		transparency = if kind == "transparency" then list else data.transparency,
	}
end

function Stops.list(data: Codec.Data, kind: Kind): { any }
	return listOf(data, kind)
end

function Stops.isEndpoint(data: Codec.Data, kind: Kind, index: number): boolean
	return index <= 1 or index >= #listOf(data, kind)
end

function Stops.rgb(hex: string): (number, number, number)
	return tonumber(string.sub(hex, 1, 2), 16) or 0, tonumber(string.sub(hex, 3, 4), 16) or 0, tonumber(string.sub(hex, 5, 6), 16) or 0
end

function Stops.hex(r: number, g: number, b: number): string
	local function channel(value: number): number
		return math.clamp(math.round(value), 0, 255)
	end
	return string.format("%02x%02x%02x", channel(r), channel(g), channel(b))
end

function Stops.parseHex(text: string): string?
	local digits = string.match(text, "^%s*#?(%x%x%x%x%x%x)%s*$")
	return if digits then string.lower(digits) else nil
end

local function bracket(list: { any }, kind: Kind, t: number): (any, any, number)
	for index = 2, #list do
		local right = list[index]
		local rightTime = timeOf(kind, right)
		if t <= rightTime then
			local left = list[index - 1]
			local leftTime = timeOf(kind, left)
			local span = rightTime - leftTime
			return left, right, if span > 0 then (t - leftTime) / span else 0
		end
	end
	local last = list[#list]
	return last, last, 0
end

function Stops.colorAt(stops: { Codec.Stop }, t: number): string
	local left, right, alpha = bracket(stops, "color", t)
	local r1, g1, b1 = Stops.rgb(left.c)
	local r2, g2, b2 = Stops.rgb(right.c)
	return Stops.hex(r1 + (r2 - r1) * alpha, g1 + (g2 - g1) * alpha, b1 + (b2 - b1) * alpha)
end

function Stops.valueAt(points: { { number } }, t: number): number
	local left, right, alpha = bracket(points, "transparency", t)
	return math.round((left[2] + (right[2] - left[2]) * alpha) * 1000) / 1000
end

function Stops.add(data: Codec.Data, kind: Kind): (Codec.Data?, number?)
	local list = listOf(data, kind)
	if #list >= Codec.MAX_KEYPOINTS then
		return nil, nil
	end
	local widest, at = -1, 2
	for index = 2, #list do
		local gap = timeOf(kind, list[index]) - timeOf(kind, list[index - 1])
		if gap > widest then
			widest, at = gap, index
		end
	end
	local t = Stops.snap((timeOf(kind, list[at - 1]) + timeOf(kind, list[at])) / 2)
	local point = if kind == "color"
		then { t = t, c = Stops.colorAt(list, t), a = 0 }
		else { t, Stops.valueAt(list, t) }
	local out = table.clone(list)
	table.insert(out, at, point)
	return replaced(data, kind, out), at
end

function Stops.remove(data: Codec.Data, kind: Kind, index: number): Codec.Data?
	local list = listOf(data, kind)
	if Stops.isEndpoint(data, kind, index) or #list <= 2 then
		return nil
	end
	local out = table.clone(list)
	table.remove(out, index)
	return replaced(data, kind, out)
end

function Stops.move(data: Codec.Data, kind: Kind, index: number, t: number): (Codec.Data, number)
	local list = listOf(data, kind)
	if Stops.isEndpoint(data, kind, index) then
		return data, index
	end
	local origin = timeOf(kind, list[index])
	local out = table.clone(list)
	table.remove(out, index)
	local wanted = math.clamp(Stops.snap(t), Stops.MIN_INNER, Stops.MAX_INNER)
	local step = if wanted > origin then -0.01 else 0.01
	for _ = 1, #out * 2 + 2 do
		local taken = false
		for _, point in out do
			if math.round(timeOf(kind, point) * 100) == math.round(wanted * 100) then
				taken = true
				break
			end
		end
		if not taken then
			break
		end
		local nextTime = math.round((wanted + step) * 100) / 100
		if nextTime < Stops.MIN_INNER or nextTime > Stops.MAX_INNER then
			step = -step
			nextTime = math.round((wanted + step) * 100) / 100
		end
		wanted = nextTime
	end
	local moved = withTime(kind, list[index], wanted)
	local target = #out
	for position = 2, #out do
		if timeOf(kind, out[position]) > timeOf(kind, moved) then
			target = position
			break
		end
	end
	table.insert(out, target, moved)
	return replaced(data, kind, out), target
end

function Stops.set(data: Codec.Data, kind: Kind, index: number, value: any): Codec.Data
	local list = table.clone(listOf(data, kind))
	local point = list[index]
	if kind == "color" then
		list[index] = { t = point.t, c = value, a = point.a }
	else
		list[index] = { point[1], math.clamp(value, 0, 1) }
	end
	return replaced(data, kind, list)
end

export type Side = "top" | "bottom" | "left" | "right" | "edges"

function Stops.mask(side: Side, length: number, axis: string?): (number, { { number } })
	local l = math.round(math.clamp(length, Stops.MASK_MIN, Stops.MASK_MAX) * 1000) / 1000
	local far = math.round((1 - l) * 1000) / 1000
	local vertical = side == "top" or side == "bottom" or (side == "edges" and axis == "v")
	local rotation = if vertical then 90 else 0
	if side == "top" or side == "left" then
		return rotation, { { 0, 1 }, { l, 0 }, { 1, 0 } }
	elseif side == "bottom" or side == "right" then
		return rotation, { { 0, 0 }, { far, 0 }, { 1, 1 } }
	end
	if l >= 0.5 then
		return rotation, { { 0, 1 }, { 0.5, 0 }, { 1, 1 } }
	end
	return rotation, { { 0, 1 }, { l, 0 }, { far, 0 }, { 1, 1 } }
end

return Stops
