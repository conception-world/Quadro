--!strict
local Geometry = require(script.Parent.Parent.Geometry)

local Gui = {}

function Gui.renderParent(inst: Instance): Instance?
	local parent = inst.Parent
	while parent and not parent:IsA("GuiBase2d") do
		parent = parent.Parent
	end
	return parent
end

function Gui.renderedParent(inst: Instance): Instance?
	if inst:FindFirstAncestorWhichIsA("LayerCollector") == nil then
		return nil
	end
	return Gui.renderParent(inst)
end

function Gui.unitScale(inst: Instance): number
	local factor = 1
	local current: Instance? = inst
	while current do
		if current:IsA("GuiBase2d") then
			local uiScale = current:FindFirstChildOfClass("UIScale")
			if uiScale then
				factor *= uiScale.Scale
			end
		end
		current = current.Parent
	end
	return factor
end

function Gui.contentBox(container: Instance?): (Vector2, Vector2, number)
	if not container then
		local camera = workspace.CurrentCamera
		return Vector2.zero, if camera then camera.ViewportSize else Vector2.new(1920, 1080), 1
	end
	local unit = Gui.unitScale(container)
	local origin: Vector2
	local size: Vector2
	if container:IsA("ScrollingFrame") then
		origin = container.AbsolutePosition - container.CanvasPosition
		size = container.AbsoluteCanvasSize
	else
		local base = container :: GuiBase2d
		origin = base.AbsolutePosition
		size = base.AbsoluteSize
	end
	local padding = container:FindFirstChildOfClass("UIPadding")
	if padding then
		local left = padding.PaddingLeft.Scale * size.X + padding.PaddingLeft.Offset * unit
		local top = padding.PaddingTop.Scale * size.Y + padding.PaddingTop.Offset * unit
		local right = padding.PaddingRight.Scale * size.X + padding.PaddingRight.Offset * unit
		local bottom = padding.PaddingBottom.Scale * size.Y + padding.PaddingBottom.Offset * unit
		origin += Vector2.new(left, top)
		size -= Vector2.new(left + right, top + bottom)
	end
	return origin, size, unit
end

function Gui.sizeRefs(inst: GuiObject, box: Vector2): Vector2
	local constraint = inst.SizeConstraint
	if constraint == Enum.SizeConstraint.RelativeXX then
		return Vector2.new(box.X, box.X)
	end
	if constraint == Enum.SizeConstraint.RelativeYY then
		return Vector2.new(box.Y, box.Y)
	end
	return box
end

local function solve(value: UDim, px: number, ref: number, unit: number, preferScale: boolean): UDim
	local scale, offset = Geometry.solveAxis(value.Scale, value.Offset, px, ref, unit, preferScale)
	return UDim.new(scale, offset)
end

export type Snapshot = { inst: GuiObject, point: Vector2, raw: Vector2, pos: Vector2, size: Vector2 }

function Gui.ownScale(inst: Instance): number
	local uiScale = inst:FindFirstChildOfClass("UIScale")
	return if uiScale then uiScale.Scale else 1
end

function Gui.placingLayout(inst: Instance): UIGridStyleLayout?
	local parent = inst.Parent
	if parent and parent:IsA("GuiBase2d") then
		return parent:FindFirstChildWhichIsA("UIGridStyleLayout")
	end
	return nil
end

function Gui.snapshot(inst: GuiObject): Snapshot
	local _, box, unit = Gui.contentBox(Gui.renderParent(inst))
	local refs = Gui.sizeRefs(inst, box)
	local size = inst.Size
	return {
		inst = inst,
		point = inst.AbsolutePosition + inst.AnchorPoint * inst.AbsoluteSize,
		raw = Vector2.new(size.X.Scale * refs.X + size.X.Offset * unit, size.Y.Scale * refs.Y + size.Y.Offset * unit),
		pos = inst.AbsolutePosition,
		size = inst.AbsoluteSize,
	}
end

function Gui.restore(snap: Snapshot)
	local inst = snap.inst
	local origin, box, unit = Gui.contentBox(Gui.renderParent(inst))
	local layout = Gui.placingLayout(inst)
	if not (layout and layout:IsA("UIGridLayout")) then
		local refs = Gui.sizeRefs(inst, box)
		local current, position = inst.Size, inst.Position
		inst.Size = UDim2.new(
			solve(current.X, snap.raw.X, refs.X, unit, position.X.Scale ~= 0),
			solve(current.Y, snap.raw.Y, refs.Y, unit, position.Y.Scale ~= 0)
		)
	end
	if not layout then
		local target = snap.point - origin
		local current, position = inst.Size, inst.Position
		inst.Position = UDim2.new(
			solve(position.X, target.X, box.X, unit, current.X.Scale ~= 0),
			solve(position.Y, target.Y, box.Y, unit, current.Y.Scale ~= 0)
		)
	end
end

function Gui.setBox(inst: GuiObject, topLeft: Vector2, size: Vector2)
	Gui.restore({
		inst = inst,
		point = topLeft + inst.AnchorPoint * size,
		raw = size / Gui.ownScale(inst),
		pos = topLeft,
		size = size,
	})
end

function Gui.collectChildren(container: Instance, out: { GuiObject }?): { GuiObject }
	local list: { GuiObject } = out or {}
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(list, child)
		elseif not child:IsA("UIBase") and not child:IsA("GuiBase2d") then
			Gui.collectChildren(child, list)
		end
	end
	return list
end

return Gui
