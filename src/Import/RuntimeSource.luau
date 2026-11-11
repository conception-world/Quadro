--!strict
return [==[
--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Runtime = {}

export type Curve = {
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	ease: (alpha: number) -> number,
}

type Handler = {
	attach: (instance: Instance) -> any,
	step: (instance: Instance, state: any, dt: number) -> (),
	detach: (instance: Instance, state: any) -> (),
}

type Entry = { state: any, ancestry: RBXScriptConnection? }

local BACK_OVERSHOOT = 1.70158

local SETTLE: Curve = {
	style = Enum.EasingStyle.Quad,
	direction = Enum.EasingDirection.Out,
	ease = function(alpha: number): number
		return 1 - (1 - alpha) * (1 - alpha)
	end,
}

local CALM: Curve = {
	style = Enum.EasingStyle.Sine,
	direction = Enum.EasingDirection.InOut,
	ease = function(alpha: number): number
		return (1 - math.cos(math.pi * alpha)) / 2
	end,
}

local ARRIVE: Curve = {
	style = Enum.EasingStyle.Back,
	direction = Enum.EasingDirection.Out,
	ease = function(alpha: number): number
		local t = alpha - 1
		return 1 + (BACK_OVERSHOOT + 1) * t * t * t + BACK_OVERSHOOT * t * t
	end,
}

local LEAVE: Curve = {
	style = Enum.EasingStyle.Quad,
	direction = Enum.EasingDirection.In,
	ease = function(alpha: number): number
		return alpha * alpha
	end,
}

local BUTTON = 0.12
local CHIP = 0.2
local CARD = 0.22
local WINDOW = 0.26
local TROPHY = 0.34

Runtime.CURVES = { SETTLE = SETTLE, CALM = CALM, ARRIVE = ARRIVE, LEAVE = LEAVE }
Runtime.DURATIONS = { BUTTON = BUTTON, CHIP = CHIP, CARD = CARD, WINDOW = WINDOW, TROPHY = TROPHY }

function Runtime.tween(duration: number, curve: Curve): TweenInfo
	return TweenInfo.new(duration, curve.style, curve.direction)
end

local REFERENCE = Vector2.new(1920, 1080)
local SCALE_NAME = "QuadroScale"
local SHINE_OVERLAY = "QuadroShineOverlay"
local SHINE_GRADIENT = "QuadroShine"
local TRANSIENT = "QuadroTransient"
local SHINE_PEAK = 0.45
local SHINE_MIN_WIDTH = 0.02
local SHINE_MAX_WIDTH = 0.96
local MIN_TIME = 0.001
local MIN_SIZE = 2
local WHITE = Color3.new(1, 1, 1)
local SCALE_MODES = { min = true, width = true, height = true }
local STROKE_MODES = { screen = true, object = true }
local MOTIONS = { offset = true, rotation = true, scale = true }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampRange(value: number, low: number, high: number): number
	return math.clamp(value, low, math.max(low, high))
end

local function viewportRatio(mode: string, viewport: Vector2, reference: Vector2): number
	local x = viewport.X / reference.X
	local y = viewport.Y / reference.Y
	if mode == "width" then
		return x
	elseif mode == "height" then
		return y
	end
	return math.min(x, y)
end

local function wrapWave(elapsed: number, speed: number, range: number): number
	if range <= 0 then
		return 0
	end
	local span = 2 * range
	return (elapsed * speed * span + range) % span - range
end

local function pingPongWave(elapsed: number, speed: number, range: number): number
	local phase = (elapsed * speed + 0.25) % 1
	return range * (1 - 4 * math.abs(phase - 0.5))
end

local function pulseWave(elapsed: number, speed: number, range: number): number
	return range * math.sin(2 * math.pi * speed * elapsed)
end

local function shineProgress(elapsed: number, interval: number, duration: number): number?
	if duration <= 0 then
		return nil
	end
	local phase = elapsed % math.max(interval, duration)
	if phase >= duration then
		return nil
	end
	return phase / duration
end

local function shineOffset(progress: number): number
	return -1 + 2 * CALM.ease(progress)
end

local function axisOf(degrees: number): Vector2
	local angle = math.rad(degrees)
	return Vector2.new(math.cos(angle), math.sin(angle))
end

local function shineReach(degrees: number): number
	local angle = math.rad(degrees)
	return math.abs(math.cos(angle)) + math.abs(math.sin(angle))
end

Runtime.math = {
	finite = finite,
	clampRange = clampRange,
	viewportRatio = viewportRatio,
	wrapWave = wrapWave,
	pingPongWave = pingPongWave,
	pulseWave = pulseWave,
	shineProgress = shineProgress,
	shineOffset = shineOffset,
	axisOf = axisOf,
	shineReach = shineReach,
}

local function numberAttribute(instance: Instance, name: string, default: number, minimum: number?): number
	local value = instance:GetAttribute(name)
	if finite(value) and (minimum == nil or value >= minimum) then
		return value
	end
	return default
end

local function offsetAttribute(instance: Instance, name: string): Vector2?
	local value = instance:GetAttribute(name)
	if typeof(value) == "Vector2" and finite(value.X) and finite(value.Y) then
		return value
	end
	return nil
end

local function vectorAttribute(instance: Instance, name: string): Vector2?
	local value = offsetAttribute(instance, name)
	if value and value.X > 0 and value.Y > 0 then
		return value
	end
	return nil
end

local function choiceAttribute(instance: Instance, name: string, choices: { [string]: boolean }, default: string): string
	local value = instance:GetAttribute(name)
	if type(value) == "string" and choices[value] then
		return value
	end
	return default
end

local function viewportOf(instance: Instance): Vector2
	local override = vectorAttribute(instance, "QuadroViewportOverride")
	if override then
		return override
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else REFERENCE
end

local function ownOrChild(instance: Instance, className: string): Instance?
	if instance:IsA(className) then
		return instance
	end
	return instance:FindFirstChildOfClass(className)
end

local function stale(instance: Instance, target: Instance?): boolean
	return target == nil or (target ~= instance and target.Parent ~= instance)
end

local function transient(instance: Instance)
	instance.Archivable = false
	instance:SetAttribute(TRANSIENT, true)
end

local function releaseScale(state: any)
	local scale = state.scale
	state.scale = nil
	if scale == nil then
		return
	end
	if state.created then
		scale:Destroy()
	elseif scale.Scale ~= state.original then
		scale.Scale = state.original
	end
end

local scaleRoot: Handler = {
	attach = function(instance: Instance): any
		if not instance:IsA("GuiBase2d") then
			return nil
		end
		return { scale = nil, created = false, original = 1 }
	end,
	step = function(instance: Instance, state: any, _dt: number)
		local reference = vectorAttribute(instance, "QuadroReference") or REFERENCE
		local mode = choiceAttribute(instance, "QuadroScaleMode", SCALE_MODES, "min")
		local low = numberAttribute(instance, "QuadroScaleMin", 0.5, 0)
		local high = numberAttribute(instance, "QuadroScaleMax", 2, 0)
		local value = clampRange(viewportRatio(mode, viewportOf(instance), reference), low, high)
		if state.scale == nil or state.scale.Parent ~= instance then
			releaseScale(state)
			local existing = instance:FindFirstChildOfClass("UIScale")
			if existing then
				state.scale = existing
				state.created = false
				state.original = existing.Scale
			else
				local created = Instance.new("UIScale")
				created.Name = SCALE_NAME
				transient(created)
				created.Parent = instance
				state.scale = created
				state.created = true
			end
		end
		if state.scale.Scale ~= value then
			state.scale.Scale = value
		end
	end,
	detach = function(_instance: Instance, state: any)
		releaseScale(state)
	end,
}

local function releaseStroke(state: any)
	local stroke = state.stroke
	state.stroke = nil
	if stroke and stroke.Thickness ~= state.original then
		stroke.Thickness = state.original
	end
end

local strokeScale: Handler = {
	attach = function(instance: Instance): any
		if not (instance:IsA("UIStroke") or instance:IsA("GuiObject")) then
			return nil
		end
		return { stroke = nil, original = 0, size = nil }
	end,
	step = function(instance: Instance, state: any, _dt: number)
		if stale(instance, state.stroke) then
			local found = ownOrChild(instance, "UIStroke")
			if found == nil then
				return
			end
			releaseStroke(state)
			state.stroke = found
			state.original = (found :: UIStroke).Thickness
			state.size = nil
		end
		local stroke: UIStroke = state.stroke
		local ratio: number
		if choiceAttribute(instance, "QuadroStrokeMode", STROKE_MODES, "screen") == "object" then
			local object = stroke.Parent
			if object == nil or not object:IsA("GuiObject") then
				return
			end
			local size = (object :: GuiObject).AbsoluteSize
			if size.X < MIN_SIZE or size.Y < MIN_SIZE then
				return
			end
			local authored = vectorAttribute(instance, "QuadroStrokeSize")
			if authored == nil or authored.X < MIN_SIZE or authored.Y < MIN_SIZE then
				if state.size == nil then
					state.size = size
				end
				authored = state.size
			end
			local base = authored :: Vector2
			ratio = math.min(size.X / base.X, size.Y / base.Y)
		else
			ratio = viewportRatio("min", viewportOf(instance), vectorAttribute(instance, "QuadroReference") or REFERENCE)
		end
		local base = numberAttribute(instance, "QuadroStrokeBase", state.original, 0)
		local low = numberAttribute(instance, "QuadroStrokeMin", 0, 0)
		local high = numberAttribute(instance, "QuadroStrokeMax", 1e9, 0)
		local value = clampRange(base * ratio, low, high)
		if stroke.Thickness ~= value then
			stroke.Thickness = value
		end
	end,
	detach = function(_instance: Instance, state: any)
		releaseStroke(state)
	end,
}

local function releaseGradient(state: any, host: Instance?)
	local gradient = state.gradient
	state.gradient = nil
	if gradient == nil then
		return
	end
	local offset: Vector2 = if host then offsetAttribute(host, "QuadroGradientBaseOffset") or state.offset else state.offset
	local rotation: number = if host then numberAttribute(host, "QuadroGradientBaseRotation", state.rotation) else state.rotation
	if gradient.Offset ~= offset then
		gradient.Offset = offset
	end
	if gradient.Rotation ~= rotation then
		gradient.Rotation = rotation
	end
end

local animatedGradient: Handler = {
	attach = function(_instance: Instance): any
		return { gradient = nil, offset = Vector2.zero, rotation = 0, elapsed = 0 }
	end,
	step = function(instance: Instance, state: any, dt: number)
		if stale(instance, state.gradient) then
			local found = ownOrChild(instance, "UIGradient")
			if found == nil then
				return
			end
			releaseGradient(state)
			state.gradient = found
			state.offset = (found :: UIGradient).Offset
			state.rotation = (found :: UIGradient).Rotation
		end
		local gradient: UIGradient = state.gradient
		state.elapsed += dt
		local baseOffset = offsetAttribute(instance, "QuadroGradientBaseOffset") or state.offset
		local baseRotation = numberAttribute(instance, "QuadroGradientBaseRotation", state.rotation)
		local motion = choiceAttribute(instance, "QuadroMotion", MOTIONS, "offset")
		local speed = numberAttribute(instance, "QuadroSpeed", 0.5)
		local range = numberAttribute(instance, "QuadroRange", 1, 0)
		local axis = axisOf(baseRotation)
		local offset = baseOffset
		local rotation = baseRotation
		if motion == "rotation" then
			rotation = (baseRotation + speed * 360 * state.elapsed) % 360
		elseif motion == "scale" then
			offset = baseOffset + axis * pulseWave(state.elapsed, speed, range)
		elseif instance:GetAttribute("QuadroPingPong") == true then
			offset = baseOffset + axis * pingPongWave(state.elapsed, speed, range)
		else
			offset = baseOffset + axis * wrapWave(state.elapsed, speed, range)
		end
		if gradient.Offset ~= offset then
			gradient.Offset = offset
		end
		if gradient.Rotation ~= rotation then
			gradient.Rotation = rotation
		end
	end,
	detach = function(instance: Instance, state: any)
		releaseGradient(state, instance)
	end,
}

local function removeShine(state: any)
	if state.overlay then
		state.overlay:Destroy()
		state.overlay = nil
		state.gradient = nil
	end
end

local function overlayZIndex(gui: GuiObject, overlay: Instance): number
	local collector = gui:FindFirstAncestorWhichIsA("LayerCollector")
	local global = collector ~= nil and (collector :: LayerCollector).ZIndexBehavior == Enum.ZIndexBehavior.Global
	local top = if global then gui.ZIndex else 0
	for _, child in (if global then gui:GetDescendants() else gui:GetChildren()) do
		if child ~= overlay and child:IsA("GuiObject") and child.ZIndex > top then
			top = child.ZIndex
		end
	end
	return top + 1
end

local function createShine(gui: GuiObject, state: any)
	local overlay = Instance.new("Frame")
	overlay.Name = SHINE_OVERLAY
	transient(overlay)
	overlay.Interactable = false
	overlay.Visible = false
	overlay.BackgroundColor3 = WHITE
	overlay.BackgroundTransparency = 0
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Name = SHINE_GRADIENT
	gradient.Parent = overlay
	overlay.Parent = gui
	state.overlay = overlay
	state.gradient = gradient
end

local function styleShine(gui: GuiObject, state: any)
	local overlay: Frame = state.overlay
	local gradient: UIGradient = state.gradient
	local width = math.clamp(numberAttribute(gui, "QuadroShineWidth", 0.18, 0), SHINE_MIN_WIDTH, SHINE_MAX_WIDTH)
	local color = gui:GetAttribute("QuadroShineColor")
	local angle = numberAttribute(gui, "QuadroShineAngle", 20)
	gradient.Color = ColorSequence.new(if typeof(color) == "Color3" then color else WHITE)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - width / 2, 1),
		NumberSequenceKeypoint.new(0.5, SHINE_PEAK),
		NumberSequenceKeypoint.new(0.5 + width / 2, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = angle
	state.axis = axisOf(angle) * shineReach(angle)
	local corner = gui:FindFirstChildOfClass("UICorner")
	local copy = overlay:FindFirstChildOfClass("UICorner")
	if corner and copy == nil then
		copy = Instance.new("UICorner")
		copy.Parent = overlay
	end
	if copy then
		if corner then
			copy.CornerRadius = corner.CornerRadius
		else
			copy:Destroy()
		end
	end
	overlay.ZIndex = overlayZIndex(gui, overlay)
end

local shine: Handler = {
	attach = function(instance: Instance): any
		if not instance:IsA("GuiObject") then
			return nil
		end
		return { elapsed = 0, overlay = nil, gradient = nil, axis = Vector2.xAxis }
	end,
	step = function(instance: Instance, state: any, dt: number)
		state.elapsed += dt
		if instance:FindFirstChildWhichIsA("UIGridStyleLayout") then
			removeShine(state)
			return
		end
		local interval = numberAttribute(instance, "QuadroShineInterval", 2.4, MIN_TIME)
		local duration = numberAttribute(instance, "QuadroShineDuration", 0.6, MIN_TIME)
		local progress = shineProgress(state.elapsed, interval, duration)
		if progress == nil then
			if state.overlay and state.overlay.Visible then
				state.overlay.Visible = false
			end
			return
		end
		if state.overlay == nil or state.overlay.Parent ~= instance or state.gradient.Parent ~= state.overlay then
			removeShine(state)
			createShine(instance :: GuiObject, state)
		end
		if not state.overlay.Visible then
			styleShine(instance :: GuiObject, state)
			state.overlay.Visible = true
		end
		state.gradient.Offset = state.axis * shineOffset(progress)
	end,
	detach = function(_instance: Instance, state: any)
		removeShine(state)
	end,
}

local function pageLayoutAt(origin: Instance, path: string): UIPageLayout?
	local current: Instance? = origin
	for _, segment in string.split(path, "/") do
		if current == nil then
			return nil
		end
		if segment == ".." then
			current = current.Parent
		elseif segment ~= "" and segment ~= "." then
			current = current:FindFirstChild(segment)
		end
	end
	if current == nil then
		return nil
	end
	if current:IsA("UIPageLayout") then
		return current
	end
	return current:FindFirstChildOfClass("UIPageLayout")
end

function Runtime.navigate(button: Instance): boolean
	local path = button:GetAttribute("QuadroPageTarget")
	if type(path) ~= "string" then
		return false
	end
	local layout = pageLayoutAt(button, path)
	if layout == nil then
		return false
	end
	local direction = button:GetAttribute("QuadroPageDirection")
	if type(direction) ~= "string" or direction == "next" then
		layout:Next()
	elseif direction == "previous" then
		layout:Previous()
	else
		local container = layout.Parent
		local page = if container then container:FindFirstChild(direction) else nil
		if page == nil or not page:IsA("GuiObject") then
			return false
		end
		layout:JumpTo(page)
	end
	return true
end

local pageNav: Handler = {
	attach = function(instance: Instance): any
		if not instance:IsA("GuiButton") then
			return nil
		end
		return {
			connection = (instance :: GuiButton).Activated:Connect(function()
				Runtime.navigate(instance)
			end),
		}
	end,
	step = function(_instance: Instance, _state: any, _dt: number) end,
	detach = function(_instance: Instance, state: any)
		state.connection:Disconnect()
	end,
}

function Runtime.eligible(instance: Instance, tag: string): boolean
	if tag == "QuadroAnimatedGradient" then
		return offsetAttribute(instance, "QuadroGradientBaseOffset") ~= nil and finite(instance:GetAttribute("QuadroGradientBaseRotation"))
	elseif tag == "QuadroStrokeScale" then
		return finite(instance:GetAttribute("QuadroStrokeBase"))
	end
	return true
end

local HANDLERS: { [string]: Handler } = {
	QuadroScaleRoot = scaleRoot,
	QuadroStrokeScale = strokeScale,
	QuadroAnimatedGradient = animatedGradient,
	QuadroShine = shine,
	QuadroPageNav = pageNav,
}

export type Accept = (tag: string, instance: Instance) -> boolean

local tracked: { [string]: { [Instance]: Entry } } = {}
local listeners: { RBXScriptConnection } = {}
local isRunning = false
local scope: Instance? = nil
local accept: Accept? = nil

local function inScope(instance: Instance): boolean
	local root = scope
	if root then
		return instance == root or instance:IsDescendantOf(root)
	end
	if instance:IsDescendantOf(workspace) then
		return true
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	return playerGui ~= nil and instance:IsDescendantOf(playerGui)
end

local function reconcile(tag: string, instance: Instance)
	local entries = tracked[tag]
	local entry = if entries then entries[instance] else nil
	if entry == nil then
		return
	end
	local filter = accept
	local wanted = inScope(instance) and (filter == nil or filter(tag, instance))
	if wanted and entry.state == nil then
		entry.state = HANDLERS[tag].attach(instance)
	elseif not wanted and entry.state ~= nil then
		local state = entry.state
		entry.state = nil
		HANDLERS[tag].detach(instance, state)
	end
end

local function track(tag: string, instance: Instance)
	local entries = tracked[tag]
	if entries == nil or entries[instance] ~= nil then
		return
	end
	local entry: Entry = { state = nil, ancestry = nil }
	entries[instance] = entry
	entry.ancestry = instance.AncestryChanged:Connect(function()
		reconcile(tag, instance)
	end)
	reconcile(tag, instance)
end

local function untrack(tag: string, instance: Instance)
	local entries = tracked[tag]
	local entry = if entries then entries[instance] else nil
	if entries == nil or entry == nil then
		return
	end
	entries[instance] = nil
	if entry.ancestry then
		entry.ancestry:Disconnect()
	end
	if entry.state ~= nil then
		HANDLERS[tag].detach(instance, entry.state)
	end
end

function Runtime.step(dt: number)
	if not finite(dt) or dt < 0 then
		return
	end
	for tag, entries in tracked do
		local handler = HANDLERS[tag]
		for instance, entry in entries do
			if entry.state ~= nil then
				handler.step(instance, entry.state, dt)
			end
		end
	end
end

function Runtime.refresh()
	for tag, entries in tracked do
		for instance in entries do
			reconcile(tag, instance)
		end
	end
end

function Runtime.start(root: Instance?, filter: Accept?)
	if isRunning then
		return
	end
	isRunning = true
	scope = root
	accept = filter
	for tag in HANDLERS do
		tracked[tag] = {}
		table.insert(listeners, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			track(tag, instance)
		end))
		table.insert(listeners, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			untrack(tag, instance)
		end))
		for _, instance in CollectionService:GetTagged(tag) do
			track(tag, instance)
		end
	end
	if RunService:IsRunning() and RunService:IsClient() then
		table.insert(listeners, RunService.RenderStepped:Connect(Runtime.step))
	end
end

function Runtime.stop()
	local previous = tracked
	tracked = {}
	for _, connection in listeners do
		connection:Disconnect()
	end
	table.clear(listeners)
	scope = nil
	accept = nil
	isRunning = false
	for tag, entries in previous do
		for instance, entry in entries do
			if entry.ancestry then
				entry.ancestry:Disconnect()
			end
			if entry.state ~= nil then
				local ok, failure = pcall(HANDLERS[tag].detach, instance, entry.state)
				if not ok then
					warn("[Quadro] runtime stop " .. tag .. ": " .. tostring(failure))
				end
			end
		end
	end
end

function Runtime.status(): { started: boolean, connections: number, instances: number, active: number }
	local instances, active = 0, 0
	for _, entries in tracked do
		for _, entry in entries do
			instances += 1
			if entry.state ~= nil then
				active += 1
			end
		end
	end
	return { started = isRunning, connections = #listeners, instances = instances, active = active }
end

local TWEENABLE_TYPES: { [string]: boolean } = {
	number = true,
	Color3 = true,
	UDim2 = true,
	UDim = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	Rect = true,
}

local captured: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local running: { [Instance]: { Tween } } = setmetatable({}, { __mode = "k" }) :: any

local function sanitize(name: string): string
	return (string.gsub(name, "[^%w_]", "_"))
end

local function findChild(parent: Instance, segment: string): Instance?
	local base = segment
	local wanted = 1
	local stem, count = string.match(segment, "^(.*)%-(%d+)$")
	if stem and count then
		base = stem
		wanted = tonumber(count) or 1
	end
	local seen = 0
	for _, child in parent:GetChildren() do
		if sanitize(child.Name) == base then
			seen += 1
			if seen == wanted then
				return child
			end
		end
	end
	return nil
end

local function resolve(gui: Instance, key: string): (Instance?, string?)
	local path, property = string.match(key, "^(.*)%.([%w_]+)$")
	if path == nil or property == nil then
		return nil, nil
	end
	local current: Instance = gui
	if path ~= "" then
		for _, segment in string.split(path, "/") do
			local found = findChild(current, segment)
			if found == nil then
				return nil, nil
			end
			current = found
		end
	end
	return current, property
end

local function statesOf(gui: Instance): Instance?
	local own = gui:FindFirstChild("QuadroStates")
	if own then
		return own
	end
	local name = gui:GetAttribute("QuadroTemplate")
	if type(name) ~= "string" then
		return nil
	end
	local templates = ReplicatedStorage:FindFirstChild("QuadroTemplates")
	local template = if templates then templates:FindFirstChild(name) else nil
	return if template then template:FindFirstChild("QuadroStates") else nil
end

local function realProperty(property: string): string
	return if property == "SizeScale" then "Size" else property
end

local function snapshot(gui: Instance, states: Instance): { [string]: any }
	local saved = captured[gui]
	if saved == nil then
		saved = {}
		captured[gui] = saved
	end
	local store = saved :: { [string]: any }
	for _, config in states:GetChildren() do
		for key in config:GetAttributes() do
			if store[key] == nil then
				local target, property = resolve(gui, key)
				if target and property then
					local ok, value = pcall(function()
						return (target :: any)[realProperty(property)]
					end)
					if ok then
						store[key] = value
					end
				end
			end
		end
	end
	return store
end

local function scaled(size: UDim2, ratio: Vector2): UDim2
	return UDim2.new(size.X.Scale * ratio.X, size.X.Offset * ratio.X, size.Y.Scale * ratio.Y, size.Y.Offset * ratio.Y)
end

function Runtime.setState(gui: Instance, state: string, tweenInfo: TweenInfo?)
	local states = statesOf(gui)
	if states == nil then
		return
	end
	local previous = running[gui]
	if previous then
		for _, tween in previous do
			tween:Cancel()
		end
	end
	local started: { Tween } = {}
	running[gui] = started
	local saved = snapshot(gui, states)
	local config = if state == "Normal" then nil else states:FindFirstChild(state)
	for key, original in saved do
		local target, property = resolve(gui, key)
		if target and property then
			local value = original
			local override = if config then config:GetAttribute(key) else nil
			if override ~= nil then
				value = if property == "SizeScale" then scaled(original, override) else override
			end
			local name = realProperty(property)
			local ok, failure = pcall(function()
				if tweenInfo and TWEENABLE_TYPES[typeof(value)] then
					local tween = TweenService:Create(target :: Instance, tweenInfo, { [name] = value })
					table.insert(started, tween)
					tween:Play()
				else
					local object = target :: any
					object[name] = value
				end
			end)
			if not ok then
				warn("[Quadro] setState " .. key .. ": " .. tostring(failure))
			end
		end
	end
end

function Runtime.bindButton(gui: GuiObject, tweenInfo: TweenInfo?): () -> ()
	local hovering = false
	local pressing = false
	local connections: { RBXScriptConnection } = {}
	local function refresh()
		local disabled = gui:IsA("GuiButton") and not gui.Active
		local state = if disabled then "Disabled" elseif pressing then "Pressed" elseif hovering then "Hover" else "Normal"
		Runtime.setState(gui, state, tweenInfo)
	end
	table.insert(connections, gui.MouseEnter:Connect(function()
		hovering = true
		refresh()
	end))
	table.insert(connections, gui.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		refresh()
	end))
	table.insert(connections, gui.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true
			refresh()
		end
	end))
	table.insert(connections, gui.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false
			refresh()
		end
	end))
	if gui:IsA("GuiButton") then
		table.insert(connections, gui:GetPropertyChangedSignal("Active"):Connect(refresh))
	end
	refresh()
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

return Runtime
]==]
