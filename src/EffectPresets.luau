--!strict
local EffectPresets = {}

export type ShadowLayer = { y: number, blur: number, transparency: number }
export type InnerShadow = { top: number, fade: number, rim: number, rimTransparency: number }
export type GlowLayer = { blur: number, transparency: number }

EffectPresets.SHADOW_ORDER = { "soft", "medium", "deep", "float", "inner" }
EffectPresets.SHADOW_DEFAULT = "medium"
EffectPresets.SHADOWS = {
	soft = {
		{ y = 2, blur = 4, transparency = 0.75 },
	},
	medium = {
		{ y = 4, blur = 8, transparency = 0.78 },
		{ y = 1, blur = 2, transparency = 0.88 },
	},
	deep = {
		{ y = 8, blur = 16, transparency = 0.8 },
		{ y = 2, blur = 4, transparency = 0.86 },
	},
	float = {
		{ y = 16, blur = 32, transparency = 0.86 },
		{ y = 4, blur = 8, transparency = 0.9 },
	},
} :: { [string]: { ShadowLayer } }
EffectPresets.INNER_PRESET = "inner"
EffectPresets.INNER = { top = 0.82, fade = 0.25, rim = 1, rimTransparency = 0.85 } :: InnerShadow

EffectPresets.NEON_COLOR = "00e5ff"
EffectPresets.NEON_LAYERS = 2
EffectPresets.NEON_MAX_LAYERS = 4
EffectPresets.NEON_STROKE = 2
local NEON_BLUR = 4
local NEON_TRANSPARENCY = 0.3
local NEON_TRANSPARENCY_STEP = 0.15

function EffectPresets.neonLayers(count: number): { GlowLayer }
	local out: { GlowLayer } = {}
	for index = 1, count do
		table.insert(out, {
			blur = NEON_BLUR * 2 ^ (index - 1),
			transparency = NEON_TRANSPARENCY + NEON_TRANSPARENCY_STEP * (index - 1),
		})
	end
	return out
end

EffectPresets.MOTIONS = { "offset", "rotation", "scale" }
-- AVISO: padrões em lockstep com os de QuadroAnimatedGradient e QuadroShine em Import/RuntimeSource.luau.
EffectPresets.MOTION_DEFAULT = "offset"
EffectPresets.MOTION_SPEED = 0.5
EffectPresets.MOTION_RANGE = 1
EffectPresets.SHINE_INTERVAL = 2.4
EffectPresets.SHINE_DURATION = 0.6
EffectPresets.SHINE_WIDTH = 0.18
EffectPresets.SHINE_ANGLE = 20

local SLICE_PERCENT = 100
EffectPresets.SLICE_PERCENT = SLICE_PERCENT
EffectPresets.SLICE_SCALE_MIN = 10
EffectPresets.SLICE_SCALE_MAX = 400
EffectPresets.SLICE_SCALE_STEP = 10

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function EffectPresets.sliceRect(l: number, t: number, r: number, b: number, w: number, h: number): ({ number }?, string?)
	if not (finite(w) and finite(h)) or w <= 0 or h <= 0 then
		return nil, "slice_error_size"
	end
	for _, margin in { l, t, r, b } do
		if not finite(margin) or margin < 0 then
			return nil, "slice_error_margin"
		end
	end
	if l + r >= w then
		return nil, "slice_error_width"
	end
	if t + b >= h then
		return nil, "slice_error_height"
	end
	return { l, t, w - r, h - b }, nil
end

export type SliceFields = { l: number, t: number, r: number, b: number, scale: number, w: number?, h: number?, images: number }

function EffectPresets.sliceArgs(fields: SliceFields): { any }
	local args: { any } = { fields.l, fields.t, fields.r, fields.b, fields.scale / SLICE_PERCENT }
	if fields.images == 1 and fields.w ~= nil and fields.h ~= nil then
		table.insert(args, fields.w)
		table.insert(args, fields.h)
	end
	return args
end

return EffectPresets
