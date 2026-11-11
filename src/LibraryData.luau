--!strict
local Codec = require("./Gradients/Codec")

local LibraryData = {}

export type Scope = "place" | "global"
export type Item = { key: string, scope: Scope, value: any, shared: boolean }
export type Global = { tokens: { [string]: any }, components: { [string]: string } }
export type Pending = { id: string, at: number }

LibraryData.KINDS = { "color", "size", "font", "gradient" }
LibraryData.SCOPES = { "place", "global" }
LibraryData.COLOR_PROPERTIES = { "background", "text" }
LibraryData.MAX_NAME = 50
LibraryData.MAX_TOKENS = 300
LibraryData.MAX_COMPONENTS = 20
LibraryData.MAX_COMPONENT_BYTES = 200 * 1024
LibraryData.CONFIRM_WINDOW = 3
LibraryData.LIST_LIMIT = 8

local FOLD_FROM = "áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ"
local FOLD_TO = "aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN"
local FOLD: { [number]: string } = {}
do
	local index = 0
	for _, code in utf8.codes(FOLD_FROM) do
		index += 1
		FOLD[code] = string.sub(FOLD_TO, index, index)
	end
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function LibraryData.cleanName(raw: any): string?
	if type(raw) ~= "string" or utf8.len(raw) == nil then
		return nil
	end
	local parts: { string } = {}
	for _, code in utf8.codes(raw) do
		local char = FOLD[code] or (if code < 128 then string.char(code) else "_")
		table.insert(parts, if string.match(char, "^[%w_%-]$") then char else "_")
	end
	local joined = string.gsub(table.concat(parts), "_+", "_")
	local clean = string.match(string.sub(joined, 1, LibraryData.MAX_NAME), "^[_%-]*(.-)[_%-]*$") or ""
	return if clean == "" then nil else clean
end

function LibraryData.key(kind: string, name: string): string
	return kind .. "_" .. name
end

function LibraryData.parseKey(key: any): (string?, string?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local kind, name = string.match(key, "^(%a+)_(.+)$")
	if kind == nil or table.find(LibraryData.KINDS, kind) == nil or LibraryData.cleanName(name) ~= name then
		return nil, nil
	end
	return kind, name
end

function LibraryData.sanitize(kind: string, raw: any): any
	if kind == "color" then
		local hex = if type(raw) == "string" then string.match(raw, "^#?(%x%x%x%x%x%x)$") else nil
		return if hex then string.lower(hex) else nil
	elseif kind == "size" then
		if type(raw) ~= "table" or (#raw ~= 2 and #raw ~= 4) then
			return nil
		end
		local out = {}
		for index = 1, #raw do
			if not finite(raw[index]) then
				return nil
			end
			out[index] = raw[index]
		end
		return out
	elseif kind == "font" then
		if type(raw) ~= "table" or type(raw.family) ~= "string" or #raw.family == 0 or #raw.family > 200 then
			return nil
		end
		if type(raw.weight) ~= "string" or type(raw.style) ~= "string" or not string.match(raw.weight, "^%a+$") or not string.match(raw.style, "^%a+$") then
			return nil
		end
		return { family = raw.family, weight = raw.weight, style = raw.style }
	elseif kind == "gradient" then
		return Codec.sanitize(raw)
	end
	return nil
end

function LibraryData.validComponent(name: any, data: any): boolean
	return LibraryData.cleanName(name) == name
		and type(data) == "string"
		and #data > 0
		and #data <= LibraryData.MAX_COMPONENT_BYTES
		and string.match(data, "^[%w%+/]+=*$") ~= nil
end

function LibraryData.sanitizeGlobal(raw: any): Global
	local out: Global = { tokens = {}, components = {} }
	if type(raw) ~= "table" then
		return out
	end
	local count = 0
	if type(raw.tokens) == "table" then
		for key, value in raw.tokens do
			local kind = LibraryData.parseKey(key)
			local clean = if kind then LibraryData.sanitize(kind, value) else nil
			if clean ~= nil and count < LibraryData.MAX_TOKENS then
				out.tokens[key] = clean
				count += 1
			end
		end
	end
	count = 0
	if type(raw.components) == "table" then
		for name, data in raw.components do
			if LibraryData.validComponent(name, data) and count < LibraryData.MAX_COMPONENTS then
				out.components[name] = data
				count += 1
			end
		end
	end
	return out
end

function LibraryData.merge(place: { [string]: any }, global: { [string]: any }): { Item }
	local items: { Item } = {}
	for key, value in place do
		table.insert(items, { key = key, scope = "place", value = value, shared = global[key] ~= nil })
	end
	for key, value in global do
		if place[key] == nil then
			table.insert(items, { key = key, scope = "global", value = value, shared = false })
		end
	end
	table.sort(items, function(a: Item, b: Item): boolean
		local left, right = string.lower(a.key), string.lower(b.key)
		if left ~= right then
			return left < right
		end
		return a.key < b.key
	end)
	return items
end

function LibraryData.freeName(base: string, taken: (name: string) -> boolean): string
	if not taken(base) then
		return base
	end
	local index = 2
	while true do
		local suffix = "-" .. index
		local stem = string.match(string.sub(base, 1, LibraryData.MAX_NAME - #suffix), "^(.-)[_%-]*$") or ""
		local candidate = stem .. suffix
		if not taken(candidate) then
			return candidate
		end
		index += 1
	end
end

function LibraryData.confirms(pending: any, id: string, now: number): boolean
	return type(pending) == "table" and pending.id == id and now - pending.at <= LibraryData.CONFIRM_WINDOW
end

function LibraryData.count(map: { [string]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

return LibraryData
