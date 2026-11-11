--!strict
local CollectionService = game:GetService("CollectionService")
local Codec = require(script.Parent.Parent.Gradients.Codec)
local EffectPresets = require(script.Parent.Parent.EffectPresets)
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Library = require(script.Parent.Parent.Gradients.Library)
local Selection = require(script.Parent.Parent.Studio.Selection)
local Stops = require(script.Parent.Parent.Gradients.Stops)
local ToolsPlus = require(script.Parent.ToolsPlus)

local Effects = {}

local WHITE = Color3.new(1, 1, 1)
local STROKE_THICKNESS = 2
local MASK_ATTRIBUTE = "QuadroMask"
local MASK_SIDES = { top = true, bottom = true, left = true, right = true, edges = true }
local MASK_AXES = { h = true, v = true }
local DEFAULT_SIDE = "bottom"
local DEFAULT_LENGTH = 0.3
local BLACK = Color3.new(0, 0, 0)
local OWNED = "QuadroOwned"
local EFFECT = "QuadroEffect"
local HOLLOW_FROM = "QuadroHollowFrom"
local HOLLOW_THICKNESS = 2
local MOTION_TAG = "QuadroAnimatedGradient"
local SHINE_TAG = "QuadroShine"
local MOTION_ATTRIBUTES = { "QuadroMotion", "QuadroSpeed", "QuadroRange", "QuadroPingPong", Library.BASE_OFFSET, Library.BASE_ROTATION }
local SHINE_ATTRIBUTES = { "QuadroShineInterval", "QuadroShineDuration", "QuadroShineWidth", "QuadroShineAngle", "QuadroShineColor" }

local function fail(message: string): any
	return { ok = false, count = 0, message = message }
end

local function owned(gui: Instance, className: string, effect: string): { Instance }
	local found: { Instance } = {}
	for _, child in gui:GetChildren() do
		if child:IsA(className) and child:GetAttribute(OWNED) == true and child:GetAttribute(EFFECT) == effect then
			table.insert(found, child)
		end
	end
	return found
end

local function syncPieces(gui: Instance, className: string, effect: string, prefix: string, count: number, configure: (piece: any, index: number) -> ())
	local pieces = owned(gui, className, effect)
	for index = 1, count do
		local piece = pieces[index]
		if piece == nil then
			piece = Instance.new(className)
			piece:SetAttribute(OWNED, true)
			piece:SetAttribute(EFFECT, effect)
		end
		piece.Name = if count == 1 then prefix else prefix .. index
		configure(piece, index)
		piece.Parent = gui
	end
	for index = count + 1, #pieces do
		pieces[index].Parent = nil
	end
end

local function guiReady(target: Instance): boolean | string
	return if target:IsA("GuiObject") then true else "result_not_gui"
end

local function innerZIndex(gui: GuiObject): number
	local collector = gui:FindFirstAncestorWhichIsA("LayerCollector")
	if collector and collector.ZIndexBehavior == Enum.ZIndexBehavior.Global then
		return gui.ZIndex
	end
	return 0
end

local function syncInner(gui: GuiObject, wanted: boolean)
	syncPieces(gui, "Frame", "innerShadow", "QuadroInnerShadow", if wanted then 1 else 0, function(frame: Frame)
		local spec = EffectPresets.INNER
		frame.Size = UDim2.fromScale(1, 1)
		frame.Position = UDim2.new()
		frame.AnchorPoint = Vector2.zero
		frame.BackgroundColor3 = BLACK
		frame.BackgroundTransparency = 0
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Selectable = false
		frame.ZIndex = innerZIndex(gui)
		local gradient = frame:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(WHITE)
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.top),
			NumberSequenceKeypoint.new(spec.fade, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		local rim = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.BorderStrokePosition = Enum.BorderStrokePosition.Inner
		rim.Thickness = spec.rim
		rim.Color = BLACK
		rim.Transparency = spec.rimTransparency
		rim.Parent = frame
		local hostCorner = gui:FindFirstChildOfClass("UICorner")
		local corner = frame:FindFirstChildOfClass("UICorner")
		if hostCorner then
			local copy = corner or Instance.new("UICorner")
			copy.CornerRadius = hostCorner.CornerRadius
			copy.Parent = frame
		elseif corner then
			corner.Parent = nil
		end
	end)
end

local function isText(target: Instance): boolean
	return target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox")
end

local function hasUserContextualStroke(label: Instance): boolean
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child:GetAttribute(EFFECT) ~= "hollow" and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and child.Enabled then
			return true
		end
	end
	return false
end

local function isImage(target: Instance): boolean
	return target:IsA("ImageLabel") or target:IsA("ImageButton")
end

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function gradientType(name: any): Enum.GradientType?
	if not Library.typeSupported or not table.find(Library.GRADIENT_TYPES, name) then
		return nil
	end
	return (Enum.GradientType :: any)[name]
end

local function strokeMode(targets: { Instance }): Enum.StrokeSizingMode
	for _, target in targets do
		local stroke = target:FindFirstChildOfClass("UIStroke")
		if stroke then
			return stroke.StrokeSizingMode
		end
	end
	return Enum.StrokeSizingMode.FixedSize
end

local function ensureStroke(gui: GuiObject, mode: Enum.StrokeSizingMode): UIStroke
	local existing = gui:FindFirstChildOfClass("UIStroke")
	if existing then
		return existing
	end
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = WHITE
	stroke.Thickness = STROKE_THICKNESS
	local side = math.min(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
	local unit = Gui.unitScale(gui)
	if mode == Enum.StrokeSizingMode.ScaledSize and side > 0 and unit > 0 then
		stroke.StrokeSizingMode = mode
		stroke.Thickness = STROKE_THICKNESS * unit / side
	end
	stroke.Parent = gui
	return stroke
end

local function strokeGradient(stroke: UIStroke): (UIGradient, boolean)
	local gradient = stroke:FindFirstChildOfClass("UIGradient")
	if gradient then
		return gradient, false
	end
	local created = Instance.new("UIGradient")
	created.Parent = stroke
	local whitened = stroke.Color ~= WHITE
	stroke.Color = WHITE
	return created, whitened
end

local function isWhite(gradient: UIGradient): boolean
	for _, point in gradient.Color.Keypoints do
		if point.Value ~= WHITE then
			return false
		end
	end
	return true
end

local function maskable(target: Instance): boolean | string
	if not target:IsA("GuiObject") then
		return "result_not_gui"
	end
	local existing = target:FindFirstChildOfClass("UIGradient")
	if existing == nil or existing:GetAttribute(MASK_ATTRIBUTE) == true or isWhite(existing) then
		return true
	end
	return "result_mask_refused"
end

local function editTarget(subject: GuiObject, target: string): (Instance?, UIGradient?)
	local host: Instance? = if target == "stroke" then subject:FindFirstChildOfClass("UIStroke") else subject
	return host, if host then host:FindFirstChildOfClass("UIGradient") else nil
end

local function tagged(tag: string, reason: string): (target: Instance) -> boolean | string
	return function(target: Instance): boolean | string
		return if CollectionService:HasTag(target, tag) then true else reason
	end
end

local function untag(tag: string, attributes: { string }): (target: Instance) -> boolean
	return function(target: Instance): boolean
		CollectionService:RemoveTag(target, tag)
		for _, name in attributes do
			target:SetAttribute(name, nil)
		end
		return true
	end
end

function Effects.register(registry: any)
	registry:define("gradient.edit", "cmd_gradient_edit", function(ctx, target: any, patch: any)
		if (target ~= "fill" and target ~= "stroke") or type(patch) ~= "table" then
			return fail("error_bad_args")
		end
		if patch.type ~= nil and gradientType(patch.type) == nil then
			return fail("error_bad_args")
		end
		local subject = Selection.firstGui()
		if subject == nil then
			return fail("error_no_selection")
		end
		local _, existing = editTarget(subject, target)
		local current = if existing then Library.restData(existing) else Stops.DEFAULT
		local color, transparency = patch.color, patch.transparency
		local merged = Codec.sanitize({
			name = current.name,
			rotation = if patch.rotation ~= nil then patch.rotation else current.rotation,
			offset = current.offset,
			color = color or current.color,
			transparency = transparency or current.transparency,
		})
		if merged == nil then
			return fail("error_bad_args")
		end
		if existing and next(patch) == nil then
			return { ok = true, count = 0 }
		end
		local data: Codec.Data = merged
		local whitened = false
		local ok, cause = History.record("gradient.edit", function()
			local gradient = existing
			if gradient == nil then
				if target == "stroke" then
					gradient, whitened = strokeGradient(ensureStroke(subject, strokeMode({ subject })))
				else
					local created = Instance.new("UIGradient")
					created.Parent = subject
					gradient = created
				end
				assert(gradient, "gradient")
				if not Library.write(gradient, data) then
					error("write failed")
				end
			else
				if color then
					gradient.Color = Library.colorSequence(data.color)
				end
				if transparency then
					gradient.Transparency = Library.numberSequence(data.transparency)
				end
				if patch.rotation ~= nil then
					gradient.Rotation = data.rotation
					local holder = Library.baseHolder(gradient)
					if holder and holder:GetAttribute(Library.BASE_ROTATION) ~= nil then
						holder:SetAttribute(Library.BASE_ROTATION, data.rotation)
					end
				end
			end
			local kind = gradientType(patch.type)
			if kind then
				gradient.Type = kind
			end
			return 1
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return fail("error_busy")
			end
			warn("[Quadro] gradient.edit: " .. tostring(cause))
			return fail("error_command_failed")
		end
		if whitened then
			ctx.notify(ctx.t("result_stroke_whitened"), "warning")
		end
		return { ok = true, count = 1 }
	end)

	registry:define("effect.gradientStroke", "cmd_gradient_stroke", function(ctx, raw: any)
		local data = if raw == nil then Stops.DEFAULT else Codec.sanitize(raw)
		if data == nil then
			return fail("error_bad_args")
		end
		local clean: Codec.Data = data
		local targets = Selection.candidates()
		local mode = strokeMode(targets)
		local whitened = 0
		local result = ToolsPlus.execute(ctx, "effect.gradientStroke", targets, function(target: Instance)
			return target:IsA("GuiObject")
		end, function(gui: GuiObject)
			local gradient, changed = strokeGradient(ensureStroke(gui, mode))
			if changed then
				whitened += 1
			end
			return Library.write(gradient, clean)
		end)
		if result.ok and whitened > 0 then
			ctx.notify(ctx.t("result_stroke_whitened"), "warning")
		end
		return result
	end)

	registry:define("effect.fadingMask", "cmd_fading_mask", function(ctx, side: any, length: any, axis: any)
		local chosenSide = if side == nil then DEFAULT_SIDE else side
		local chosenLength = if length == nil then DEFAULT_LENGTH else length
		local chosenAxis = if axis == nil then "h" else axis
		if not MASK_SIDES[chosenSide] or not isNumber(chosenLength) or not MASK_AXES[chosenAxis] then
			return fail("error_bad_args")
		end
		local rotation, points = Stops.mask(chosenSide, chosenLength, chosenAxis)
		local transparency = Library.numberSequence(points)
		return ToolsPlus.execute(ctx, "effect.fadingMask", Selection.candidates(), maskable, function(gui: GuiObject)
			local gradient = gui:FindFirstChildOfClass("UIGradient")
			if gradient == nil then
				local created = Instance.new("UIGradient")
				created.Name = MASK_ATTRIBUTE
				created.Parent = gui
				gradient = created
			end
			assert(gradient, "gradient")
			gradient.Color = ColorSequence.new(WHITE)
			gradient.Transparency = transparency
			gradient.Rotation = rotation
			gradient.Offset = Vector2.zero
			Library.syncBase(gradient)
			local linear = gradientType("Linear")
			if linear then
				gradient.Type = linear
			end
			gradient:SetAttribute(MASK_ATTRIBUTE, true)
			return true
		end)
	end)

	registry:define("effect.shadow", "cmd_shadow", function(ctx, preset: any)
		local chosen = if preset == nil then EffectPresets.SHADOW_DEFAULT else preset
		if chosen == "none" then
			return ToolsPlus.execute(ctx, "effect.shadow", Selection.candidates(), function(target: Instance)
				if not target:IsA("GuiObject") then
					return "result_not_gui"
				end
				local found = #owned(target, "UIShadow", "shadow") + #owned(target, "Frame", "innerShadow")
				return if found > 0 then true else "result_shadow_missing"
			end, function(gui: GuiObject)
				syncPieces(gui, "UIShadow", "shadow", "QuadroShadow", 0, function() end)
				syncInner(gui, false)
				return true
			end)
		end
		if chosen == EffectPresets.INNER_PRESET then
			return ToolsPlus.execute(ctx, "effect.shadow", Selection.candidates(), function(target: Instance)
				if not target:IsA("GuiObject") then
					return "result_not_gui"
				end
				return if target:FindFirstChildWhichIsA("UIGridStyleLayout") then "result_inner_layout" else true
			end, function(gui: GuiObject)
				syncPieces(gui, "UIShadow", "shadow", "QuadroShadow", 0, function() end)
				syncInner(gui, true)
				return true
			end)
		end
		local layers = if type(chosen) == "string" then EffectPresets.SHADOWS[chosen] else nil
		if layers == nil then
			return fail("error_bad_args")
		end
		local presetLayers: { EffectPresets.ShadowLayer } = layers
		return ToolsPlus.execute(ctx, "effect.shadow", Selection.candidates(), guiReady, function(gui: GuiObject)
			syncPieces(gui, "UIShadow", "shadow", "QuadroShadow", #presetLayers, function(shadow: UIShadow, index: number)
				local layer = presetLayers[index]
				shadow.Color = BLACK
				shadow.Offset = UDim2.fromOffset(0, layer.y)
				shadow.BlurRadius = UDim.new(0, layer.blur)
				shadow.Spread = UDim2.new()
				shadow.Transparency = layer.transparency
				shadow.Inset = false
			end)
			syncInner(gui, false)
			return true
		end)
	end)

	registry:define("effect.neonOutline", "cmd_neon_outline", function(ctx, color: any, layers: any)
		if color == "none" then
			return ToolsPlus.execute(ctx, "effect.neonOutline", Selection.candidates(), function(target: Instance)
				if not target:IsA("GuiObject") then
					return "result_not_gui"
				end
				local found = #owned(target, "UIStroke", "neonStroke") + #owned(target, "UIShadow", "neonGlow")
				return if found > 0 then true else "result_neon_missing"
			end, function(gui: GuiObject)
				syncPieces(gui, "UIStroke", "neonStroke", "QuadroNeonStroke", 0, function() end)
				syncPieces(gui, "UIShadow", "neonGlow", "QuadroNeonGlow", 0, function() end)
				return true
			end)
		end
		local hex: string? = nil
		if color == nil then
			hex = EffectPresets.NEON_COLOR
		elseif typeof(color) == "Color3" then
			hex = color:ToHex()
		elseif type(color) == "string" then
			hex = Stops.parseHex(color)
		end
		local count = if layers == nil then EffectPresets.NEON_LAYERS else layers
		if hex == nil or not isNumber(count) or count % 1 ~= 0 or count < 1 or count > EffectPresets.NEON_MAX_LAYERS then
			return fail("error_bad_args")
		end
		local tint = Color3.fromHex(hex)
		local glows = EffectPresets.neonLayers(count)
		return ToolsPlus.execute(ctx, "effect.neonOutline", Selection.candidates(), guiReady, function(gui: GuiObject)
			syncPieces(gui, "UIStroke", "neonStroke", "QuadroNeonStroke", 1, function(stroke: UIStroke)
				stroke.Color = tint
				stroke.Thickness = EffectPresets.NEON_STROKE
				stroke.Transparency = 0
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
			end)
			syncPieces(gui, "UIShadow", "neonGlow", "QuadroNeonGlow", count, function(glow: UIShadow, index: number)
				glow.Color = tint
				glow.Offset = UDim2.new()
				glow.BlurRadius = UDim.new(0, glows[index].blur)
				glow.Spread = UDim2.new()
				glow.Transparency = glows[index].transparency
				glow.Inset = false
			end)
			return true
		end)
	end)

	registry:define("effect.hollowText", "cmd_hollow_text", function(ctx)
		return ToolsPlus.execute(ctx, "effect.hollowText", Selection.candidates(), function(target: Instance)
			return if isText(target) then true else "result_hollow_not_text"
		end, function(label: any)
			local from = label:GetAttribute(HOLLOW_FROM)
			if type(from) == "number" then
				label.TextTransparency = from
				label:SetAttribute(HOLLOW_FROM, nil)
				syncPieces(label, "UIStroke", "hollow", "QuadroHollowStroke", 0, function() end)
				return true
			end
			label:SetAttribute(HOLLOW_FROM, label.TextTransparency)
			label.TextTransparency = 1
			if not hasUserContextualStroke(label) then
				syncPieces(label, "UIStroke", "hollow", "QuadroHollowStroke", 1, function(stroke: UIStroke)
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
					stroke.Thickness = HOLLOW_THICKNESS
					stroke.Color = label.TextColor3
					stroke.Transparency = 0
				end)
			end
			return true
		end)
	end)

	registry:define("effect.nineSlice", "cmd_nine_slice", function(ctx, l: any, t: any, r: any, b: any, scale: any, w: any, h: any)
		local sliceScale = if scale == nil then 1 else scale
		for _, margin in { l, t, r, b } do
			if not isNumber(margin) or margin < 0 then
				return fail("error_bad_args")
			end
		end
		if not isNumber(sliceScale) or sliceScale <= 0 then
			return fail("error_bad_args")
		end
		if (w ~= nil or h ~= nil) and not (isNumber(w) and isNumber(h)) then
			return fail("error_bad_args")
		end
		local function rectFor(image: any): ({ number }?, string?)
			local width, height = w, h
			if width == nil then
				local region: Vector2 = image.ImageRectSize
				if region.X <= 0 or region.Y <= 0 then
					return nil, "result_slice_no_size"
				end
				width, height = region.X, region.Y
			end
			local rect, problem = EffectPresets.sliceRect(l, t, r, b, width, height)
			if rect then
				return rect, nil
			end
			return nil, if problem == "slice_error_size" then "result_slice_no_size" else "result_slice_bad_margins"
		end
		return ToolsPlus.execute(ctx, "effect.nineSlice", Selection.candidates(), function(target: Instance)
			if not isImage(target) then
				return "result_slice_not_image"
			end
			local rect, reason = rectFor(target)
			return if rect then true else reason or "result_slice_bad_margins"
		end, function(image: any)
			local rect = rectFor(image)
			if rect == nil then
				return false
			end
			image.ScaleType = Enum.ScaleType.Slice
			image.SliceCenter = Rect.new(rect[1], rect[2], rect[3], rect[4])
			image.SliceScale = sliceScale
			return true
		end)
	end)

	registry:define("effect.animatedGradient", "cmd_animated_gradient", function(ctx, motion: any, speed: any, range: any, pingPong: any)
		if motion == "none" then
			return ToolsPlus.execute(ctx, "effect.animatedGradient", Selection.candidates(), tagged(MOTION_TAG, "result_motion_missing"), untag(MOTION_TAG, MOTION_ATTRIBUTES))
		end
		local chosen = if motion == nil then EffectPresets.MOTION_DEFAULT else motion
		local rate = if speed == nil then EffectPresets.MOTION_SPEED else speed
		local reach = if range == nil then EffectPresets.MOTION_RANGE else range
		local bounce = if pingPong == nil then false else pingPong
		if table.find(EffectPresets.MOTIONS, chosen) == nil or not isNumber(rate) or not isNumber(reach) or reach < 0 or type(bounce) ~= "boolean" then
			return fail("error_bad_args")
		end
		return ToolsPlus.execute(ctx, "effect.animatedGradient", Selection.candidates(), function(target: Instance)
			if not target:IsA("GuiObject") then
				return "result_not_gui"
			end
			return if target:FindFirstChildOfClass("UIGradient") then true else "result_motion_no_gradient"
		end, function(gui: GuiObject)
			local gradient = gui:FindFirstChildOfClass("UIGradient") :: UIGradient
			if gui:GetAttribute(Library.BASE_OFFSET) == nil then
				gui:SetAttribute(Library.BASE_OFFSET, gradient.Offset)
			end
			if gui:GetAttribute(Library.BASE_ROTATION) == nil then
				gui:SetAttribute(Library.BASE_ROTATION, gradient.Rotation)
			end
			gui:SetAttribute("QuadroMotion", chosen)
			gui:SetAttribute("QuadroSpeed", rate)
			gui:SetAttribute("QuadroRange", reach)
			gui:SetAttribute("QuadroPingPong", bounce)
			CollectionService:AddTag(gui, MOTION_TAG)
			return true
		end, true)
	end)

	registry:define("effect.shine", "cmd_shine", function(ctx, interval: any, duration: any, width: any, angle: any)
		if interval == "none" then
			return ToolsPlus.execute(ctx, "effect.shine", Selection.candidates(), tagged(SHINE_TAG, "result_shine_missing"), untag(SHINE_TAG, SHINE_ATTRIBUTES))
		end
		local every = if interval == nil then EffectPresets.SHINE_INTERVAL else interval
		local length = if duration == nil then EffectPresets.SHINE_DURATION else duration
		local band = if width == nil then EffectPresets.SHINE_WIDTH else width
		local tilt = if angle == nil then EffectPresets.SHINE_ANGLE else angle
		if not (isNumber(every) and isNumber(length) and isNumber(band) and isNumber(tilt)) or every <= 0 or length <= 0 or band <= 0 or band > 1 then
			return fail("error_bad_args")
		end
		return ToolsPlus.execute(ctx, "effect.shine", Selection.candidates(), function(target: Instance)
			if not target:IsA("GuiObject") then
				return "result_not_gui"
			end
			return if target:FindFirstChildWhichIsA("UIGridStyleLayout") then "result_shine_layout" else true
		end, function(gui: GuiObject)
			gui:SetAttribute("QuadroShineInterval", every)
			gui:SetAttribute("QuadroShineDuration", length)
			gui:SetAttribute("QuadroShineWidth", band)
			gui:SetAttribute("QuadroShineAngle", tilt)
			if gui:GetAttribute("QuadroShineColor") == nil then
				gui:SetAttribute("QuadroShineColor", WHITE)
			end
			CollectionService:AddTag(gui, SHINE_TAG)
			return true
		end, true)
	end)
end

return Effects
