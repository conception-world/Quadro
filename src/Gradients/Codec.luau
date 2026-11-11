--!strict
export type Stop = { t: number, c: string, a: number }
export type Data = {
	name: string,
	rotation: number,
	offset: { number },
	color: { Stop },
	transparency: { { number } },
}

local Codec = {}

local function round3(value: number): number
	local rounded = math.floor(value * 1000 + 0.5) / 1000
	return if rounded == 0 then 0 else rounded
end

function Codec.normalize(data: Data): Data
	local color: { Stop } = {}
	for _, stop in data.color do
		table.insert(color, { t = round3(stop.t), c = string.lower(stop.c), a = round3(stop.a) })
	end
	local transparency: { { number } } = {}
	for _, point in data.transparency do
		table.insert(transparency, { round3(point[1]), round3(point[2]) })
	end
	return {
		name = data.name,
		rotation = math.floor(data.rotation + 0.5),
		offset = { round3(data.offset[1]), round3(data.offset[2]) },
		color = color,
		transparency = transparency,
	}
end

function Codec.signature(data: Data): string
	local n = Codec.normalize(data)
	local parts = { string.format("r%d", n.rotation), string.format("o%.3f,%.3f", n.offset[1], n.offset[2]) }
	for _, stop in n.color do
		table.insert(parts, string.format("c%.3f:%s:%.3f", stop.t, stop.c, stop.a))
	end
	for _, point in n.transparency do
		table.insert(parts, string.format("t%.3f:%.3f", point[1], point[2]))
	end
	return table.concat(parts, "|")
end

Codec.MAX_NAME_LENGTH = 60
Codec.MAX_KEYPOINTS = 20

function Codec.cleanName(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	if trimmed == "" or not utf8.len(trimmed) then
		return nil
	end
	local cut = utf8.offset(trimmed, Codec.MAX_NAME_LENGTH + 1)
	return if cut then string.sub(trimmed, 1, cut - 1) else trimmed
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function channel(value: any): string?
	if not finite(value) then
		return nil
	end
	return string.format("%02x", math.floor(math.clamp(value, 0, 1) * 255 + 0.5))
end

local function pair(raw: any, first: string, second: string): (any, any)
	if type(raw) ~= "table" then
		return nil, nil
	end
	if raw[1] ~= nil or raw[2] ~= nil then
		return raw[1], raw[2]
	end
	return raw[first], raw[second]
end

function Codec.sanitize(raw: any): Data?
	if type(raw) ~= "table" or not finite(raw.rotation) then
		return nil
	end
	local offsetX, offsetY = pair(raw.offset, "x", "y")
	if not finite(offsetX) or not finite(offsetY) then
		return nil
	end
	local rawColor, rawTransparency = raw.color, raw.transparency
	if type(rawColor) ~= "table" or type(rawTransparency) ~= "table" then
		return nil
	end
	if #rawColor < 2 or #rawColor > Codec.MAX_KEYPOINTS or #rawTransparency < 2 or #rawTransparency > Codec.MAX_KEYPOINTS then
		return nil
	end
	local color: { Stop } = {}
	for _, stop in rawColor do
		if type(stop) ~= "table" then
			return nil
		end
		local t = if stop.t ~= nil then stop.t else stop.time
		local hex = stop.c
		if hex == nil then
			local r, g, b = channel(stop.r), channel(stop.g), channel(stop.b)
			if not r or not g or not b then
				return nil
			end
			hex = r .. g .. b
		end
		local alpha = if stop.a == nil then 0 else stop.a
		if not finite(t) or not finite(alpha) or type(hex) ~= "string" or not string.match(hex, "^%x%x%x%x%x%x$") then
			return nil
		end
		table.insert(color, { t = t, c = hex, a = math.clamp(alpha, 0, 1) })
	end
	local transparency: { { number } } = {}
	for _, point in rawTransparency do
		local t, value = pair(point, "time", "value")
		if not finite(t) or not finite(value) then
			return nil
		end
		table.insert(transparency, { t, math.clamp(value, 0, 1) })
	end
	local data = Codec.normalize({
		name = Codec.cleanName(raw.name) or "Gradient",
		rotation = math.clamp(raw.rotation, -360, 360),
		offset = { math.clamp(offsetX, -1, 1), math.clamp(offsetY, -1, 1) },
		color = color,
		transparency = transparency,
	})
	local previous = 0
	for _, stop in data.color do
		if stop.t < previous or stop.t > 1 then
			return nil
		end
		previous = stop.t
	end
	previous = 0
	for _, point in data.transparency do
		if point[1] < previous or point[1] > 1 then
			return nil
		end
		previous = point[1]
	end
	if data.color[1].t ~= 0 or data.color[#data.color].t ~= 1 then
		return nil
	end
	if data.transparency[1][1] ~= 0 or data.transparency[#data.transparency][1] ~= 1 then
		return nil
	end
	return data
end

return Codec
