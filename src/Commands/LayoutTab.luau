--!strict
local Geometry = require(script.Parent.Parent.Geometry)
local Gui = require(script.Parent.Parent.Studio.Gui)
local Selection = require(script.Parent.Parent.Studio.Selection)
local ToolsPlus = require(script.Parent.ToolsPlus)

local LayoutTab = {}

local EDGES: { [string]: { axis: string, edge: Geometry.AlignEdge } } = {
	left = { axis = "x", edge = "min" },
	hcenter = { axis = "x", edge = "center" },
	right = { axis = "x", edge = "max" },
	top = { axis = "y", edge = "min" },
	vcenter = { axis = "y", edge = "center" },
	bottom = { axis = "y", edge = "max" },
}

local FLEX_ALIGNMENTS: { [string]: Enum.UIFlexAlignment } = {
	none = Enum.UIFlexAlignment.None,
	fill = Enum.UIFlexAlignment.Fill,
	spaceAround = Enum.UIFlexAlignment.SpaceAround,
	spaceBetween = Enum.UIFlexAlignment.SpaceBetween,
	spaceEvenly = Enum.UIFlexAlignment.SpaceEvenly,
}

local FLEX_MODES: { [string]: Enum.UIFlexMode } = {
	none = Enum.UIFlexMode.None,
	fill = Enum.UIFlexMode.Fill,
	grow = Enum.UIFlexMode.Grow,
	shrink = Enum.UIFlexMode.Shrink,
}

local CONSTRAINT_KINDS = { size = true, aspect = true, both = true }
local LIMIT_MIN = 0.5
local LIMIT_MAX = 2

local function fail(message: string): any
	return { ok = false, count = 0, message = message }
end

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function movableVerdict(item: GuiObject): boolean | string
	if Gui.renderedParent(item) == nil or item.AbsoluteSize.X <= 0 or item.AbsoluteSize.Y <= 0 then
		return "result_tool_skipped"
	end
	if Gui.placingLayout(item) ~= nil then
		return "result_layout_placed"
	end
	return true
end

local function moveTo(item: GuiObject, topLeft: Vector2)
	local snap = Gui.snapshot(item)
	snap.point += topLeft - item.AbsolutePosition
	Gui.restore(snap)
end

local function usable(items: { GuiObject }): { GuiObject }
	local list: { GuiObject } = {}
	for _, item in items do
		if movableVerdict(item) == true then
			table.insert(list, item)
		end
	end
	return list
end

local function axisValue(vector: Vector2, axis: string): number
	return if axis == "x" then vector.X else vector.Y
end

local function withAxis(vector: Vector2, axis: string, value: number): Vector2
	return if axis == "x" then Vector2.new(value, vector.Y) else Vector2.new(vector.X, value)
end

local function applyAxis(ctx: any, id: string, targets: { GuiObject }, axis: string, positions: { [GuiObject]: number }): any
	return ToolsPlus.execute(ctx, id, targets, movableVerdict, function(item: GuiObject)
		local value = positions[item]
		if value == nil then
			return false
		end
		moveTo(item, withAxis(item.AbsolutePosition, axis, value))
		return true
	end)
end

local function spansOf(items: { GuiObject }, axis: string): { Geometry.Span }
	local spans: { Geometry.Span } = {}
	for index, item in items do
		spans[index] = { pos = axisValue(item.AbsolutePosition, axis), size = axisValue(item.AbsoluteSize, axis) }
	end
	return spans
end

local function mapPositions(items: { GuiObject }, positions: { number }): { [GuiObject]: number }
	local map: { [GuiObject]: number } = {}
	for index, item in items do
		map[item] = positions[index]
	end
	return map
end

local function selectedContainer(): (GuiBase2d?, string?)
	local selected: { GuiBase2d } = {}
	for _, instance in game:GetService("Selection"):Get() do
		if instance:IsA("GuiBase2d") then
			table.insert(selected, instance)
		end
	end
	if #selected == 0 then
		return nil, "error_no_selection"
	end
	if #selected == 1 then
		local only = selected[1]
		for _, child in only:GetChildren() do
			if child:IsA("GuiObject") then
				return only, nil
			end
		end
		return nil, "error_layout_no_children"
	end
	local parent = selected[1].Parent
	for _, item in selected do
		if item.Parent ~= parent then
			return nil, "error_mixed_parents"
		end
	end
	if parent == nil or not parent:IsA("GuiBase2d") then
		return nil, "error_layout_no_container"
	end
	return parent, nil
end

local function containerChildren(container: GuiBase2d): { GuiObject }
	local list: { GuiObject } = {}
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child.AbsoluteSize.X > 0 and child.AbsoluteSize.Y > 0 then
			table.insert(list, child)
		end
	end
	return list
end

local function childBoxes(container: GuiBase2d, children: { GuiObject }): { Geometry.Box }
	local origin = Gui.contentBox(container)
	local boxes: { Geometry.Box } = {}
	for index, child in children do
		local pos = child.AbsolutePosition - origin
		boxes[index] = { x = pos.X, y = pos.Y, w = child.AbsoluteSize.X, h = child.AbsoluteSize.Y }
	end
	return boxes
end

local function containerVerdict(container: GuiBase2d, allowed: string): boolean | string
	local _, box = Gui.contentBox(container)
	if box.X <= 0 or box.Y <= 0 or #containerChildren(container) == 0 then
		return "result_tool_skipped"
	end
	local layout = container:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout ~= nil and not layout:IsA(allowed) then
		return if allowed == "UIGridLayout" then "result_grid_has_layout" else "result_flex_has_layout"
	end
	return true
end

local function reuse(parent: Instance, className: string): Instance
	local found = parent:FindFirstChildOfClass(className)
	if found then
		return found
	end
	local created = Instance.new(className)
	created.Parent = parent
	return created
end

local function autoGrid(container: GuiBase2d): boolean
	local children = containerChildren(container)
	local _, box = Gui.contentBox(container)
	local guess = Geometry.gridGuess(childBoxes(container, children))
	local grid = reuse(container, "UIGridLayout") :: UIGridLayout
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	for rank, index in guess.order do
		children[index].LayoutOrder = rank
	end
	grid.CellSize = UDim2.fromScale(Geometry.toScale(guess.cellW, box.X), Geometry.toScale(guess.cellH, box.Y))
	grid.CellPadding = UDim2.fromScale(Geometry.toScale(guess.gapX, box.X), Geometry.toScale(guess.gapY, box.Y))
	if guess.aspect then
		local aspect = reuse(grid, "UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.AspectRatio = Geometry.round4(guess.aspect)
	end
	return true
end

local function flexLayout(container: GuiBase2d, horizontal: boolean, hFlex: string, vFlex: string, wraps: boolean, item: string): boolean
	local children = containerChildren(container)
	local _, box = Gui.contentBox(container)
	local guess = Geometry.gridGuess(childBoxes(container, children))
	local existing = container:FindFirstChildOfClass("UIListLayout")
	local list = reuse(container, "UIListLayout") :: UIListLayout
	if existing == nil then
		list.Padding = UDim.new(Geometry.toScale(if horizontal then guess.gapX else guess.gapY, if horizontal then box.X else box.Y), 0)
	end
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	list.HorizontalFlex = FLEX_ALIGNMENTS[hFlex]
	list.VerticalFlex = FLEX_ALIGNMENTS[vFlex]
	list.Wraps = wraps
	local boxes = childBoxes(container, children)
	local order: { number } = {}
	for index = 1, #children do
		order[index] = index
	end
	table.sort(order, function(a: number, b: number)
		local left, right = boxes[a], boxes[b]
		local first, second = if horizontal then left.x else left.y, if horizontal then right.x else right.y
		if first ~= second then
			return first < second
		end
		return a < b
	end)
	for rank, index in order do
		children[index].LayoutOrder = rank
		if item ~= "none" then
			local flex = reuse(children[index], "UIFlexItem") :: UIFlexItem
			flex.FlexMode = FLEX_MODES[item]
			flex.GrowRatio = 1
			flex.ShrinkRatio = 1
		else
			local flexItem = children[index]:FindFirstChildOfClass("UIFlexItem")
			if flexItem then
				flexItem.FlexMode = Enum.UIFlexMode.None
			end
		end
	end
	return true
end

local function constrain(gui: GuiObject, kind: string): boolean
	local abs = gui.AbsoluteSize
	local unit = Gui.unitScale(gui)
	if kind ~= "aspect" then
		local limit = reuse(gui, "UISizeConstraint") :: UISizeConstraint
		local minX, minY, maxX, maxY = Geometry.sizeLimits(abs.X / unit, abs.Y / unit, LIMIT_MIN, LIMIT_MAX)
		limit.MinSize = Vector2.new(minX, minY)
		limit.MaxSize = Vector2.new(maxX, maxY)
	end
	if kind ~= "size" then
		local aspect = reuse(gui, "UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.AspectRatio = Geometry.round4(abs.X / abs.Y)
	end
	return true
end

function LayoutTab.register(registry: any)
	registry:define("layout.align", "cmd_align", function(ctx, edge: any, first: any)
		local spec = if type(edge) == "string" then EDGES[edge] else nil
		if spec == nil or (first ~= nil and type(first) ~= "boolean") then
			return fail("error_bad_args")
		end
		local items = Selection.guiTargets()
		if #items < 2 then
			return fail("error_layout_two")
		end
		local reference = usable(items)
		local targets = items
		local refMin, refMax = math.huge, -math.huge
		if first == true then
			local anchor = items[1]
			refMin = axisValue(anchor.AbsolutePosition, spec.axis)
			refMax = refMin + axisValue(anchor.AbsoluteSize, spec.axis)
			targets = table.move(items, 2, #items, 1, {})
		else
			for _, item in reference do
				local low = axisValue(item.AbsolutePosition, spec.axis)
				refMin = math.min(refMin, low)
				refMax = math.max(refMax, low + axisValue(item.AbsoluteSize, spec.axis))
			end
		end
		if refMin == math.huge then
			return fail("error_no_applicable")
		end
		local positions: { [GuiObject]: number } = {}
		for _, item in targets do
			positions[item] = Geometry.alignAxis(
				spec.edge,
				axisValue(item.AbsolutePosition, spec.axis),
				axisValue(item.AbsoluteSize, spec.axis),
				refMin,
				refMax
			)
		end
		return applyAxis(ctx, "layout.align", targets, spec.axis, positions)
	end)

	registry:define("layout.distribute", "cmd_distribute", function(ctx, axisId: any)
		local id = if axisId == nil then "h" else axisId
		if id ~= "h" and id ~= "v" then
			return fail("error_bad_args")
		end
		local axis = if id == "h" then "x" else "y"
		local items = Selection.guiTargets()
		local movable = usable(items)
		if #movable < 3 then
			return fail("error_layout_three")
		end
		local positions = Geometry.distributeAxis(spansOf(movable, axis))
		return applyAxis(ctx, "layout.distribute", items, axis, mapPositions(movable, positions))
	end)

	registry:define("layout.matchSpacing", "cmd_match_spacing", function(ctx, axisId: any, gap: any)
		local id = if axisId == nil then "h" else axisId
		if (id ~= "h" and id ~= "v") or (gap ~= nil and (not isNumber(gap) or gap < 0)) then
			return fail("error_bad_args")
		end
		local axis = if id == "h" then "x" else "y"
		local items = Selection.guiTargets()
		local movable = usable(items)
		if #movable < 2 then
			return fail("error_layout_two")
		end
		local positions = Geometry.spacingAxis(spansOf(movable, axis), gap)
		return applyAxis(ctx, "layout.matchSpacing", items, axis, mapPositions(movable, positions))
	end)

	registry:define("layout.matchSize", "cmd_match_size", function(ctx, which: any)
		local mode = if which == nil then "both" else which
		if mode ~= "w" and mode ~= "h" and mode ~= "both" then
			return fail("error_bad_args")
		end
		local items = Selection.guiTargets()
		if #items < 2 then
			return fail("error_layout_two")
		end
		local size = items[1].AbsoluteSize
		local targets = table.move(items, 2, #items, 1, {})
		return ToolsPlus.execute(ctx, "layout.matchSize", targets, movableVerdict, function(item: GuiObject)
			local current = item.AbsoluteSize
			Gui.setBox(
				item,
				item.AbsolutePosition,
				Vector2.new(if mode ~= "h" then size.X else current.X, if mode ~= "w" then size.Y else current.Y)
			)
			return true
		end)
	end)

	registry:define("layout.autoGrid", "cmd_auto_grid", function(ctx)
		local container, problem = selectedContainer()
		if container == nil then
			return fail(problem or "error_no_applicable")
		end
		local target = container
		return ToolsPlus.execute(ctx, "layout.autoGrid", { target }, function(item: GuiBase2d)
			return containerVerdict(item, "UIGridLayout")
		end, autoGrid)
	end)

	registry:define("layout.flex", "cmd_flex", function(ctx, dir: any, hFlex: any, vFlex: any, wraps: any, item: any)
		local direction = if dir == nil then "h" else dir
		local horizontalFlex = if hFlex == nil then "none" else hFlex
		local verticalFlex = if vFlex == nil then "none" else vFlex
		local wrap = if wraps == nil then false else wraps
		local mode = if item == nil then "fill" else item
		if
			(direction ~= "h" and direction ~= "v")
			or FLEX_ALIGNMENTS[horizontalFlex] == nil
			or FLEX_ALIGNMENTS[verticalFlex] == nil
			or type(wrap) ~= "boolean"
			or FLEX_MODES[mode] == nil
		then
			return fail("error_bad_args")
		end
		local container, problem = selectedContainer()
		if container == nil then
			return fail(problem or "error_no_applicable")
		end
		local target = container
		return ToolsPlus.execute(ctx, "layout.flex", { target }, function(candidate: GuiBase2d)
			return containerVerdict(candidate, "UIListLayout")
		end, function(candidate: GuiBase2d)
			return flexLayout(candidate, direction == "h", horizontalFlex, verticalFlex, wrap, mode)
		end)
	end)

	registry:define("layout.constraints", "cmd_constraints", function(ctx, kind: any)
		local which = if kind == nil then "both" else kind
		if not CONSTRAINT_KINDS[which] then
			return fail("error_bad_args")
		end
		return ToolsPlus.execute(ctx, "layout.constraints", Selection.guiTargets(), function(gui: GuiObject)
			local abs = gui.AbsoluteSize
			return abs.X > 0 and abs.Y > 0 and Gui.unitScale(gui) > 0
		end, function(gui: GuiObject)
			return constrain(gui, which)
		end)
	end)

	registry:define("layout.reparent", "cmd_reparent", function(ctx)
		local picked = game:GetService("Selection"):Get()
		if #picked < 2 then
			return fail("error_layout_two")
		end
		local destination = picked[#picked]
		if not destination:IsA("GuiBase2d") then
			return fail("error_reparent_dest")
		end
		local snaps: { [Instance]: Gui.Snapshot } = {}
		local items: { Instance } = {}
		for index = 1, #picked - 1 do
			local item = picked[index]
			table.insert(items, item)
			if item:IsA("GuiObject") and Gui.renderedParent(item) ~= nil then
				snaps[item] = Gui.snapshot(item)
			end
		end
		local layout = destination:FindFirstChildWhichIsA("UIGridStyleLayout")
		local result = ToolsPlus.execute(ctx, "layout.reparent", items, function(item: Instance)
			if snaps[item] == nil then
				return "result_tool_skipped"
			end
			if item == destination or destination:IsDescendantOf(item) then
				return "result_reparent_descendant"
			end
			if item.Parent == destination then
				return "result_reparent_same"
			end
			return true
		end, function(item: GuiObject)
			item.Parent = destination
			Gui.restore(snaps[item])
			return true
		end)
		if result.ok and layout ~= nil then
			ctx.notify(ctx.t("result_reparent_layout"), "warning")
		end
		return result
	end)
end

return LayoutTab
