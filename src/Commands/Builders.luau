--!strict
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local SelectionService = game:GetService("Selection")
local BuilderMath = require(script.Parent.Parent.BuilderMath)
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Installer = require(script.Parent.Parent.Runtime.Installer)
local Stops = require(script.Parent.Parent.Gradients.Stops)
local ToolsPlus = require(script.Parent.ToolsPlus)

local Builders = {}

local BUILDER = "QuadroBuilder"
local POINTS = "QuadroPathPoints"
local NAV_TAG = "QuadroPageNav"
local PAGES_NAME = "Pages"
local PATH_NAME = "Path"
local PREVIOUS_NAME = "PagesPrev"
local NEXT_NAME = "PagesNext"
local PATH_HOST = "pathHost"
local DETECTOR_NAME = "UIDragDetector"
local PRECISION = 10000

type PageMotion = { style: Enum.EasingStyle, direction: Enum.EasingDirection, time: number }

local motion: PageMotion? = nil

local function pageMotion(): PageMotion?
	if motion then
		return motion
	end
	local runtime = Installer.load()
	if runtime == nil then
		return nil
	end
	local settle = runtime.CURVES.SETTLE
	motion = { style = settle.style, direction = settle.direction, time = runtime.DURATIONS.WINDOW }
	return motion
end

local function fail(message: string): any
	return { ok = false, count = 0, message = message }
end

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isHost(instance: Instance): boolean
	return instance:IsA("LayerCollector") or instance:IsA("Frame") or instance:IsA("ScrollingFrame") or instance:IsA("CanvasGroup")
end

local function isGuiParent(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("GuiBase2d") or instance:IsA("LayerCollector"))
end

local function pathTargets(): { Instance }
	local found: { Instance } = {}
	for _, selected in SelectionService:Get() do
		if selected:IsA("GuiObject") or selected:IsA("LayerCollector") then
			table.insert(found, selected)
		end
	end
	return found
end

local function pathsOf(): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(path: Instance)
		if not seen[path] then
			seen[path] = true
			table.insert(found, path)
		end
	end
	for _, selected in SelectionService:Get() do
		if selected:IsA("Path2D") then
			add(selected)
		else
			for _, child in selected:GetChildren() do
				if child:IsA("Path2D") then
					add(child)
				end
			end
		end
	end
	return found
end

local function udim2(vec: BuilderMath.Vec): UDim2
	return UDim2.fromScale(vec[1], vec[2])
end

local function rounded(value: number): number
	return math.round(value * PRECISION) / PRECISION
end

local function uniqueName(parent: Instance, base: string): string
	if parent:FindFirstChild(base) == nil then
		return base
	end
	local index = 2
	while parent:FindFirstChild(base .. index) do
		index += 1
	end
	return base .. index
end

local function registerPath(registry: any)
	registry:define("builder.path", "cmd_path", function(ctx, preset: any, thickness: any, color: any)
		local chosen = if preset == nil then BuilderMath.PRESET_DEFAULT else preset
		local width = if thickness == nil then BuilderMath.THICKNESS_DEFAULT else thickness
		local hex = if color == nil then BuilderMath.COLOR_DEFAULT else if type(color) == "string" then Stops.parseHex(color) else nil
		local points = if type(chosen) == "string" then BuilderMath.controlPoints(chosen) else nil
		if points == nil or hex == nil or not isNumber(width) or width < BuilderMath.THICKNESS_MIN or width > BuilderMath.THICKNESS_MAX then
			return fail("error_bad_args")
		end
		local controls: { Path2DControlPoint } = {}
		for _, point in points do
			table.insert(controls, Path2DControlPoint.new(udim2(point.position), udim2(point.left), udim2(point.right)))
		end
		local paint = Color3.fromHex(hex)
		return ToolsPlus.execute(ctx, "builder.path", pathTargets(), function(target: Instance)
			if isHost(target) or isGuiParent(target.Parent) then
				return true
			end
			return "result_tool_skipped"
		end, function(target: Instance)
			local host = target
			if not isHost(target) then
				local parent = target.Parent :: Instance
				local wrapper: Instance? = nil
				for _, child in parent:GetChildren() do
					if child:IsA("Frame") and child:GetAttribute(BUILDER) == PATH_HOST then
						wrapper = child
						break
					end
				end
				if wrapper == nil then
					local frame = Instance.new("Frame")
					frame.Name = uniqueName(parent, PATH_NAME)
					frame.Size = UDim2.fromScale(1, 1)
					frame.BackgroundTransparency = 1
					frame.BorderSizePixel = 0
					frame:SetAttribute(BUILDER, PATH_HOST)
					frame.Parent = parent
					wrapper = frame
				end
				host = wrapper :: Instance
			end
			local path: Path2D? = nil
			for _, child in host:GetChildren() do
				if child:IsA("Path2D") and child:GetAttribute(BUILDER) == "path" then
					path = child
					break
				end
			end
			local made = path or Instance.new("Path2D")
			made:SetControlPoints(controls)
			made.Thickness = width
			made.Color3 = paint
			made:SetAttribute(BUILDER, "path")
			made:SetAttribute(POINTS, nil)
			made.Parent = host
			return true
		end)
	end)

	registry:define("builder.pathSample", "cmd_path_sample", function(ctx, count: any)
		local amount = if count == nil then BuilderMath.SAMPLE_DEFAULT else count
		if not BuilderMath.validCount(amount) then
			return fail("error_bad_args")
		end
		local times = BuilderMath.sampleTimes(amount)
		return ToolsPlus.execute(ctx, "builder.pathSample", pathsOf(), function(path: Path2D)
			if path:FindFirstAncestorWhichIsA("LayerCollector") == nil then
				return "result_path_unrendered"
			end
			return if #path:GetControlPoints() >= 2 then true else "result_path_short"
		end, function(path: Path2D)
			local samples = {}
			for _, time in times do
				local ok, position = pcall(function()
					return path:GetPositionOnCurve(time)
				end)
				if not ok then
					warn("[Quadro] builder.pathSample: " .. tostring(position))
					return false
				end
				table.insert(samples, {
					xs = rounded(position.X.Scale),
					xo = rounded(position.X.Offset),
					ys = rounded(position.Y.Scale),
					yo = rounded(position.Y.Offset),
				})
			end
			path:SetAttribute(POINTS, HttpService:JSONEncode(samples))
			return true
		end)
	end)
end

local function detector(panel: GuiObject): UIDragDetector
	local existing = panel:FindFirstChildOfClass("UIDragDetector")
	if existing then
		return existing
	end
	local created = Instance.new("UIDragDetector")
	created.Name = DETECTOR_NAME
	created.Parent = panel
	return created
end

local function registerDrag(registry: any)
	registry:define("builder.drag", "cmd_drag", function(ctx, preset: any)
		local chosen = if preset == nil then BuilderMath.DRAG_DEFAULT else preset
		if table.find(BuilderMath.DRAG_PRESETS, chosen) == nil then
			return fail("error_bad_args")
		end
		local targets: { Instance } = {}
		for _, selected in SelectionService:Get() do
			if selected:IsA("GuiObject") then
				table.insert(targets, selected)
			end
		end
		return ToolsPlus.execute(ctx, "builder.drag", targets, function(target: GuiObject)
			local parent = target.Parent
			if chosen == "header" then
				if parent == nil or not parent:IsA("GuiObject") then
					return "result_drag_no_panel"
				end
				return if target:FindFirstAncestorWhichIsA("LayerCollector") then true else "result_tool_skipped"
			elseif chosen == "bounded" then
				return if isGuiParent(parent) then true else "result_drag_no_panel"
			end
			return true
		end, function(target: GuiObject)
			local panel = if chosen == "header" then target.Parent :: GuiObject else target
			local drag = detector(panel)
			drag.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
			drag.ResponseStyle = Enum.UIDragDetectorResponseStyle.Scale
			drag.DragRelativity = Enum.UIDragDetectorDragRelativity.Absolute
			drag.DragSpace = Enum.UIDragDetectorDragSpace.Parent
			drag.Enabled = true
			if chosen == "header" then
				drag.BoundingUI = panel:FindFirstAncestorWhichIsA("LayerCollector")
				drag:SetAttribute(BUILDER, "header")
				drag:SetAttribute("QuadroDragHeader", target.Name)
			elseif chosen == "bounded" then
				drag.BoundingUI = target.Parent :: GuiBase2d
				drag:SetAttribute(BUILDER, "bounded")
				drag:SetAttribute("QuadroDragHeader", nil)
			else
				drag.BoundingUI = nil
				drag:SetAttribute(BUILDER, "free")
				drag:SetAttribute("QuadroDragHeader", nil)
			end
			return true
		end)
	end)
end

local function countedKey(ctx: any, key: string, count: number): string
	local one = key .. "_one"
	if count == 1 and ctx.t(one) ~= one then
		return one
	end
	return key
end

local function boxOf(item: GuiObject): BuilderMath.Box
	return { x = item.AbsolutePosition.X, y = item.AbsolutePosition.Y, w = item.AbsoluteSize.X, h = item.AbsoluteSize.Y }
end

local function navButton(name: string, text: string, direction: string, layoutPath: string, order: number, model: GuiObject, box: BuilderMath.Box, parent: Instance)
	local button = Instance.new("TextButton")
	button.Name = uniqueName(parent, name)
	button.ZIndex = model.ZIndex + 1
	button.AnchorPoint = Vector2.zero
	button.Size = model.Size
	button.Position = model.Position
	button.Text = text
	button.TextScaled = true
	button.LayoutOrder = order
	button.Parent = parent
	Gui.setBox(button, Vector2.new(box.x, box.y), Vector2.new(box.w, box.h))
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = BuilderMath.BUTTON_TEXT_MAX
	limit.MinTextSize = BuilderMath.BUTTON_TEXT_MIN
	limit.Parent = button
	button:SetAttribute("QuadroPageTarget", layoutPath)
	button:SetAttribute("QuadroPageDirection", direction)
	CollectionService:AddTag(button, NAV_TAG)
end

local function registerPages(registry: any)
	registry:define("builder.pages", "cmd_pages", function(ctx)
		local picked: { GuiObject } = {}
		for _, selected in SelectionService:Get() do
			if selected:IsA("GuiObject") then
				table.insert(picked, selected)
			end
		end
		if #picked < 2 then
			return fail("error_layout_two")
		end
		local parent = picked[1].Parent
		if parent == nil then
			return fail("error_no_applicable")
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
		local items: { GuiObject } = {}
		for _, item in picked do
			if item.Parent ~= parent then
				skip("result_pages_parent")
			elseif Gui.renderedParent(item) == nil or item.AbsoluteSize.X <= 0 or item.AbsoluteSize.Y <= 0 then
				skip("result_tool_skipped")
			elseif Gui.placingLayout(item) ~= nil then
				skip("result_layout_placed")
			else
				table.insert(items, item)
			end
		end
		if #items < 2 then
			return fail("error_layout_two")
		end
		local settle = pageMotion()
		if settle == nil then
			warn("[Quadro] builder.pages: runtime failed to load")
			return fail("error_command_failed")
		end
		local runtimeReport: Installer.Report? = nil
		local container: Frame? = nil
		local ok, cause = History.record("builder.pages", function()
			local boxes: { BuilderMath.Box } = {}
			for _, item in items do
				table.insert(boxes, boxOf(item))
			end
			local area = BuilderMath.bounds(boxes)
			local model = items[1]
			local frame = Instance.new("Frame")
			frame.Name = uniqueName(parent, PAGES_NAME)
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			frame.AnchorPoint = Vector2.zero
			frame.Size = model.Size
			frame.Position = model.Position
			frame.ZIndex = model.ZIndex
			frame.ClipsDescendants = true
			frame.Parent = parent
			Gui.setBox(frame, Vector2.new(area.x, area.y), Vector2.new(area.w, area.h))
			local layout = Instance.new("UIPageLayout")
			layout.Animated = true
			layout.EasingStyle = settle.style
			layout.EasingDirection = settle.direction
			layout.TweenTime = settle.time
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 0)
			layout.Circular = false
			layout.Parent = frame
			for index, item in items do
				item.AnchorPoint = Vector2.zero
				item.Size = UDim2.fromScale(1, 1)
				item.Position = UDim2.fromScale(0, 0)
				item.LayoutOrder = index
				item.Parent = frame
			end
			local previousBox, nextBox = BuilderMath.navBoxes(area)
			local layoutPath = "../" .. frame.Name .. "/" .. layout.Name
			navButton(PREVIOUS_NAME, ctx.t("pages_previous"), "previous", layoutPath, 1, model, previousBox, parent)
			navButton(NEXT_NAME, ctx.t("pages_next"), "next", layoutPath, 2, model, nextBox, parent)
			runtimeReport = Installer.install()
			container = frame
			return #items
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] builder.pages: " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		if container then
			SelectionService:Set({ container })
		end
		ctx.notify(ctx.t("result_pages_made", #items), "success")
		for _, key in order do
			ctx.notify(ctx.t(countedKey(ctx, key, reasons[key]), reasons[key]), "warning")
		end
		ToolsPlus.announceRuntime(ctx, runtimeReport)
		return { ok = true, count = #items }
	end)
end

function Builders.register(registry: any)
	registerPath(registry)
	registerDrag(registry)
	registerPages(registry)
end

return Builders
