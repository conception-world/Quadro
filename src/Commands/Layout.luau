--!strict
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Layout = {}

local SIZING_COMPONENTS: { [string]: boolean } = {
	UIAspectRatioConstraint = true,
	UISizeConstraint = true,
	UIFlexItem = true,
	UIScale = true,
}

local function newWrapper(className: string, name: string): GuiObject
	local wrapper = Instance.new(className) :: GuiObject
	wrapper.Name = name
	wrapper.BackgroundTransparency = 1
	wrapper.BorderSizePixel = 0
	if wrapper:IsA("TextButton") then
		wrapper.Text = ""
		wrapper.AutoButtonColor = false
	end
	return wrapper
end

local function restoreAll(snaps: { Gui.Snapshot }, shift: Vector2?)
	for _, snap in snaps do
		if shift then
			snap.point += shift
		end
		Gui.restore(snap)
	end
end

local function failure(id: string, cause: any): any
	if cause == "busy" then
		return { ok = false, count = 0, message = "error_busy" }
	end
	warn("[Quadro] " .. id .. ": " .. tostring(cause))
	return { ok = false, count = 0, message = "error_command_failed" }
end

local function resolveUDim(value: UDim, px: number, ref: number, unit: number): UDim
	if value.Scale ~= 0 and ref > 0 then
		return UDim.new((px - value.Offset * unit) / ref, value.Offset)
	end
	if unit <= 0 then
		return value
	end
	return UDim.new(0, math.round(px / unit))
end

local function holdContents(container: GuiObject): (Vector2?) -> ()
	local snaps: { Gui.Snapshot } = {}
	for _, child in Gui.collectChildren(container) do
		table.insert(snaps, Gui.snapshot(child))
	end
	local layout = container:FindFirstChildWhichIsA("UIGridStyleLayout")
	local _, box, unit = Gui.contentBox(container)
	local list = if layout and layout:IsA("UIListLayout") then layout else nil
	local grid = if layout and layout:IsA("UIGridLayout") then layout else nil
	local horizontal = list ~= nil and list.FillDirection == Enum.FillDirection.Horizontal
	local listPadding = 0
	local cellSize = Vector2.zero
	local cellPadding = Vector2.zero
	if list then
		listPadding = list.Padding.Scale * (if horizontal then box.X else box.Y) + list.Padding.Offset * unit
	elseif grid then
		local cell, gap = grid.CellSize, grid.CellPadding
		cellSize = Vector2.new(cell.X.Scale * box.X + cell.X.Offset * unit, cell.Y.Scale * box.Y + cell.Y.Offset * unit)
		cellPadding = Vector2.new(gap.X.Scale * box.X + gap.X.Offset * unit, gap.Y.Scale * box.Y + gap.Y.Offset * unit)
	end
	return function(shift: Vector2?)
		local _, newBox = Gui.contentBox(container)
		if list then
			list.Padding = resolveUDim(list.Padding, listPadding, if horizontal then newBox.X else newBox.Y, unit)
		elseif grid then
			local cell, gap = grid.CellSize, grid.CellPadding
			grid.CellSize = UDim2.new(
				resolveUDim(cell.X, cellSize.X, newBox.X, unit),
				resolveUDim(cell.Y, cellSize.Y, newBox.Y, unit)
			)
			grid.CellPadding = UDim2.new(
				resolveUDim(gap.X, cellPadding.X, newBox.X, unit),
				resolveUDim(gap.Y, cellPadding.Y, newBox.Y, unit)
			)
		end
		restoreAll(snaps, shift)
	end
end

local function sharedParent(items: { GuiObject }): Instance?
	local parent = items[1].Parent
	for _, item in items do
		if item.Parent ~= parent then
			return nil
		end
	end
	return parent
end

local function predominantAnchor(items: { GuiObject }): Vector2
	local best, bestCount = items[1].AnchorPoint, 0
	local counts: { [string]: number } = {}
	for _, item in items do
		local key = tostring(item.AnchorPoint)
		local count = (counts[key] or 0) + 1
		counts[key] = count
		if count > bestCount then
			best, bestCount = item.AnchorPoint, count
		end
	end
	return best
end

local function defineGroup(registry: any, id: string, labelKey: string, className: string)
	registry:define(id, labelKey, function(ctx)
		local items = Selection.guiTargets()
		if #items == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local parent = sharedParent(items)
		if parent == nil then
			return { ok = false, count = 0, message = "error_mixed_parents" }
		end
		if Gui.renderedParent(items[1]) == nil then
			return { ok = false, count = 0, message = "result_ignored_no_parent", args = { #items } }
		end
		local wrapper: GuiObject? = nil
		local placed = false
		local ok, cause = History.record(id, function()
			local snaps: { Gui.Snapshot } = {}
			local minCorner = Vector2.new(math.huge, math.huge)
			local maxCorner = Vector2.new(-math.huge, -math.huge)
			local offsetX, offsetY = true, true
			local zIndex, layoutOrder = items[1].ZIndex, items[1].LayoutOrder
			for _, item in items do
				local snap = Gui.snapshot(item)
				table.insert(snaps, snap)
				minCorner = minCorner:Min(snap.pos)
				maxCorner = maxCorner:Max(snap.pos + snap.size)
				offsetX = offsetX and item.Position.X.Scale == 0 and item.Size.X.Scale == 0
				offsetY = offsetY and item.Position.Y.Scale == 0 and item.Size.Y.Scale == 0
				zIndex = math.max(zIndex, item.ZIndex)
				layoutOrder = math.min(layoutOrder, item.LayoutOrder)
			end
			local span = maxCorner - minCorner
			if span.X <= 0 or span.Y <= 0 then
				error("selection has no measurable bounds")
			end
			local group = newWrapper(className, "Group")
			local unitX, unitY = if offsetX then 0 else 1, if offsetY then 0 else 1
			group.AnchorPoint = predominantAnchor(items)
			group.Position = UDim2.fromScale(unitX, unitY)
			group.Size = UDim2.fromScale(unitX, unitY)
			group.ZIndex = zIndex
			group.LayoutOrder = layoutOrder
			group.Parent = parent
			Gui.setBox(group, minCorner, span)
			for _, snap in snaps do
				snap.inst.Parent = group
			end
			local layout = Gui.placingLayout(group)
			restoreAll(snaps, if layout then group.AbsolutePosition - minCorner else nil)
			placed = layout ~= nil
			wrapper = group
			return #items
		end, { nested = ctx.fromHook })
		if not ok then
			return failure(id, cause)
		end
		if wrapper then
			Selection.set({ wrapper })
		end
		ctx.notify(ctx.t("result_grouped", #items), "success")
		if placed then
			ctx.notify(ctx.t("result_group_placed"), "warning")
		end
		return { ok = true, count = #items }
	end)
end

local function defineEach(
	registry: any,
	id: string,
	labelKey: string,
	successKey: string,
	ignoredKey: string,
	collect: () -> { Instance },
	work: (Instance, { Instance }) -> boolean
)
	registry:define(id, labelKey, function(ctx)
		local targets = collect()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local done, ignored = 0, 0
		local result: { Instance } = {}
		local ok, cause = History.record(id, function()
			for _, target in targets do
				if work(target, result) then
					done += 1
				else
					ignored += 1
				end
			end
			return done
		end, { nested = ctx.fromHook })
		if not ok then
			return failure(id, cause)
		end
		if done > 0 then
			if #result > 0 then
				Selection.set(result)
			end
			ctx.notify(ctx.t(successKey, done), "success")
		end
		if ignored > 0 then
			ctx.notify(ctx.t(ignoredKey, ignored), "warning")
		end
		if done == 0 then
			return { ok = false, count = 0, message = ignoredKey, args = { ignored } }
		end
		return { ok = true, count = done }
	end)
end

local function groupEach(target: Instance, result: { Instance }): boolean
	local item = target :: GuiObject
	if Gui.renderedParent(item) == nil then
		return false
	end
	local wrapper = newWrapper("Frame", item.Name .. "Group")
	wrapper.AnchorPoint = item.AnchorPoint
	wrapper.Position = item.Position
	wrapper.Size = item.Size
	wrapper.SizeConstraint = item.SizeConstraint
	wrapper.AutomaticSize = item.AutomaticSize
	wrapper.ZIndex = item.ZIndex
	wrapper.LayoutOrder = item.LayoutOrder
	wrapper.Parent = item.Parent
	for _, child in item:GetChildren() do
		if SIZING_COMPONENTS[child.ClassName] then
			child.Parent = wrapper
		end
	end
	item.Parent = wrapper
	item.AnchorPoint = Vector2.zero
	item.Position = UDim2.new()
	item.Size = UDim2.fromScale(1, 1)
	item.SizeConstraint = Enum.SizeConstraint.RelativeXY
	table.insert(result, wrapper)
	return true
end

local function ungroup(target: Instance, result: { Instance }): boolean
	local parent = target.Parent
	if not parent then
		return false
	end
	local children = Gui.collectChildren(target)
	if #children == 0 then
		return false
	end
	if target:IsA("GuiObject") then
		if Gui.renderedParent(target) == nil then
			return false
		end
		local snaps: { Gui.Snapshot } = {}
		for _, child in children do
			table.insert(snaps, Gui.snapshot(child))
		end
		local wrapperScale = Gui.ownScale(target)
		for _, child in target:GetChildren() do
			if child:IsA("GuiObject") or not child:IsA("UIBase") then
				child.Parent = parent
			end
		end
		if wrapperScale ~= 1 then
			for _, snap in snaps do
				local uiScale = snap.inst:FindFirstChildOfClass("UIScale")
				if not uiScale then
					uiScale = Instance.new("UIScale")
					uiScale.Parent = snap.inst
				end
				(uiScale :: UIScale).Scale *= wrapperScale
				snap.raw /= wrapperScale
			end
		end
		restoreAll(snaps)
	elseif target:IsA("Folder") then
		for _, child in target:GetChildren() do
			child.Parent = parent
		end
	else
		return false
	end
	for _, child in children do
		table.insert(result, child)
	end
	target.Parent = nil
	return true
end

local function fit(target: Instance, _: { Instance }): boolean
	local inst = target :: GuiObject
	if Gui.renderedParent(inst) == nil then
		return false
	end
	local minCorner: Vector2? = nil
	local maxCorner: Vector2? = nil
	for _, child in Gui.collectChildren(inst) do
		if child.Visible then
			local topLeft = child.AbsolutePosition
			local bottomRight = topLeft + child.AbsoluteSize
			minCorner = if minCorner then minCorner:Min(topLeft) else topLeft
			maxCorner = if maxCorner then maxCorner:Max(bottomRight) else bottomRight
		end
	end
	if not minCorner or not maxCorner then
		return false
	end
	local span = maxCorner - minCorner
	if span.X <= 0 or span.Y <= 0 then
		return false
	end
	local aspect = inst:FindFirstChildWhichIsA("UIAspectRatioConstraint")
	if aspect and aspect.AspectType == Enum.AspectType.ScaleWithParentSize then
		return false
	end
	local layout = inst:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout and (layout:IsA("UIGridLayout") or (layout:IsA("UIListLayout") and layout.Wraps)) then
		span += Vector2.one
	end
	local size, inset = span, Vector2.zero
	local padding = inst:FindFirstChildOfClass("UIPadding")
	if padding then
		local unit = Gui.unitScale(inst)
		local freeX = math.max(1 - padding.PaddingLeft.Scale - padding.PaddingRight.Scale, 0.01)
		local freeY = math.max(1 - padding.PaddingTop.Scale - padding.PaddingBottom.Scale, 0.01)
		size = Vector2.new(
			(span.X + (padding.PaddingLeft.Offset + padding.PaddingRight.Offset) * unit) / freeX,
			(span.Y + (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) * unit) / freeY
		)
		inset = Vector2.new(
			padding.PaddingLeft.Scale * size.X + padding.PaddingLeft.Offset * unit,
			padding.PaddingTop.Scale * size.Y + padding.PaddingTop.Offset * unit
		)
	end
	local release = holdContents(inst)
	if aspect then
		aspect.AspectRatio = size.X / size.Y
	end
	local topLeft = minCorner - inset
	Gui.setBox(inst, topLeft, size)
	release(if Gui.placingLayout(inst) then inst.AbsolutePosition - topLeft else nil)
	return true
end

local function expand(target: Instance, _: { Instance }): boolean
	local inst = target :: GuiObject
	local parent = Gui.renderedParent(inst)
	if parent == nil then
		return false
	end
	local origin, box = Gui.contentBox(parent)
	if box.X <= 0 or box.Y <= 0 then
		return false
	end
	local oldTopLeft = inst.AbsolutePosition
	local release = holdContents(inst)
	inst.SizeConstraint = Enum.SizeConstraint.RelativeXY
	Gui.setBox(inst, origin, box)
	release(if Gui.placingLayout(inst) then inst.AbsolutePosition - oldTopLeft else nil)
	return true
end

local function guiTargets(): { Instance }
	return Selection.guiTargets()
end

local function rawSelection(): { Instance }
	return game:GetService("Selection"):Get()
end

function Layout.register(registry: any)
	defineGroup(registry, "layout.group", "cmd_group", "Frame")
	defineGroup(registry, "layout.groupButton", "cmd_group_button", "TextButton")
	defineEach(registry, "layout.groupEach", "cmd_group_each", "result_grouped", "result_ignored_no_parent", guiTargets, groupEach)
	defineEach(registry, "layout.ungroup", "cmd_ungroup", "result_ungrouped", "result_ungroup_skipped", rawSelection, ungroup)
	defineEach(registry, "layout.fit", "cmd_fit", "result_fitted", "result_fit_skipped", guiTargets, fit)
	defineEach(registry, "layout.expand", "cmd_expand", "result_expanded", "result_ignored_no_parent", guiTargets, expand)
end

return Layout
