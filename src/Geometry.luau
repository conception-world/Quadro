--!strict
local Geometry = {}

function Geometry.round4(n: number): number
	return math.round(n * 10000) / 10000
end

function Geometry.toScale(px: number, refPx: number): number
	if refPx == 0 then
		return 0
	end
	return Geometry.round4(px / refPx)
end

function Geometry.axisToScale(scale: number, offset: number, refPx: number): (number, number)
	if refPx <= 0 then
		return scale, offset
	end
	return Geometry.toScale(scale * refPx + offset, refPx), 0
end

function Geometry.axisToOffset(scale: number, offset: number, refPx: number): (number, number)
	if refPx <= 0 then
		return scale, offset
	end
	return 0, math.round(scale * refPx + offset)
end

function Geometry.pixelSnap(offset: number): number
	return math.round(offset)
end

function Geometry.anchorShift(positionPx: number, sizePx: number, fromAnchor: number, toAnchor: number): number
	return positionPx + sizePx * (toAnchor - fromAnchor)
end

function Geometry.centerPosition(x: number, w: number, anchor: number, parentPx: number): number
	return Geometry.toScale(x + w * anchor, parentPx)
end

function Geometry.cornerScale(radiusPx: number, w: number, h: number): number
	local side = math.min(w, h)
	if side <= 0 then
		return 0
	end
	return math.min(0.5, Geometry.round4(radiusPx / side))
end

function Geometry.strokeScale(weightPx: number, w: number, h: number): number
	local side = math.min(w, h)
	if side <= 0 then
		return 0
	end
	return Geometry.round4(weightPx / side)
end

function Geometry.solveAxis(
	scale: number,
	offset: number,
	absolutePx: number,
	refPx: number,
	unit: number,
	preferScale: boolean
): (number, number)
	if refPx <= 0 or unit <= 0 then
		return scale, offset
	end
	if scale ~= 0 or preferScale then
		return Geometry.toScale(absolutePx, refPx), 0
	end
	return 0, math.round(absolutePx / unit)
end

function Geometry.innerSize(sizePx: number, padStartPx: number, padEndPx: number): number
	return math.max(0, sizePx - padStartPx - padEndPx)
end

function Geometry.hybridSplit(absolutePx: number, refPx: number, scalePortion: number, unit: number?): (number, number)
	local step = unit or 1
	if refPx <= 0 or step <= 0 then
		return 0, math.round(absolutePx / math.max(step, 1e-6))
	end
	local scale = Geometry.round4(scalePortion * absolutePx / refPx)
	return scale, math.round((absolutePx - scale * refPx) / step)
end

export type CornerMode = "px" | "scale" | "percent" | "hybrid"

function Geometry.cornerPixels(scale: number, offset: number, w: number, h: number, unit: number?): number
	local side = math.min(w, h)
	return math.max(0, math.min(scale * side + offset * (unit or 1), side / 2))
end

function Geometry.cornerConvert(
	scale: number,
	offset: number,
	w: number,
	h: number,
	mode: CornerMode,
	value: number?,
	unit: number?
): (number, number)
	local step = unit or 1
	local side = math.min(w, h)
	if side <= 0 or step <= 0 then
		return scale, offset
	end
	local px = Geometry.cornerPixels(scale, offset, w, h, step)
	if mode == "px" then
		return 0, if value then value else math.round(px / step)
	elseif mode == "scale" then
		return if value then value else math.min(0.5, Geometry.round4(px / side)), 0
	elseif mode == "percent" then
		return if value then value / 100 else math.min(0.5, Geometry.round4(px / side)), 0
	end
	return Geometry.hybridSplit(px, side, value or 0.7, step)
end

function Geometry.paddingConvert(scale: number, offset: number, refPx: number, unit: number, toScale: boolean): (number, number)
	if refPx <= 0 or unit <= 0 then
		return scale, offset
	end
	local px = scale * refPx + offset * unit
	if toScale then
		return Geometry.round4(px / refPx), 0
	end
	return 0, math.round(px / unit)
end

function Geometry.clampTextRange(minSize: number, maxSize: number): (number, number)
	local low = math.clamp(math.round(minSize), 1, 100)
	return low, math.clamp(math.round(maxSize), low, 100)
end

function Geometry.sizeLimits(w: number, h: number, minFactor: number, maxFactor: number): (number, number, number, number)
	return math.round(w * minFactor), math.round(h * minFactor), math.round(w * maxFactor), math.round(h * maxFactor)
end

export type Span = { pos: number, size: number }
export type Box = { x: number, y: number, w: number, h: number }
export type AlignEdge = "min" | "center" | "max"

function Geometry.alignAxis(edge: AlignEdge, pos: number, size: number, refMin: number, refMax: number): number
	if edge == "min" then
		return refMin
	elseif edge == "max" then
		return refMax - size
	elseif edge == "center" then
		return (refMin + refMax) / 2 - size / 2
	end
	return pos
end

local function sortedIndices(spans: { Span }): { number }
	local order: { number } = {}
	for index = 1, #spans do
		order[index] = index
	end
	table.sort(order, function(a: number, b: number)
		local left, right = spans[a].pos, spans[b].pos
		if left ~= right then
			return left < right
		end
		return a < b
	end)
	return order
end

function Geometry.distributeAxis(spans: { Span }): { number }
	local count = #spans
	local out: { number } = {}
	for index, span in spans do
		out[index] = span.pos
	end
	if count < 3 then
		return out
	end
	local order = sortedIndices(spans)
	local first, last = spans[order[1]], spans[order[count]]
	local used = 0
	for _, span in spans do
		used += span.size
	end
	local gap = (last.pos + last.size - first.pos - used) / (count - 1)
	local cursor = first.pos
	for _, index in order do
		out[index] = cursor
		cursor += spans[index].size + gap
	end
	return out
end

function Geometry.spacingAxis(spans: { Span }, gap: number?): { number }
	local count = #spans
	local out: { number } = {}
	for index, span in spans do
		out[index] = span.pos
	end
	if count < 2 then
		return out
	end
	local order = sortedIndices(spans)
	local first, last = spans[order[1]], spans[order[count]]
	local used = 0
	for _, span in spans do
		used += span.size
	end
	local step = gap or (last.pos + last.size - first.pos - used) / (count - 1)
	local cursor = first.pos
	for _, index in order do
		out[index] = cursor
		cursor += spans[index].size + step
	end
	return out
end

export type GridGuess = { order: { number }, cellW: number, cellH: number, gapX: number, gapY: number, aspect: number? }

local ASPECT_TOLERANCE = 0.05

function Geometry.gridGuess(boxes: { Box }): GridGuess
	local count = #boxes
	local sumW, sumH = 0, 0
	for _, box in boxes do
		sumW += box.w
		sumH += box.h
	end
	local cellW, cellH = sumW / math.max(count, 1), sumH / math.max(count, 1)
	local sorted: { number } = {}
	for index = 1, count do
		sorted[index] = index
	end
	table.sort(sorted, function(a: number, b: number)
		if boxes[a].y ~= boxes[b].y then
			return boxes[a].y < boxes[b].y
		end
		return boxes[a].x < boxes[b].x
	end)
	local order: { number } = {}
	local row: { number } = {}
	local rowY = 0
	local function flush()
		table.sort(row, function(a: number, b: number)
			return boxes[a].x < boxes[b].x
		end)
		for _, index in row do
			table.insert(order, index)
		end
		row = {}
	end
	for _, index in sorted do
		if #row > 0 and boxes[index].y - rowY > cellH / 2 then
			flush()
		end
		if #row == 0 then
			rowY = boxes[index].y
		end
		table.insert(row, index)
	end
	flush()
	local gapX, gapY = math.huge, math.huge
	for a = 1, count do
		for b = 1, count do
			if a ~= b then
				local left, right = boxes[a], boxes[b]
				local overlapY = math.min(left.y + left.h, right.y + right.h) - math.max(left.y, right.y)
				local overlapX = math.min(left.x + left.w, right.x + right.w) - math.max(left.x, right.x)
				local dx = right.x - (left.x + left.w)
				local dy = right.y - (left.y + left.h)
				if overlapY > cellH / 2 and dx >= 0 then
					gapX = math.min(gapX, dx)
				end
				if overlapX > cellW / 2 and dy >= 0 then
					gapY = math.min(gapY, dy)
				end
			end
		end
	end
	local aspect: number? = nil
	if count > 0 and cellH > 0 then
		local mean = cellW / cellH
		aspect = mean
		for _, box in boxes do
			if box.h <= 0 or math.abs(box.w / box.h - mean) > mean * ASPECT_TOLERANCE then
				aspect = nil
				break
			end
		end
	end
	return {
		order = order,
		cellW = cellW,
		cellH = cellH,
		gapX = if gapX == math.huge then 0 else gapX,
		gapY = if gapY == math.huge then 0 else gapY,
		aspect = aspect,
	}
end

return Geometry
