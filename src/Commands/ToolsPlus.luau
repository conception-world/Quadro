--!strict
local CollectionService = game:GetService("CollectionService")
local Geometry = require(script.Parent.Parent.Geometry)
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Installer = require(script.Parent.Parent.Runtime.Installer)
local Selection = require(script.Parent.Parent.Studio.Selection)
local Text = require(script.Parent.Text)

local ToolsPlus = {}

local STROKE_TAG = "QuadroStrokeScale"
local SCALE_ROOT_TAG = "QuadroScaleRoot"
local SCALE_MODES = { min = true, width = true, height = true }
local SCALE_MIN = 0.5
local SCALE_MAX = 2
local STROKE_MODES = { px = true, object = true, screen = true }
local CORNER_MODES = { px = true, scale = true, percent = true, hybrid = true }
local HYBRID_TARGETS = { size = true, position = true, both = true }

local function modifiers(className: string): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(instance: Instance)
		local parent = instance.Parent
		if not seen[instance] and parent ~= nil and parent:IsA("GuiObject") then
			seen[instance] = true
			table.insert(found, instance)
		end
	end
	for _, selected in game:GetService("Selection"):Get() do
		if selected:IsA(className) then
			add(selected)
		end
	end
	for _, gui in Selection.guiTargets() do
		for _, child in gui:GetChildren() do
			if child:IsA(className) then
				add(child)
			end
		end
	end
	return found
end

local function scaleRoots(): { Instance }
	local found: { Instance } = {}
	for _, selected in game:GetService("Selection"):Get() do
		if selected:IsA("GuiObject") or selected:IsA("ScreenGui") then
			table.insert(found, selected)
		end
	end
	return found
end

local function hybridParts(gui: GuiObject, which: string): (boolean, boolean)
	local layout = Gui.placingLayout(gui)
	local doSize = which ~= "position" and not (layout ~= nil and layout:IsA("UIGridLayout"))
	local doPosition = which ~= "size" and layout == nil
	return doSize, doPosition
end

local function hybridTargets(): { GuiObject }
	local found: { GuiObject } = {}
	for _, gui in Selection.guiTargets() do
		if Gui.renderedParent(gui) ~= nil then
			table.insert(found, gui)
		end
	end
	return found
end

local function hybridReady(): boolean
	for _, gui in hybridTargets() do
		local doSize, doPosition = hybridParts(gui, "both")
		if doSize or doPosition then
			return true
		end
	end
	return false
end

function ToolsPlus.applicable(): { [string]: boolean }
	return {
		hybrid = hybridReady(),
		stroke = #modifiers("UIStroke") > 0,
		corner = #modifiers("UICorner") > 0,
		padding = #modifiers("UIPadding") > 0,
		text = Text.any(),
		responsive = #Selection.guiTargets() > 0,
		scaleRoot = #scaleRoots() > 0,
	}
end

local function countedKey(ctx: any, key: string, count: number): string
	local one = key .. "_one"
	if count == 1 and ctx.t(one) ~= one then
		return one
	end
	return key
end

function ToolsPlus.announceRuntime(ctx: any, runtime: Installer.Report?)
	if runtime == nil then
		return
	end
	if runtime.module == "locked" or runtime.loader == "locked" then
		ctx.notify(ctx.t("result_runtime_locked"), "warning")
	end
	if runtime.module == "conflict" or runtime.loader == "conflict" then
		ctx.notify(ctx.t("result_runtime_conflict"), "warning")
	end
	if runtime.duplicates > 0 then
		ctx.notify(ctx.t("result_runtime_duplicates", runtime.duplicates), "warning")
	end
end

local function execute(
	ctx: any,
	id: string,
	targets: { any },
	ready: ((target: any) -> boolean | string)?,
	apply: (target: any) -> boolean,
	install: boolean?
): any
	if #targets == 0 then
		return { ok = false, count = 0, message = "error_no_applicable" }
	end
	local reasons: { [string]: number } = {}
	local order: { string } = {}
	local function skip(key: string)
		if reasons[key] == nil then
			reasons[key] = 0
			table.insert(order, key)
		end
		reasons[key] += 1
	end
	local eligible: { any } = {}
	for _, target in targets do
		local verdict: any = if ready == nil then true else ready(target)
		if verdict == true then
			table.insert(eligible, target)
		else
			skip(if type(verdict) == "string" then verdict else "result_tool_skipped")
		end
	end
	local done = 0
	if #eligible == 0 then
		local first = order[1]
		return { ok = false, count = 0, message = countedKey(ctx, first, reasons[first]), args = { reasons[first] } }
	end
	local runtime: Installer.Report? = nil
	local ok, cause = History.record(id, function()
		for _, target in eligible do
			if apply(target) then
				done += 1
			else
				skip("result_tool_skipped")
			end
		end
		if install and done > 0 then
			runtime = Installer.install()
		end
		return done
	end, { nested = ctx.fromHook })
	if not ok then
		if cause == "busy" then
			return { ok = false, count = 0, message = "error_busy" }
		end
		warn("[Quadro] " .. id .. ": " .. tostring(cause))
		return { ok = false, count = 0, message = "error_command_failed" }
	end
	if done == 0 then
		local first = order[1]
		return { ok = false, count = 0, message = countedKey(ctx, first, reasons[first]), args = { reasons[first] } }
	end
	ctx.notify(ctx.t("result_tool_applied", done), "success")
	for _, key in order do
		ctx.notify(ctx.t(countedKey(ctx, key, reasons[key]), reasons[key]), "warning")
	end
	ToolsPlus.announceRuntime(ctx, runtime)
	return { ok = true, count = done }
end

ToolsPlus.execute = execute

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function hybridPosition(gui: GuiObject, portionX: number, portionY: number)
	local _, box, unit = Gui.contentBox(Gui.renderedParent(gui))
	local position = gui.Position
	local sx, ox = Geometry.hybridSplit(position.X.Scale * box.X + position.X.Offset * unit, box.X, portionX, unit)
	local sy, oy = Geometry.hybridSplit(position.Y.Scale * box.Y + position.Y.Offset * unit, box.Y, portionY, unit)
	gui.Position = UDim2.new(sx, ox, sy, oy)
end

local function hybridSize(gui: GuiObject, portionX: number, portionY: number)
	local _, box, unit = Gui.contentBox(Gui.renderedParent(gui))
	local refs = Gui.sizeRefs(gui, box)
	local size = gui.Size
	local sx, ox = Geometry.hybridSplit(size.X.Scale * refs.X + size.X.Offset * unit, refs.X, portionX, unit)
	local sy, oy = Geometry.hybridSplit(size.Y.Scale * refs.Y + size.Y.Offset * unit, refs.Y, portionY, unit)
	gui.Size = UDim2.new(sx, ox, sy, oy)
end

local function strokePixels(stroke: UIStroke, parent: GuiObject): (number, number, number)
	local unit = Gui.unitScale(parent)
	local abs = parent.AbsoluteSize
	local side = math.min(abs.X, abs.Y)
	if stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
		return if unit > 0 then stroke.Thickness * side / unit else 0, side, unit
	end
	return stroke.Thickness, side, unit
end

local function round2(value: number): number
	return math.round(value * 100) / 100
end

local function clearStrokeScale(stroke: UIStroke)
	if not CollectionService:HasTag(stroke, STROKE_TAG) then
		return
	end
	CollectionService:RemoveTag(stroke, STROKE_TAG)
	for _, name in { "QuadroStrokeBase", "QuadroStrokeMode", "QuadroStrokeMin", "QuadroStrokeMax", "QuadroReference" } do
		stroke:SetAttribute(name, nil)
	end
end

local function strokeReady(stroke: UIStroke, mode: string): boolean
	local parent = stroke.Parent :: GuiObject
	local abs = parent.AbsoluteSize
	local side = math.min(abs.X, abs.Y)
	if mode == "object" or stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
		return side > 0 and Gui.unitScale(parent) > 0
	end
	return true
end

local function convertStroke(stroke: UIStroke, mode: string, min: number?, max: number?): boolean
	local parent = stroke.Parent :: GuiObject
	local px, side, unit = strokePixels(stroke, parent)
	if mode == "object" then
		if side <= 0 or unit <= 0 then
			return false
		end
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.Thickness = px * unit / side
		clearStrokeScale(stroke)
		return true
	end
	if stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize and (side <= 0 or unit <= 0) then
		return false
	end
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	stroke.Thickness = round2(px)
	if mode == "px" then
		clearStrokeScale(stroke)
		return true
	end
	local camera = workspace.CurrentCamera
	stroke:SetAttribute("QuadroReference", if camera then camera.ViewportSize else Vector2.new(1920, 1080))
	stroke:SetAttribute("QuadroStrokeBase", round2(px))
	stroke:SetAttribute("QuadroStrokeMode", "screen")
	stroke:SetAttribute("QuadroStrokeMin", min)
	stroke:SetAttribute("QuadroStrokeMax", max)
	CollectionService:AddTag(stroke, STROKE_TAG)
	return true
end

local function convertCorner(corner: UICorner, mode: string, value: number?, portion: number): boolean
	local parent = corner.Parent :: GuiObject
	local abs = parent.AbsoluteSize
	if math.min(abs.X, abs.Y) <= 0 then
		return false
	end
	local unit = Gui.unitScale(parent)
	local radius = corner.CornerRadius
	local scale, offset = Geometry.cornerConvert(
		radius.Scale,
		radius.Offset,
		abs.X,
		abs.Y,
		mode :: Geometry.CornerMode,
		if mode == "hybrid" then (value or portion) else value,
		unit
	)
	corner.CornerRadius = UDim.new(scale, offset)
	return true
end

local function convertPadding(padding: UIPadding, toScale: boolean): boolean
	local parent = padding.Parent :: GuiObject
	local abs = parent.AbsoluteSize
	if abs.X <= 0 or abs.Y <= 0 then
		return false
	end
	local unit = Gui.unitScale(parent)
	local function side(value: UDim, ref: number): UDim
		local scale, offset = Geometry.paddingConvert(value.Scale, value.Offset, ref, unit, toScale)
		return UDim.new(scale, offset)
	end
	padding.PaddingLeft = side(padding.PaddingLeft, abs.X)
	padding.PaddingRight = side(padding.PaddingRight, abs.X)
	padding.PaddingTop = side(padding.PaddingTop, abs.Y)
	padding.PaddingBottom = side(padding.PaddingBottom, abs.Y)
	return true
end

function ToolsPlus.register(registry: any, getSettings: () -> { [string]: any })
	registry:define("transform.hybrid", "cmd_hybrid", function(ctx, px: any, py: any, target: any)
		local settings = getSettings()
		local portionX = if px == nil then settings.hybridX else px
		local portionY = if py == nil then settings.hybridY else py
		local which = if target == nil then "both" else target
		if not (isNumber(portionX) and isNumber(portionY)) or not HYBRID_TARGETS[which] then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		local x = math.clamp(portionX, 0, 1)
		local y = math.clamp(portionY, 0, 1)
		return execute(ctx, "transform.hybrid", hybridTargets(), function(gui: GuiObject)
			local doSize, doPosition = hybridParts(gui, which)
			return doSize or doPosition
		end, function(gui: GuiObject)
			local doSize, doPosition = hybridParts(gui, which)
			if doSize then
				hybridSize(gui, x, y)
			end
			if doPosition then
				hybridPosition(gui, x, y)
			end
			return true
		end)
	end)

	registry:define("stroke.convert", "cmd_stroke", function(ctx, mode: any, min: any, max: any)
		if not STROKE_MODES[mode] or (min ~= nil and not isNumber(min)) or (max ~= nil and not isNumber(max)) then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		return execute(ctx, "stroke.convert", modifiers("UIStroke"), function(stroke: UIStroke)
			return strokeReady(stroke, mode)
		end, function(stroke: UIStroke)
			return convertStroke(stroke, mode, min, max)
		end, mode == "screen")
	end)

	registry:define("corner.convert", "cmd_corner", function(ctx, mode: any, value: any)
		if not CORNER_MODES[mode] or (value ~= nil and not isNumber(value)) then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		local portion = getSettings().hybridX
		return execute(ctx, "corner.convert", modifiers("UICorner"), function(corner: UICorner)
			local abs = (corner.Parent :: GuiObject).AbsoluteSize
			return math.min(abs.X, abs.Y) > 0
		end, function(corner: UICorner)
			return convertCorner(corner, mode, value, if isNumber(portion) then portion else 0.7)
		end)
	end)

	registry:define("padding.convert", "cmd_padding", function(ctx, mode: any)
		if mode ~= "scale" and mode ~= "offset" then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		return execute(ctx, "padding.convert", modifiers("UIPadding"), function(padding: UIPadding)
			local abs = (padding.Parent :: GuiObject).AbsoluteSize
			return abs.X > 0 and abs.Y > 0
		end, function(padding: UIPadding)
			return convertPadding(padding, mode == "scale")
		end)
	end)

	registry:define("text.fit", "cmd_text_fit", function(ctx, min: any, max: any)
		local settings = getSettings()
		local lowRaw = if min == nil then settings.textMin else min
		local highRaw = if max == nil then settings.textMax else max
		if not (isNumber(lowRaw) and isNumber(highRaw)) then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		local low, high = Geometry.clampTextRange(lowRaw, highRaw)
		return execute(ctx, "text.fit", Text.collect(), nil, function(label: TextLabel)
			local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
			if constraint == nil then
				local created = Instance.new("UITextSizeConstraint")
				created.Parent = label
				constraint = created
			end
			assert(constraint, "constraint")
			constraint.MinTextSize = low
			constraint.MaxTextSize = high
			label.TextScaled = true
			return true
		end)
	end)

	registry:define("responsive.clamp", "cmd_clamp", function(ctx, minPct: any, maxPct: any)
		if not (isNumber(minPct) and isNumber(maxPct)) or minPct <= 0 or maxPct < minPct then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		local updated = 0
		local result = execute(ctx, "responsive.clamp", Selection.guiTargets(), function(gui: GuiObject)
			local abs = gui.AbsoluteSize
			return abs.X > 0 and abs.Y > 0 and Gui.unitScale(gui) > 0
		end, function(gui: GuiObject)
			local unit = Gui.unitScale(gui)
			local limit = gui:FindFirstChildOfClass("UISizeConstraint")
			local baseX = gui.AbsoluteSize.X / unit
			local baseY = gui.AbsoluteSize.Y / unit
			if limit ~= nil then
				local parent = Gui.renderedParent(gui)
				if parent == nil then
					return false
				end
				local _, box, parentUnit = Gui.contentBox(parent)
				local refs = Gui.sizeRefs(gui, box)
				local size = gui.Size
				baseX = (size.X.Scale * refs.X + size.X.Offset * parentUnit) / unit
				baseY = (size.Y.Scale * refs.Y + size.Y.Offset * parentUnit) / unit
				updated += 1
			else
				local created = Instance.new("UISizeConstraint")
				created.Parent = gui
				limit = created
			end
			assert(limit, "limit")
			local minX, minY, maxX, maxY = Geometry.sizeLimits(baseX, baseY, minPct, maxPct)
			limit.MinSize = Vector2.new(minX, minY)
			limit.MaxSize = Vector2.new(maxX, maxY)
			return true
		end)
		if updated > 0 and result.ok then
			ctx.notify(ctx.t("result_clamp_updated"), "info")
		end
		return result
	end)

	registry:define("responsive.scaleRoot", "cmd_scale_root", function(ctx, refX: any, refY: any, mode: any)
		local x = if refX == nil then 1920 else refX
		local y = if refY == nil then 1080 else refY
		local scaleMode = if mode == nil then "min" else mode
		if not (isNumber(x) and isNumber(y)) or x <= 0 or y <= 0 or not SCALE_MODES[scaleMode] then
			return { ok = false, count = 0, message = "error_bad_args" }
		end
		return execute(ctx, "responsive.scaleRoot", scaleRoots(), nil, function(root: Instance)
			root:SetAttribute("QuadroReference", Vector2.new(x, y))
			root:SetAttribute("QuadroScaleMode", scaleMode)
			if root:GetAttribute("QuadroScaleMin") == nil then
				root:SetAttribute("QuadroScaleMin", SCALE_MIN)
			end
			if root:GetAttribute("QuadroScaleMax") == nil then
				root:SetAttribute("QuadroScaleMax", SCALE_MAX)
			end
			CollectionService:AddTag(root, SCALE_ROOT_TAG)
			return true
		end, true)
	end)
end

return ToolsPlus
