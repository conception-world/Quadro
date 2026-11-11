--!strict
local BuilderMath = {}

export type Vec = { number }
export type Point = { position: Vec, left: Vec, right: Vec }
export type Box = { x: number, y: number, w: number, h: number }

BuilderMath.PRESETS = { "line", "curve", "arc", "wave" }
BuilderMath.PRESET_DEFAULT = "curve"
BuilderMath.DRAG_PRESETS = { "header", "free", "bounded" }
BuilderMath.DRAG_DEFAULT = "header"
BuilderMath.SAMPLE_MIN = 2
BuilderMath.SAMPLE_MAX = 64
BuilderMath.SAMPLE_DEFAULT = 16
BuilderMath.THICKNESS_MIN = 1
BuilderMath.THICKNESS_MAX = 32
BuilderMath.THICKNESS_DEFAULT = 4
BuilderMath.COLOR_DEFAULT = "00e5ff"
BuilderMath.COLORS = { "00e5ff", "ffffff", "ffd166", "ef476f", "06d6a0", "8338ec" }
BuilderMath.BUTTON_GAP = 0.03
BuilderMath.BUTTON_HEIGHT = 0.14
BuilderMath.BUTTON_INSET = 0.04
BuilderMath.BUTTON_TEXT_MAX = 28
BuilderMath.BUTTON_TEXT_MIN = 8

local CIRCLE_HANDLE = 0.5523
local WAVE_HANDLE = 0.36
local WAVE_STEPS = 3
local WAVE_HIGH = 0.8
local WAVE_LOW = 0.2

local function point(x: number, y: number, left: Vec?, right: Vec?): Point
	return { position = { x, y }, left = left or { 0, 0 }, right = right or { 0, 0 } }
end

local function line(): { Point }
	return { point(0, 1), point(1, 0) }
end

local function curve(): { Point }
	return {
		point(0, 1, nil, { 0, -CIRCLE_HANDLE }),
		point(1, 0, { -CIRCLE_HANDLE, 0 }, nil),
	}
end

local function arc(): { Point }
	local half = 0.5
	return {
		point(0, 1, nil, { 0, -CIRCLE_HANDLE }),
		point(half, 0, { -CIRCLE_HANDLE * half, 0 }, { CIRCLE_HANDLE * half, 0 }),
		point(1, 1, { 0, -CIRCLE_HANDLE }, nil),
	}
end

local function wave(): { Point }
	local points: { Point } = {}
	local step = 1 / WAVE_STEPS
	local handle = WAVE_HANDLE * step
	for index = 0, WAVE_STEPS do
		local y = if index % 2 == 0 then WAVE_HIGH else WAVE_LOW
		local left: Vec? = if index > 0 then { -handle, 0 } else nil
		local right: Vec? = if index < WAVE_STEPS then { handle, 0 } else nil
		table.insert(points, point(index * step, y, left, right))
	end
	return points
end

local BUILDERS: { [string]: () -> { Point } } = { line = line, curve = curve, arc = arc, wave = wave }

function BuilderMath.controlPoints(preset: string): { Point }?
	local build = BUILDERS[preset]
	return if build then build() else nil
end

function BuilderMath.validCount(count: any): boolean
	return type(count) == "number"
		and count == math.floor(count)
		and count >= BuilderMath.SAMPLE_MIN
		and count <= BuilderMath.SAMPLE_MAX
end

function BuilderMath.sampleTimes(count: number): { number }
	local times: { number } = {}
	for index = 0, count - 1 do
		table.insert(times, index / (count - 1))
	end
	return times
end

function BuilderMath.bounds(boxes: { Box }): Box
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, box in boxes do
		minX = math.min(minX, box.x)
		minY = math.min(minY, box.y)
		maxX = math.max(maxX, box.x + box.w)
		maxY = math.max(maxY, box.y + box.h)
	end
	return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

function BuilderMath.navBoxes(area: Box): (Box, Box)
	local inset = math.min(area.w, area.h) * BuilderMath.BUTTON_INSET
	local gap = area.w * BuilderMath.BUTTON_GAP
	local width = (area.w - 2 * inset - gap) / 2
	local height = area.h * BuilderMath.BUTTON_HEIGHT
	local top = area.y + area.h - inset - height
	return { x = area.x + inset, y = top, w = width, h = height }, { x = area.x + inset + width + gap, y = top, w = width, h = height }
end

return BuilderMath
