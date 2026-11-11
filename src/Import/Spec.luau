--!strict
local Spec = {}

Spec.SUPPORTED_VERSION = 1
Spec.MAX_STOPS = 20
Spec.COMPONENTS_PAGE = "__Components"

local MAX_NODES = 5000
local MAX_STOPS = Spec.MAX_STOPS
local MAX_ERRORS = 50
local MAX_SOURCE_WARNINGS = 100
local MAX_WARNING_LENGTH = 200
local KINDS = { frame = true, text = true, image = true, button = true, scroll = true, grid = true, list = true, template = true, ignore = true }
local SIZING = { hug = true, fill = true, fixed = true }
local CONSTRAINTS = { MIN = true, MAX = true, CENTER = true, STRETCH = true, SCALE = true }
local STROKE_ALIGN = { I = true, C = true, O = true }
local DIRECTIONS = { H = true, V = true }

export type Stop = { t: number, hex: string, a: number }
export type Linear = { kind: "linear", rotation: number, stops: { Stop } }
export type ImageFill = { kind: "image", hash: string?, asset: string?, scale: string, tile: { number }? }
export type Fill = { kind: "solid", hex: string, a: number }
	| Linear
	| ImageFill
	| { kind: "token", name: string }
export type Effect = { kind: string, hex: string?, a: number?, x: number?, y: number?, blur: number?, spread: number? }
export type Node = {
	id: string, name: string, kind: string, box: { number },
	rotation: number, opacity: number, visible: boolean, clip: boolean,
	fills: { Fill }, tint: string?, stroke: { hex: string, a: number, weight: number, align: string, linear: Linear? }?,
	radius: { number }?, effects: { Effect },
	layout: { dir: string, gap: number, padding: { number }, align: { string }, wrap: boolean }?,
	sizing: { h: string, v: string }?, constraints: { h: string, v: string }?, absolute: boolean,
	text: { chars: string, family: string, weight: number, italic: boolean, size: number, hex: string, a: number, token: string?, align: { string }, stroke: { hex: string, a: number, weight: number }? }?,
	component: { key: string, name: string, variant: { [string]: string }, main: boolean }?,
	slice: { number }?, children: { Node },
}
export type Doc = {
	version: number,
	source: { [string]: any },
	root: Node,
	images: { [string]: { w: number, h: number, asset: string? } },
	tokens: { gradients: { [string]: Linear } },
	warnings: { string },
}

type Ctx = { errors: { string }, warnings: { string }, ids: { [string]: boolean }, count: number }

local function fail(ctx: Ctx, message: string)
	local errors = ctx.errors
	if #errors < MAX_ERRORS then
		table.insert(errors, message)
	elseif #errors == MAX_ERRORS then
		table.insert(errors, "…")
	end
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function num(ctx: Ctx, id: string, field: string, v: any, default: number, min: number?): number
	if v == nil then
		return default
	end
	if not finite(v) or (min ~= nil and v < min) then
		fail(ctx, "bad " .. field .. " on " .. id)
		return default
	end
	return v
end

local function alpha(ctx: Ctx, id: string, v: any): number
	return clamp01(num(ctx, id, "alpha", v, 1))
end

local function hex(v: any): string?
	if type(v) ~= "string" then
		return nil
	end
	local h = string.lower((string.gsub(v, "^#", "")))
	if #h == 6 and string.match(h, "^%x+$") then
		return h
	end
	return nil
end

local function hexOr(ctx: Ctx, id: string, v: any, default: string?): string
	if v == nil and default then
		return default
	end
	local h = hex(v)
	if not h then
		fail(ctx, "bad hex on " .. id)
		return default or "000000"
	end
	return h
end

local function str(v: any, default: string): string
	return if type(v) == "string" then v else default
end

local function enum(ctx: Ctx, id: string, v: any, set: { [string]: boolean }, default: string): string
	if v == nil then
		return default
	end
	if type(v) == "string" and set[v] then
		return v
	end
	table.insert(ctx.warnings, "unknown value on " .. id .. ", using " .. default)
	return default
end

local function deepCopy(v: any, depth: number): any
	if type(v) ~= "table" then
		local kind = type(v)
		return if kind == "number" or kind == "string" or kind == "boolean" then v else nil
	end
	if depth > 32 then
		return nil
	end
	local out = {}
	for k, x in v do
		if type(k) == "string" or type(k) == "number" then
			out[k] = deepCopy(x, depth + 1)
		end
	end
	return out
end

local function normalizeFill(ctx: Ctx, id: string, raw: any): Fill?
	if type(raw) ~= "table" then
		fail(ctx, "bad fill on " .. id)
		return nil
	end
	if raw.solid ~= nil then
		return { kind = "solid", hex = hexOr(ctx, id, raw.solid, nil), a = alpha(ctx, id, raw.a) }
	elseif raw.linear ~= nil then
		local lin = raw.linear
		if type(lin) ~= "table" or (lin.stops ~= nil and type(lin.stops) ~= "table") then
			fail(ctx, "bad gradient on " .. id)
			return nil
		end
		local stops: { Stop } = {}
		for _, s in lin.stops or {} do
			if type(s) ~= "table" or not finite(s[1]) then
				fail(ctx, "bad stop on " .. id)
			else
				table.insert(stops, { t = clamp01(s[1]), hex = hexOr(ctx, id, s[2], nil), a = alpha(ctx, id, s[3]) })
			end
		end
		if #stops < 2 then
			table.insert(ctx.warnings, "gradient on " .. id .. " dropped: fewer than 2 stops")
			return nil
		end
		local order = {}
		for i, s in stops do
			order[s] = i
		end
		table.sort(stops, function(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return (order[a] :: number) < (order[b] :: number)
		end)
		if #stops > MAX_STOPS then
			for i = #stops, MAX_STOPS + 1, -1 do
				stops[i] = nil
			end
			table.insert(ctx.warnings, "gradient on " .. id .. " truncated to " .. MAX_STOPS .. " stops")
		end
		return { kind = "linear", rotation = num(ctx, id, "rotation", lin.rotation, 0), stops = stops }
	elseif raw.image ~= nil or raw.asset ~= nil then
		if raw.image ~= nil and type(raw.image) ~= "string" then
			fail(ctx, "bad image fill on " .. id)
			return nil
		end
		local asset = raw.asset
		if asset ~= nil and not (type(asset) == "string" and string.match(asset, "^rbxassetid://%d+$")) then
			table.insert(ctx.warnings, "asset on " .. id .. " ignored: expected rbxassetid://<number>")
			asset = nil
		end
		if asset == nil and raw.image == nil then
			return nil
		end
		local tile = raw.tile
		local sized = type(tile) == "table" and finite(tile[1]) and finite(tile[2]) and tile[1] > 0 and tile[2] > 0
		if raw.scale == "tile" and not sized then
			table.insert(ctx.warnings, "tile on " .. id .. " dropped: invalid size")
		end
		return { kind = "image", hash = raw.image, asset = asset, scale = str(raw.scale, "fill"), tile = if sized then { tile[1], tile[2] } else nil }
	elseif raw.token ~= nil then
		if type(raw.token) ~= "string" then
			fail(ctx, "bad token fill on " .. id)
			return nil
		end
		return { kind = "token", name = raw.token }
	end
	fail(ctx, "unknown fill on " .. id)
	return nil
end

local function normalizeStroke(ctx: Ctx, id: string, raw: any): any
	if type(raw) ~= "table" then
		fail(ctx, "bad stroke on " .. id)
		return nil
	end
	local paint = normalizeFill(ctx, id, raw.paint)
	local out: any = {
		weight = num(ctx, id, "stroke weight", raw.weight, 1, 0),
		align = enum(ctx, id, raw.align, STROKE_ALIGN, "I"),
	}
	if paint and paint.kind == "solid" then
		out.hex, out.a = paint.hex, paint.a
	elseif paint and paint.kind == "linear" then
		out.hex, out.a = paint.stops[1].hex, paint.stops[1].a
		out.linear = paint
	else
		if paint then
			table.insert(ctx.warnings, "stroke paint on " .. id .. " unsupported, dropped")
		end
		return nil
	end
	return out
end

local function normalizeEffects(ctx: Ctx, id: string, raw: any): { Effect }
	local out: { Effect } = {}
	if raw == nil then
		return out
	end
	if type(raw) ~= "table" then
		fail(ctx, "bad effects on " .. id)
		return out
	end
	for _, e in raw do
		local shadow = if type(e) == "table" then (e.dropShadow or e.innerShadow) else nil
		if type(shadow) == "table" then
			table.insert(out, {
				kind = if e.dropShadow then "dropShadow" else "innerShadow",
				hex = hexOr(ctx, id, shadow.color, "000000"),
				a = alpha(ctx, id, shadow.a),
				x = num(ctx, id, "shadow x", shadow.x, 0),
				y = num(ctx, id, "shadow y", shadow.y, 0),
				blur = num(ctx, id, "shadow blur", shadow.blur, 0, 0),
				spread = num(ctx, id, "shadow spread", shadow.spread, 0),
			})
		elseif type(e) == "table" and e.blur ~= nil then
			table.insert(out, { kind = "blur", blur = num(ctx, id, "blur", e.blur, 0, 0) })
		else
			table.insert(ctx.warnings, "unknown effect on " .. id .. " dropped")
		end
	end
	return out
end

local function pair(ctx: Ctx, id: string, v: any, default: { string }): { string }
	if v == nil then
		return { default[1], default[2] }
	end
	if type(v) == "table" and type(v[1]) == "string" and type(v[2]) == "string" then
		return { v[1], v[2] }
	end
	table.insert(ctx.warnings, "bad alignment on " .. id)
	return { default[1], default[2] }
end

local function normalizeText(ctx: Ctx, id: string, raw: any): any
	if type(raw) ~= "table" then
		fail(ctx, "bad text on " .. id)
		return nil
	end
	local font = if type(raw.font) == "table" then raw.font else {}
	local stroke = nil
	if raw.stroke ~= nil then
		if type(raw.stroke) == "table" then
			stroke = {
				hex = hexOr(ctx, id, raw.stroke.color, nil),
				a = alpha(ctx, id, raw.stroke.a),
				weight = num(ctx, id, "text stroke weight", raw.stroke.weight, 1, 0),
			}
		else
			fail(ctx, "bad text stroke on " .. id)
		end
	end
	return {
		chars = str(raw.chars, ""),
		family = str(font.family, ""),
		weight = num(ctx, id, "font weight", font.weight, 400),
		italic = font.italic == true,
		size = num(ctx, id, "font size", raw.size, 14, 0),
		hex = hexOr(ctx, id, raw.color, "000000"),
		a = alpha(ctx, id, raw.a),
		token = if type(raw.token) == "string" then raw.token else nil,
		align = pair(ctx, id, raw.align, { "LEFT", "CENTER" }),
		stroke = stroke,
	}
end

local function normalizeLayout(ctx: Ctx, id: string, raw: any): any
	if type(raw) ~= "table" then
		fail(ctx, "bad layout on " .. id)
		return nil
	end
	local padding = { 0, 0, 0, 0 }
	if raw.padding ~= nil then
		local p = raw.padding
		if type(p) == "table" and #p == 4 and finite(p[1]) and finite(p[2]) and finite(p[3]) and finite(p[4]) and p[1] >= 0 and p[2] >= 0 and p[3] >= 0 and p[4] >= 0 then
			padding = { p[1], p[2], p[3], p[4] }
		else
			fail(ctx, "bad padding on " .. id)
		end
	end
	return {
		dir = enum(ctx, id, raw.dir, DIRECTIONS, "V"),
		gap = num(ctx, id, "gap", raw.gap, 0, 0),
		padding = padding,
		align = pair(ctx, id, raw.align, { "MIN", "MIN" }),
		wrap = raw.wrap == true,
	}
end

local function normalizeAxes(ctx: Ctx, id: string, raw: any, set: { [string]: boolean }, default: string): any
	if raw == nil then
		return nil
	end
	if type(raw) ~= "table" then
		fail(ctx, "bad axes on " .. id)
		return nil
	end
	return { h = enum(ctx, id, raw.h, set, default), v = enum(ctx, id, raw.v, set, default) }
end

local function normalizeComponent(ctx: Ctx, id: string, raw: any): any
	if raw == nil then
		return nil
	end
	if type(raw) ~= "table" or type(raw.key) ~= "string" then
		table.insert(ctx.warnings, "component on " .. id .. " dropped")
		return nil
	end
	local variant = {}
	if type(raw.variant) == "table" then
		for k, v in raw.variant do
			if type(k) == "string" and type(v) == "string" then
				variant[k] = v
			end
		end
	end
	return { key = raw.key, name = str(raw.name, raw.key), variant = variant, main = raw.main == true }
end

local function fourNumbers(ctx: Ctx, id: string, field: string, raw: any): { number }?
	if type(raw) == "table" and #raw == 4 then
		for i = 1, 4 do
			if not finite(raw[i]) or raw[i] < 0 then
				fail(ctx, "bad " .. field .. " on " .. id)
				return nil
			end
		end
		return { raw[1], raw[2], raw[3], raw[4] }
	end
	fail(ctx, "bad " .. field .. " on " .. id)
	return nil
end

local function normalizeRadius(ctx: Ctx, id: string, raw: any): { number }?
	if raw == nil then
		return nil
	end
	if finite(raw) and raw >= 0 then
		return { raw, raw, raw, raw }
	end
	return fourNumbers(ctx, id, "radius", raw)
end

local function normalizeNode(ctx: Ctx, raw: any): Node?
	if type(raw) ~= "table" or type(raw.id) ~= "string" then
		fail(ctx, "node without id")
		return nil
	end
	local id: string = raw.id
	ctx.count += 1
	if ctx.count > MAX_NODES then
		if ctx.count == MAX_NODES + 1 then
			fail(ctx, "more than " .. MAX_NODES .. " nodes")
		end
		return nil
	end
	if ctx.ids[id] then
		fail(ctx, "duplicate id " .. id)
		return nil
	end
	ctx.ids[id] = true

	local box = raw.box
	if type(box) ~= "table" or #box ~= 4 or not (finite(box[1]) and finite(box[2]) and finite(box[3]) and finite(box[4])) then
		fail(ctx, "bad box on " .. id)
		return nil
	end
	if box[3] < 0 or box[4] < 0 then
		fail(ctx, "negative size on " .. id)
		return nil
	end
	if type(raw.kind) ~= "string" or not KINDS[raw.kind] then
		fail(ctx, "unknown kind " .. tostring(raw.kind) .. " on " .. id)
		return nil
	end

	local fills: { Fill } = {}
	if raw.fill ~= nil then
		if type(raw.fill) ~= "table" then
			fail(ctx, "bad fill on " .. id)
		else
			for _, f in raw.fill do
				local nf = normalizeFill(ctx, id, f)
				if nf then
					table.insert(fills, nf)
				end
			end
		end
	end

	local children: { Node } = {}
	if raw.children ~= nil then
		if type(raw.children) ~= "table" then
			fail(ctx, "bad children on " .. id)
		else
			for _, c in raw.children do
				local nc = normalizeNode(ctx, c)
				if nc then
					table.insert(children, nc)
				end
			end
		end
	end

	return {
		id = id,
		name = str(raw.name, id),
		kind = raw.kind,
		box = { box[1], box[2], box[3], box[4] },
		rotation = num(ctx, id, "rotation", raw.rotation, 0),
		opacity = clamp01(num(ctx, id, "opacity", raw.opacity, 1)),
		visible = raw.visible ~= false,
		clip = raw.clip == true,
		fills = fills,
		tint = if raw.tint ~= nil then hexOr(ctx, id, raw.tint, nil) else nil,
		stroke = if raw.stroke ~= nil then normalizeStroke(ctx, id, raw.stroke) else nil,
		radius = normalizeRadius(ctx, id, raw.radius),
		effects = normalizeEffects(ctx, id, raw.effects),
		layout = if raw.layout ~= nil then normalizeLayout(ctx, id, raw.layout) else nil,
		sizing = normalizeAxes(ctx, id, raw.sizing, SIZING, "fixed"),
		constraints = normalizeAxes(ctx, id, raw.constraints, CONSTRAINTS, "MIN"),
		absolute = raw.absolute == true,
		text = if raw.text ~= nil then normalizeText(ctx, id, raw.text) else nil,
		component = normalizeComponent(ctx, id, raw.component),
		slice = if raw.slice ~= nil then fourNumbers(ctx, id, "slice", raw.slice) else nil,
		children = children,
	}
end

function Spec.isSource(node: Node): boolean
	return (node.component ~= nil and node.component.main) or node.name == Spec.COMPONENTS_PAGE
end

local function normalizeTokens(ctx: Ctx, raw: any): { [string]: Linear }
	local out: { [string]: Linear } = {}
	if type(raw) ~= "table" then
		return out
	end
	local names: { string } = {}
	for name in raw do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		local scratch: Ctx = { errors = {}, warnings = ctx.warnings, ids = {}, count = 0 }
		local fill = normalizeFill(scratch, "token " .. name, { linear = raw[name] })
		if fill and fill.kind == "linear" and #scratch.errors == 0 then
			out[name] = fill
		else
			table.insert(ctx.warnings, "gradient token '" .. name .. "' dropped: invalid")
		end
	end
	return out
end

local function normalizeImages(ctx: Ctx, raw: any): { [string]: { w: number, h: number, asset: string? } }
	local out = {}
	if raw == nil then
		return out
	end
	if type(raw) ~= "table" then
		fail(ctx, "bad images")
		return out
	end
	for hash, info in raw do
		if type(hash) == "string" and type(info) == "table" and finite(info.w) and finite(info.h) then
			if info.w > 0 and info.h > 0 then
				out[hash] = { w = info.w, h = info.h, asset = if type(info.asset) == "string" then info.asset else nil }
				if type(info.error) == "string" then
					table.insert(ctx.warnings, string.format("%s: falha no envio (%s)", string.sub(hash, 1, 8), string.sub(info.error, 1, 200)))
				end
			else
				table.insert(ctx.warnings, "image " .. hash .. " dropped: invalid size")
			end
		else
			fail(ctx, "bad image entry")
		end
	end
	return out
end

local function sourceWarnings(raw: any): { string }
	local out: { string } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, message in raw do
		if type(message) == "string" and #out < MAX_SOURCE_WARNINGS then
			table.insert(out, string.sub(message, 1, MAX_WARNING_LENGTH))
		end
	end
	return out
end

local function parseUnsafe(raw: any): (Doc?, { string })
	if type(raw) ~= "table" then
		return nil, { "spec is not an object" }
	end
	local version = raw.version
	if not finite(version) or version ~= math.floor(version) or version < 1 or version > Spec.SUPPORTED_VERSION then
		return nil, { "unsupported version " .. tostring(version) }
	end
	if raw.root == nil then
		return nil, { "missing root" }
	end
	local ctx: Ctx = { errors = {}, warnings = {}, ids = {}, count = 0 }
	local root = normalizeNode(ctx, raw.root)
	local images = normalizeImages(ctx, raw.images)
	if #ctx.errors > 0 or not root then
		return nil, ctx.errors
	end
	local sourceList = sourceWarnings(raw.warnings)
	local tokens = if type(raw.tokens) == "table" then raw.tokens else {}
	local gradients = normalizeTokens(ctx, tokens.gradients)
	if root.component and root.component.main then
		table.insert(ctx.warnings, root.name .. ": componente principal na raiz é construído como tela, não como template")
	end
	return {
		version = version,
		source = if type(raw.source) == "table" then deepCopy(raw.source, 0) else {},
		root = root,
		images = images,
		tokens = { gradients = gradients },
		warnings = table.move(ctx.warnings, 1, #ctx.warnings, #sourceList + 1, sourceList),
	},
		ctx.errors
end

function Spec.imageId(doc: Doc, fill: ImageFill): string?
	if fill.asset then
		return fill.asset
	end
	local entry = if fill.hash then doc.images[fill.hash] else nil
	local asset = entry and entry.asset
	return if type(asset) == "string" and string.match(asset, "^rbxassetid://") then asset else nil
end

function Spec.parse(raw: any): (Doc?, { string })
	local ok, doc, errors = pcall(parseUnsafe, raw)
	if not ok then
		return nil, { "malformed spec: " .. tostring(doc) }
	end
	return doc, errors
end

return Spec
