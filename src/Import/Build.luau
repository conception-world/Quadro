--!strict
local Geometry = require("../Geometry")
local History = require("../Studio/History")
local Fonts = require("./Fonts")
local Paint = require("./Paint")
local Plan = require("./Plan")
local Spec = require("./Spec")
local Templates = require("./Templates")
local Units = require("./Units")
local Validate = require("./Validate")

local Build = {}

export type Summary = {
	ok: boolean,
	created: number,
	updated: number,
	kept: number,
	removed: number,
	orphaned: number,
	pendingImages: number,
	warnings: { string },
	issues: { string },
	warningTargets: { [string]: string },
	issueTargets: { [string]: string },
	busy: boolean?,
	crashed: boolean?,
	screenGui: string?,
	rootId: string?,
	runtime: any?,
}

type Options = { library: Paint.Library, nested: boolean? }
type State = {
	doc: Spec.Doc,
	library: Paint.Library,
	warnings: { string },
	warningTargets: { [string]: string },
	created: number,
	updated: number,
	pending: number,
	index: { [string]: Instance },
	templates: { [string]: Instance },
	building: boolean,
	textScale: number,
}
type ParentBox = { innerW: number, innerH: number, pad: { number }, hasLayout: boolean, dir: string, isRoot: boolean, grid: boolean? }
type NodeLayout = typeof(({} :: Spec.Node).layout)
type Context = { children: { Spec.Node }, merged: Spec.Node?, layout: NodeLayout, grid: boolean, pad: { number }, spanW: number, spanH: number, childBox: ParentBox, free: boolean, freeBox: ParentBox }

local REFERENCE_W = 1920
local REFERENCE_H = 1080
local BATCH = 200
local ZERO_PAD = { 0, 0, 0, 0 }

local ALIGN_H: { [string]: Enum.HorizontalAlignment } = {
	MIN = Enum.HorizontalAlignment.Left,
	LEFT = Enum.HorizontalAlignment.Left,
	CENTER = Enum.HorizontalAlignment.Center,
	MAX = Enum.HorizontalAlignment.Right,
	RIGHT = Enum.HorizontalAlignment.Right,
}
local ALIGN_V: { [string]: Enum.VerticalAlignment } = {
	MIN = Enum.VerticalAlignment.Top,
	TOP = Enum.VerticalAlignment.Top,
	CENTER = Enum.VerticalAlignment.Center,
	MAX = Enum.VerticalAlignment.Bottom,
	BOTTOM = Enum.VerticalAlignment.Bottom,
}
local TEXT_X: { [string]: Enum.TextXAlignment } = {
	LEFT = Enum.TextXAlignment.Left,
	CENTER = Enum.TextXAlignment.Center,
	RIGHT = Enum.TextXAlignment.Right,
	JUSTIFIED = Enum.TextXAlignment.Center,
}
local TEXT_Y: { [string]: Enum.TextYAlignment } = {
	TOP = Enum.TextYAlignment.Top,
	CENTER = Enum.TextYAlignment.Center,
	BOTTOM = Enum.TextYAlignment.Bottom,
}
local MODIFIERS: { [string]: boolean } = {
	UICorner = true,
	UIStroke = true,
	UIShadow = true,
	UIGradient = true,
	UITextSizeConstraint = true,
	UIListLayout = true,
	UIGridLayout = true,
	UIPadding = true,
	UIAspectRatioConstraint = true,
	UIFlexItem = true,
	UIScale = true,
}
local CONTAINERS: { [string]: boolean } = { frame = true, list = true, grid = true, scroll = true, template = true }

local function maxAlpha(fill: Spec.Fill, tokens: { [string]: Spec.Linear }): number
	if fill.kind == "solid" then
		return fill.a
	end
	local linear: Spec.Linear? = if fill.kind == "linear" then fill else if fill.kind == "token" then tokens[fill.name] else nil
	if linear == nil then
		return 1
	end
	local best = 0
	for _, stop in linear.stops do
		best = math.max(best, stop.a)
	end
	return best
end

local function chooseFill(node: Spec.Node, tokens: { [string]: Spec.Linear }): (Spec.Fill?, number)
	local best: Spec.Fill? = nil
	local bestAlpha = -1
	for _, fill in node.fills do
		local alpha = maxAlpha(fill, tokens)
		if alpha > bestAlpha then
			best = fill
			bestAlpha = alpha
		end
	end
	return best, math.max(#node.fills - 1, 0)
end

local function className(node: Spec.Node, tokens: { [string]: Spec.Linear }): string
	local fill = chooseFill(node, tokens)
	local imageFill = fill ~= nil and fill.kind == "image"
	if node.kind == "text" then
		return "TextLabel"
	elseif node.kind == "button" then
		return if imageFill then "ImageButton" else "TextButton"
	elseif node.kind == "scroll" then
		return "ScrollingFrame"
	elseif imageFill then
		return "ImageLabel"
	end
	return "Frame"
end

local function tagWarnings(state: State, from: number, id: string)
	if state.building then
		return
	end
	for index = from + 1, #state.warnings do
		state.warningTargets[tostring(index)] = id
	end
end

local function applyText(gui: GuiObject, node: Spec.Node, opacity: number, state: State)
	local label = gui :: any
	label.TextScaled = true
	local text = node.text
	if text == nil then
		label.Text = ""
		return
	end
	local resolved = Fonts.resolve(text.family, text.weight, text.italic)
	if not resolved.known then
		table.insert(state.warnings, node.name .. ": font '" .. text.family .. "' not mapped, using Gotham")
	end
	label.Text = text.chars
	label.FontFace = Font.new(
		resolved.family,
		(Enum.FontWeight :: any)[resolved.weight],
		(Enum.FontStyle :: any)[resolved.style]
	)
	local r, g, b = Units.hexToRgb(text.hex)
	label.TextColor3 = Color3.new(r, g, b)
	label.TextTransparency = math.clamp(1 - text.a * opacity, 0, 1)
	label.TextXAlignment = TEXT_X[text.align[1]] or Enum.TextXAlignment.Left
	label.TextYAlignment = TEXT_Y[text.align[2]] or Enum.TextYAlignment.Center
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = math.max(Units.textMax(text.size * state.textScale), 8)
	constraint.MinTextSize = 8
	constraint.Parent = gui
	if text.stroke then
		Paint.stroke(label, text.stroke, node.box[3], node.box[4], opacity, true)
	end
end

local function applyImage(gui: GuiObject, fill: Spec.ImageFill, node: Spec.Node, opacity: number, state: State)
	local image = gui :: any
	local entry = if fill.hash then state.doc.images[fill.hash] else nil
	local asset = Spec.imageId(state.doc, fill)
	if asset then
		image.Image = asset
		gui:SetAttribute("QuadroPendingImage", nil)
	elseif image.Image == "" and fill.hash then
		gui:SetAttribute("QuadroPendingImage", fill.hash)
		state.pending += 1
	end
	image.ImageTransparency = math.clamp(1 - opacity, 0, 1)
	image.ResampleMode = Enum.ResamplerMode.Default
	local slice = node.slice
	if slice and not entry then
		table.insert(state.warnings, node.name .. ": slice ignored, image " .. (fill.hash or fill.asset or "?") .. " has no size entry")
	end
	if slice and entry then
		image.ScaleType = Enum.ScaleType.Slice
		image.SliceCenter = Rect.new(slice[1], slice[2], entry.w - slice[3], entry.h - slice[4])
	elseif fill.tile then
		image.ScaleType = Enum.ScaleType.Tile
		image.TileSize = UDim2.fromOffset(fill.tile[1], fill.tile[2])
		image.ResampleMode = Enum.ResamplerMode.Pixelated
	else
		image.ScaleType = if fill.scale == "fill" then Enum.ScaleType.Crop else Enum.ScaleType.Fit
	end
end

local function addAspect(gui: Instance, w: number, h: number)
	if w > 0 and h > 0 then
		local aspect = gui:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = w / h
		aspect.Parent = gui
	end
end

local function applyLayout(gui: GuiObject, layout: { dir: string, gap: number, align: { string }, wrap: boolean }?, grid: boolean, innerW: number, innerH: number, first: Spec.Node?)
	local dir = if layout then layout.dir else "V"
	local gap = if layout then layout.gap else 0
	if grid then
		local g = gui:FindFirstChildOfClass("UIGridLayout") or Instance.new("UIGridLayout")
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.FillDirection = if dir == "H" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		g.CellPadding = UDim2.fromScale(Units.gap(gap, "H", innerW, innerH), Units.gap(gap, "V", innerW, innerH))
		if first then
			local sx, sy = Units.size(first.box[3], first.box[4], innerW, innerH)
			g.CellSize = UDim2.fromScale(sx, sy)
			addAspect(g, first.box[3], first.box[4])
		else
			g.CellSize = UDim2.fromScale(0.25, 0.25)
		end
		g.Parent = gui
		return
	end
	local list = gui:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(Units.gap(gap, dir, innerW, innerH), 0)
	list.Wraps = layout ~= nil and layout.wrap
	local primary = if layout then layout.align[1] else "MIN"
	local cross = if layout then layout.align[2] else "MIN"
	local main = if primary == "SPACE_BETWEEN" then "MIN" else primary
	if dir ~= "H" then
		list.FillDirection = Enum.FillDirection.Vertical
		list.VerticalAlignment = ALIGN_V[main] or Enum.VerticalAlignment.Top
		list.HorizontalAlignment = ALIGN_H[cross] or Enum.HorizontalAlignment.Left
		if primary == "SPACE_BETWEEN" then
			list.VerticalFlex = Enum.UIFlexAlignment.SpaceBetween
		end
	else
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = ALIGN_H[main] or Enum.HorizontalAlignment.Left
		list.VerticalAlignment = ALIGN_V[cross] or Enum.VerticalAlignment.Top
		if primary == "SPACE_BETWEEN" then
			list.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
		end
	end
	list.Parent = gui
end

local function applySizing(gui: GuiObject, sizing: { h: string, v: string }, dir: string)
	local mainFill = if dir == "H" then sizing.h == "fill" elseif dir == "V" then sizing.v == "fill" else false
	if mainFill then
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = gui
	end
end

local function scrollExtent(node: Spec.Node, children: { Spec.Node }, layout: NodeLayout, pad: { number }): (number, number)
	local extentW, extentH = 0, 0
	if layout then
		local horizontal = layout.dir == "H"
		local main, cross = 0, 0
		for _, child in children do
			main += if horizontal then child.box[3] else child.box[4]
			cross = math.max(cross, if horizontal then child.box[4] else child.box[3])
		end
		main += layout.gap * math.max(#children - 1, 0)
		if horizontal then
			extentW, extentH = main + pad[2] + pad[4], cross + pad[1] + pad[3]
		else
			extentW, extentH = cross + pad[2] + pad[4], main + pad[1] + pad[3]
		end
	else
		for _, child in children do
			extentW = math.max(extentW, child.box[1] + child.box[3])
			extentH = math.max(extentH, child.box[2] + child.box[4])
		end
	end
	return math.max(extentW, node.box[3]), math.max(extentH, node.box[4])
end

local function foldPadding(node: Spec.Node, merged: Spec.Node, layout: { dir: string, padding: { number } }): { number }
	local p = layout.padding
	local m = merged.box
	local vertical = layout.dir ~= "H"
	local top = m[2] + p[1]
	local left = m[1] + p[4]
	local right = if vertical then node.box[3] - m[1] - m[3] + p[2] else p[2]
	local bottom = if vertical then p[3] else node.box[4] - m[2] - m[4] + p[3]
	return { math.max(top, 0), math.max(right, 0), math.max(bottom, 0), math.max(left, 0) }
end

local function configureScroll(scroll: ScrollingFrame, node: Spec.Node, context: Context, pbox: ParentBox, wrapped: boolean)
	local extentW, extentH = context.spanW, context.spanH
	local parentW = math.max(if wrapped then node.box[3] else pbox.innerW, 1)
	local parentH = math.max(if wrapped then node.box[4] else pbox.innerH, 1)
	local x = extentW > node.box[3] + 0.5
	local y = extentH > node.box[4] + 0.5 or not x
	local axis = if x and y then "XY" elseif x then "X" else "Y"
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.CanvasSize = UDim2.fromScale(if x then extentW / parentW else 0, if y then extentH / parentH else 0)
	scroll.VerticalScrollBarInset = if y then Enum.ScrollBarInset.ScrollBar else Enum.ScrollBarInset.None
	scroll.HorizontalScrollBarInset = if x then Enum.ScrollBarInset.ScrollBar else Enum.ScrollBarInset.None
	scroll.ScrollingDirection = (Enum.ScrollingDirection :: any)[axis]
	scroll.ScrollBarThickness = 4
end

local function applyPadding(gui: GuiObject, pad: { number }, w: number, h: number)
	local scales = Units.padding(pad, w, h)
	if scales[1] == 0 and scales[2] == 0 and scales[3] == 0 and scales[4] == 0 then
		return
	end
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(scales[1], 0)
	padding.PaddingRight = UDim.new(scales[2], 0)
	padding.PaddingBottom = UDim.new(scales[3], 0)
	padding.PaddingLeft = UDim.new(scales[4], 0)
	padding.Parent = gui
end

local function describe(node: Spec.Node, isRootNode: boolean): Context
	local children = node.children
	local source = node
	local merged: Spec.Node? = nil
	if node.kind == "scroll" and #children == 1 and children[1].layout then
		merged = children[1]
		source = children[1]
		children = children[1].children
	end
	local layout = source.layout
	local grid = node.kind == "grid"
	local flowing: { Spec.Node } = {}
	for _, child in children do
		if not child.absolute then
			table.insert(flowing, child)
		end
	end
	local free = (layout ~= nil or grid) and #flowing < #children
	local pad = if layout then layout.padding else ZERO_PAD
	if merged and layout then
		pad = foldPadding(node, merged, layout)
	end
	local spanW, spanH = node.box[3], node.box[4]
	if node.kind == "scroll" then
		spanW, spanH = scrollExtent(node, if free then flowing else children, layout, pad)
	end
	local innerW = Geometry.innerSize(spanW, pad[4], pad[2])
	local innerH = Geometry.innerSize(spanH, pad[1], pad[3])
	local origin = if merged then { -merged.box[2], 0, 0, -merged.box[1] } else ZERO_PAD
	return {
		children = children,
		merged = merged,
		layout = layout,
		grid = grid,
		pad = pad,
		spanW = spanW,
		spanH = spanH,
		childBox = { innerW = innerW, innerH = innerH, pad = pad, hasLayout = layout ~= nil or grid, dir = if layout then layout.dir else "", isRoot = isRootNode, grid = grid },
		free = free,
		freeBox = { innerW = spanW, innerH = spanH, pad = origin, hasLayout = false, dir = "", isRoot = isRootNode },
	}
end

local function isUserModifier(instance: Instance): boolean
	local parent = instance.Parent
	return MODIFIERS[instance.ClassName] == true
		and instance:GetAttribute("QuadroOwned") ~= true
		and parent ~= nil
		and parent:GetAttribute("QuadroStyled") == true
end

local function clearOwned(gui: GuiObject)
	local styled = gui:GetAttribute("QuadroStyled") == true
	for _, child in gui:GetChildren() do
		if MODIFIERS[child.ClassName] and not Validate.isEffectPiece(child) and (child:GetAttribute("QuadroOwned") == true or not styled) then
			child.Parent = nil
		end
	end
	gui.AutomaticSize = Enum.AutomaticSize.None
end

local function fitWrapper(wrapper: Frame, gui: GuiObject, name: string, w: number, h: number)
	wrapper.Name = name .. "Frame"
	wrapper.Visible = gui.Visible
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui:SetAttribute("AnchorReason", nil)
	gui.Size = UDim2.fromScale(1, 1)
	gui.Position = UDim2.fromScale(0.5, 0.5)
	gui.Rotation = 0
	local aspect = wrapper:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect == nil then
		aspect = Instance.new("UIAspectRatioConstraint")
		aspect:SetAttribute("QuadroOwned", true)
		aspect.Parent = wrapper
	end
	if w > 0 and h > 0 then
		aspect.AspectRatio = w / h
	end
end

local function fitSlot(slot: Frame, gui: GuiObject)
	slot.Name = "QuadroSlot"
	slot.Visible = gui.Visible
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui:SetAttribute("AnchorReason", nil)
	gui.Size = UDim2.fromScale(1, 1)
	gui.Position = UDim2.fromScale(0.5, 0.5)
end

local function snapshotChildren(frame: Instance): { [Instance]: boolean }
	local seen: { [Instance]: boolean } = {}
	for _, child in frame:GetChildren() do
		seen[child] = true
	end
	return seen
end

local function ownModifiers(frame: Frame, before: { [Instance]: boolean })
	frame:SetAttribute("QuadroStyled", true)
	for _, child in frame:GetChildren() do
		if MODIFIERS[child.ClassName] and not before[child] then
			child:SetAttribute("QuadroOwned", true)
		end
	end
end

local function styleNode(state: State, node: Spec.Node, gui: GuiObject, pbox: ParentBox, index: number, isRootNode: boolean, context: Context, wrapper: Frame?, flow: Frame?, slot: Frame?)
	clearOwned(gui)
	if slot then
		clearOwned(slot)
	end
	local before = snapshotChildren(gui)
	local slotBefore = if slot then snapshotChildren(slot) else nil
	local w, h = node.box[3], node.box[4]
	local opacity = node.opacity
	local sx, sy = Units.size(w, h, pbox.innerW, pbox.innerH)
	local sizing = node.sizing
	if pbox.hasLayout and sizing then
		if pbox.dir == "H" and sizing.v == "fill" then
			sy = 1
		elseif pbox.dir == "V" and sizing.h == "fill" then
			sx = 1
		end
	end
	local ax, ay, reason = Units.anchor(node.constraints, pbox.isRoot)
	local placed: GuiObject = wrapper or slot or gui
	gui.Name = node.name
	placed.AnchorPoint = Vector2.new(ax, ay)
	placed:SetAttribute("AnchorReason", reason)
	placed.Size = UDim2.fromScale(sx, sy)
	if not pbox.hasLayout then
		local px, py = Units.position(node.box[1], node.box[2], w, h, pbox.pad, pbox.innerW, pbox.innerH, ax, ay)
		placed.Position = UDim2.fromScale(px, py)
	end
	local turned: GuiObject = wrapper or gui
	turned.Rotation = node.rotation
	gui.Visible = node.visible
	placed.LayoutOrder = index
	if wrapper then
		fitWrapper(wrapper, gui, node.name, w, h)
	elseif slot then
		fitSlot(slot, gui)
	end
	gui.BorderSizePixel = 0
	gui.ClipsDescendants = node.clip

	local warningsBefore = #state.warnings
	local fill, extraFills = chooseFill(node, state.doc.tokens.gradients)
	local tiled = fill ~= nil and fill.kind == "image" and fill.tile ~= nil
	if extraFills > 0 then
		table.insert(state.warnings, node.name .. ": " .. extraFills .. " pinturas extras ignoradas")
	end
	if (gui:IsA("ImageLabel") or gui:IsA("ImageButton")) and fill and fill.kind == "image" then
		gui.BackgroundTransparency = 1
		applyImage(gui, fill, node, opacity, state)
	elseif node.kind == "text" then
		gui.BackgroundTransparency = 1
	else
		if fill and fill.kind == "image" then
			table.insert(state.warnings, node.name .. ": image fill needs an image node")
			fill = nil
		end
		Paint.background(gui, fill, opacity, state.doc.tokens.gradients, state.library, state.warnings, node.tint)
	end
	if gui:IsA("TextButton") or gui:IsA("ImageButton") then
		gui.AutoButtonColor = false
	end

	if node.radius then
		Paint.corner(gui, node.radius, w, h, state.warnings)
	end
	if node.stroke then
		Paint.stroke(gui, node.stroke, w, h, opacity, false)
	end
	Paint.effects(gui, node.effects, w, h, opacity, state.warnings)
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		applyText(gui, node, opacity, state)
	end
	tagWarnings(state, warningsBefore, node.id)
	if gui:IsA("ScrollingFrame") then
		configureScroll(gui, node, context, pbox, wrapper ~= nil)
	end

	local box = context.childBox
	if context.layout or context.grid then
		local first: Spec.Node? = nil
		for _, child in context.children do
			if first == nil and not child.absolute then
				first = child
			end
		end
		local host: GuiObject = flow or gui
		if flow then
			clearOwned(flow)
			flow.Name = "QuadroFlow"
			flow.AnchorPoint = Vector2.new(0.5, 0.5)
			flow.Position = UDim2.fromScale(0.5, 0.5)
			flow.Size = UDim2.fromScale(1, 1)
			flow.BackgroundTransparency = 1
			flow.BorderSizePixel = 0
		end
		local flowBefore = if flow then snapshotChildren(flow) else nil
		applyLayout(host, context.layout, context.grid, box.innerW, box.innerH, first)
		applyPadding(host, context.pad, context.spanW, context.spanH)
		if flow and flowBefore then
			ownModifiers(flow, flowBefore)
		end
	end
	if pbox.hasLayout and node.sizing then
		applySizing(slot or gui, node.sizing, pbox.dir)
	end
	if slot and slotBefore then
		ownModifiers(slot, slotBefore)
	end

	local topPanel = pbox.isRoot and CONTAINERS[node.kind] == true
	local reducedRoot = isRootNode and not Units.fullScreen(w, h)
	if (node.kind == "button" or (gui:IsA("ImageLabel") and not tiled) or topPanel or reducedRoot) and not gui:IsA("ScrollingFrame") then
		addAspect(gui, w, h)
	end
	for _, child in gui:GetChildren() do
		if MODIFIERS[child.ClassName] and not before[child] then
			child:SetAttribute("QuadroOwned", true)
			for _, nested in child:GetDescendants() do
				nested:SetAttribute("QuadroOwned", true)
			end
		end
	end
	gui:SetAttribute("QuadroStyled", true)
end

local function orphanFolder(screenName: string): Instance
	local storage = game:GetService("ServerStorage")
	local root = storage:FindFirstChild("_QuadroOrphans")
	if root == nil then
		root = Instance.new("Folder")
		root.Name = "_QuadroOrphans"
		root.Parent = storage
	end
	local folder = root:FindFirstChild(screenName)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = screenName
		folder.Parent = root
	end
	return folder
end

local function moveToOrphans(instance: Instance, screenName: string)
	local folder = orphanFolder(screenName)
	local base = instance.Name
	local counter = 1
	while folder:FindFirstChild(instance.Name) do
		counter += 1
		instance.Name = base .. " (" .. counter .. ")"
	end
	instance.Parent = folder
end

local function wrapperOf(instance: Instance?, attribute: string): Frame?
	local parent = if instance then instance.Parent else nil
	if parent ~= nil and parent:IsA("Frame") and parent:GetAttribute(attribute) == true then
		return parent
	end
	return nil
end

local function flowOf(gui: Instance): Frame?
	for _, child in gui:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute("QuadroFlowWrap") == true then
			return child
		end
	end
	return nil
end

local function dropWrapper(wrapper: Frame, screenName: string, warnings: { string })
	for _, child in wrapper:GetChildren() do
		if child:GetAttribute("QuadroOwned") ~= true then
			moveToOrphans(wrapper, screenName)
			table.insert(warnings, wrapper.Name .. " moved to _QuadroOrphans (contains your instances)")
			return
		end
	end
	wrapper.Parent = nil
end

local function isLocked(instance: Instance): boolean
	return instance:GetAttribute("QuadroLock") == true
end

local function lockedWithin(instance: Instance): boolean
	if isLocked(instance) then
		return true
	end
	for _, descendant in instance:GetDescendants() do
		if isLocked(descendant) then
			return true
		end
	end
	return false
end

local function findRootFrame(screen: Instance): Instance?
	for _, child in screen:GetChildren() do
		if child:GetAttribute("QuadroRoot") == true then
			return child
		end
	end
	return nil
end

local function setOwnedZ(object: GuiObject, z: number?)
	local owned = object:GetAttribute("QuadroZ")
	if owned ~= nil and object.ZIndex ~= owned then
		return
	end
	if owned == nil and object.ZIndex ~= 1 then
		return
	end
	object.ZIndex = z or 1
	object:SetAttribute("QuadroZ", z)
end

local function syncNode(state: State, node: Spec.Node, parent: Instance, pbox: ParentBox, index: number, isRootNode: boolean, z: number?)
	if node.kind == "ignore" or (not state.building and not isRootNode and Spec.isSource(node)) then
		return
	end
	local live: Instance? = if isRootNode then findRootFrame(parent) else state.index[node.id]
	local wanted = className(node, state.doc.tokens.gradients)
	local component = node.component
	local fromTemplate = false
	if live == nil and not isRootNode and component and not component.main then
		local template = state.templates[component.name]
		if template then
			live = Templates.instantiate(template, node, state.index)
			wanted = (live :: Instance).ClassName
			fromTemplate = true
		end
	end
	if live ~= nil and live:IsA("GuiObject") and live.ClassName ~= wanted and isLocked(live) then
		table.insert(state.warnings, live.Name .. ": class change skipped (locked)")
		tagWarnings(state, #state.warnings - 1, node.id)
		wanted = live.ClassName
	end
	local wrapper = wrapperOf(live, "QuadroScrollWrap")
	local slot = wrapperOf(live, "QuadroSlot")
	local gui: GuiObject
	local rebuilt = false
	if live ~= nil and live:IsA("GuiObject") and live.ClassName == wanted then
		gui = live
		if fromTemplate then
			state.created += 1
		else
			state.updated += 1
		end
	else
		gui = Instance.new(wanted) :: GuiObject
		rebuilt = true
		if not isRootNode then
			state.index[node.id] = gui
		end
		if live then
			for _, child in live:GetChildren() do
				if not MODIFIERS[child.ClassName] or isUserModifier(child) or Validate.isEffectPiece(child) then
					child.Parent = gui
				end
			end
			for key, value in live:GetAttributes() do
				gui:SetAttribute(key, value)
			end
			gui:SetAttribute("QuadroZ", nil)
			live.Parent = nil
			state.updated += 1
		else
			state.created += 1
			if state.created % BATCH == 0 then
				task.wait()
			end
			if isRootNode then
				gui:SetAttribute("QuadroRoot", true)
			else
				gui:SetAttribute("FigmaId", node.id)
			end
		end
	end
	local context = describe(node, isRootNode)
	local flow = flowOf(gui)
	local staleFlow: Frame? = nil
	if rebuilt or not isLocked(gui) then
		local wrap = gui:IsA("ScrollingFrame") and pbox.isRoot and CONTAINERS[node.kind] == true
		if wrap and wrapper == nil then
			local created = Instance.new("Frame")
			created.BackgroundTransparency = 1
			created.BorderSizePixel = 0
			created:SetAttribute("QuadroOwned", true)
			created:SetAttribute("QuadroScrollWrap", true)
			wrapper = created
		elseif not wrap and wrapper ~= nil then
			gui.Parent = parent
			dropWrapper(wrapper, state.doc.root.name, state.warnings)
			wrapper = nil
		end
		local slotted = node.kind == "button" and pbox.hasLayout and not pbox.grid
		if slotted and slot == nil then
			local created = Instance.new("Frame")
			created:SetAttribute("QuadroOwned", true)
			created:SetAttribute("QuadroSlot", true)
			slot = created
		elseif not slotted and slot ~= nil then
			gui.Parent = parent
			dropWrapper(slot, state.doc.root.name, state.warnings)
			slot = nil
		end
		if context.free and flow == nil then
			local created = Instance.new("Frame")
			created:SetAttribute("QuadroOwned", true)
			created:SetAttribute("QuadroFlowWrap", true)
			created.Parent = gui
			flow = created
		elseif not context.free and flow ~= nil then
			staleFlow = flow
			flow = nil
		end
		styleNode(state, node, gui, pbox, index, isRootNode, context, wrapper, flow, slot)
	end
	local firstFlow: number? = nil
	for childIndex, child in context.children do
		if firstFlow == nil and not child.absolute then
			firstFlow = childIndex
		end
	end
	if flow ~= nil and (rebuilt or not isLocked(gui)) then
		setOwnedZ(flow, firstFlow)
	end
	for childIndex, child in context.children do
		if flow ~= nil and child.absolute then
			syncNode(state, child, gui, context.freeBox, childIndex, false, childIndex)
		else
			syncNode(state, child, flow or gui, context.childBox, childIndex, false)
		end
	end
	if staleFlow then
		for _, child in staleFlow:GetChildren() do
			if child:GetAttribute("FigmaId") ~= nil or child:GetAttribute("QuadroSlot") == true then
				child.Parent = gui
			end
		end
		dropWrapper(staleFlow, state.doc.root.name, state.warnings)
	end
	if component and not component.main then
		local stale = gui:FindFirstChild("QuadroStates")
		if stale then
			stale.Parent = nil
		end
		gui:SetAttribute("QuadroTemplate", component.name)
	end
	local shell = wrapper or slot
	if shell and shell.Parent ~= parent then
		shell.Parent = parent
	end
	if not isRootNode and (rebuilt or not isLocked(gui)) then
		setOwnedZ(shell or gui, z)
	end
	local holder: Instance = shell or parent
	if gui.Parent ~= holder then
		gui.Parent = holder
	end
end

local function screenBox(root: Spec.Node): (number, number)
	local w, h = root.box[3], root.box[4]
	if Units.fullScreen(w, h) then
		return w, h
	end
	return REFERENCE_W, REFERENCE_H
end

local function topFrame(root: Spec.Node): Spec.Node
	local clone = table.clone(root)
	local w, h = root.box[3], root.box[4]
	local screenW, screenH = screenBox(root)
	if Units.fullScreen(w, h) then
		local effects: { Spec.Effect } = {}
		for _, effect in root.effects do
			if effect.kind ~= "dropShadow" then
				table.insert(effects, effect)
			end
		end
		clone.effects = effects
	end
	clone.constraints = nil
	clone.sizing = nil
	clone.box = { (screenW - w) / 2, (screenH - h) / 2, w, h }
	return clone
end

local function isUserInstance(instance: Instance): boolean
	if MODIFIERS[instance.ClassName] then
		return isUserModifier(instance)
	end
	return instance:GetAttribute("FigmaId") == nil
		and instance:GetAttribute("QuadroRoot") ~= true
		and instance:GetAttribute("QuadroScrollWrap") ~= true
		and instance:GetAttribute("QuadroFlowWrap") ~= true
		and instance:GetAttribute("QuadroSlot") ~= true
		and instance.Name ~= "QuadroStates"
		and (instance.Parent == nil or instance.Parent.Name ~= "QuadroStates")
end

local function indexScreen(screen: ScreenGui): (Plan.Existing, { [string]: Instance }, { [Instance]: boolean })
	local existing: Plan.Existing = {}
	local instances: { [string]: Instance } = {}
	local duplicates: { [Instance]: boolean } = {}
	local function markForeign(ownerId: string?)
		local ancestor = ownerId
		while ancestor ~= nil do
			existing[ancestor].foreign = true
			ancestor = existing[ancestor].parentId
		end
	end
	local function visit(instance: Instance, ownerId: string?)
		for _, child in instance:GetChildren() do
			if MODIFIERS[child.ClassName] then
				if isUserModifier(child) then
					markForeign(ownerId)
				end
				continue
			end
			local id = child:GetAttribute("FigmaId")
			if type(id) == "string" then
				if instances[id] ~= nil then
					duplicates[child] = true
					markForeign(ownerId)
					continue
				end
				instances[id] = child
				existing[id] = { name = child.Name, parentId = ownerId, foreign = false }
				visit(child, id)
				continue
			end
			if isUserInstance(child) then
				markForeign(ownerId)
			end
			visit(child, ownerId)
		end
	end
	local rootId = screen:GetAttribute("FigmaId")
	if type(rootId) == "string" then
		instances[rootId] = screen
		existing[rootId] = { name = screen.Name, parentId = nil, foreign = false }
	end
	visit(screen, if type(rootId) == "string" then rootId else nil)
	return existing, instances, duplicates
end

local function underDuplicate(instance: Instance, screen: Instance, duplicates: { [Instance]: boolean }): boolean
	local parent = instance.Parent
	while parent ~= nil and parent ~= screen do
		if duplicates[parent] then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function countKept(screen: ScreenGui, duplicates: { [Instance]: boolean }): number
	local kept = 0
	for _, descendant in screen:GetDescendants() do
		local user = isUserInstance(descendant) and not MODIFIERS[(descendant.Parent :: Instance).ClassName] and not underDuplicate(descendant, screen, duplicates)
		if duplicates[descendant] or user then
			kept += 1
		end
	end
	return kept
end

local TEMPLATE_BOX: ParentBox = { innerW = REFERENCE_W, innerH = REFERENCE_H, pad = ZERO_PAD, hasLayout = false, dir = "", isRoot = false }

local function claimTemplate(folder: Instance, group: Templates.Group, warnings: { string }): (Instance?, boolean)
	local byKey: Instance? = nil
	local byName: Instance? = nil
	for _, child in folder:GetChildren() do
		if child:GetAttribute("FigmaComponentKey") == group.key then
			byKey = child
		elseif child.Name == group.name then
			byName = child
		end
	end
	if byKey then
		if byName and byName:GetAttribute("FigmaComponentKey") ~= nil then
			table.insert(warnings, group.name .. ": another template with this name and a different key exists, skipped")
			return nil, false
		end
		return byKey, true
	end
	if byName then
		local key = byName:GetAttribute("FigmaComponentKey")
		if key ~= nil and key ~= group.key then
			table.insert(warnings, group.name .. ": another template with this name and a different key exists, skipped")
			return nil, false
		end
		return byName, true
	end
	return nil, true
end

local function buildTemplates(state: State): boolean
	local groups = Templates.collect(state.doc.root, state.warnings)
	if #groups == 0 then
		return false
	end
	local folder = Templates.folder()
	local hasStates = false
	state.building = true
	for _, group in groups do
		local existing, allowed = claimTemplate(folder, group, state.warnings)
		if not allowed then
			continue
		end
		if existing and existing:GetAttribute("FigmaId") ~= group.normal.id then
			moveToOrphans(existing, state.doc.root.name)
		end
		for _, descendant in folder:GetDescendants() do
			local id = descendant:GetAttribute("FigmaId")
			if type(id) == "string" then
				state.index[id] = descendant
			end
		end
		syncNode(state, group.normal, folder, TEMPLATE_BOX, 1, false)
		local template = state.index[group.normal.id]
		if template == nil then
			for _, child in folder:GetChildren() do
				if child:GetAttribute("FigmaId") == group.normal.id then
					template = child
				end
			end
		end
		if template then
			template.Name = group.name
			template:SetAttribute("FigmaComponentKey", group.key)
			state.templates[group.name] = template
			local values: { [string]: { [string]: any } } = {}
			local stateNames: { string } = {}
			for stateName in group.states do
				table.insert(stateNames, stateName)
			end
			table.sort(stateNames)
			for _, stateName in stateNames do
				local scratch = table.clone(state)
				scratch.index = {}
				scratch.warnings = {}
				scratch.warningTargets = {}
				scratch.pending = 0
				local temp = Instance.new("Folder")
				syncNode(scratch, group.states[stateName], temp, TEMPLATE_BOX, 1, false)
				local built = temp:GetChildren()[1]
				local label = group.name .. "/" .. stateName
				values[stateName] = if built then Templates.diff(template, built, scratch.warnings, label) else {}
				local known: { [string]: boolean } = {}
				for _, warning in state.warnings do
					known[warning] = true
				end
				for _, warning in scratch.warnings do
					if not known[warning] then
						known[warning] = true
						table.insert(state.warnings, warning)
					end
				end
			end
			Templates.writeStates(template, values, state.warnings)
			hasStates = hasStates or next(values) ~= nil
		end
	end
	state.building = false
	return hasStates
end

function Build.run(doc: Spec.Doc, opts: Options): Summary
	local summary: Summary = {
		ok = false,
		created = 0,
		updated = 0,
		kept = 0,
		removed = 0,
		orphaned = 0,
		pendingImages = 0,
		warnings = table.clone(doc.warnings),
		issues = {},
		warningTargets = {},
		issueTargets = {},
		screenGui = nil,
	}
	local state: State = {
		doc = doc,
		library = opts.library,
		warnings = summary.warnings,
		warningTargets = summary.warningTargets,
		created = 0,
		updated = 0,
		pending = 0,
		index = {},
		templates = {},
		building = false,
		textScale = REFERENCE_W / (screenBox(doc.root)),
	}
	local ok, cause = History.record("Import", function()
		local root = doc.root
		local starterGui = game:GetService("StarterGui")
		local live: ScreenGui? = nil
		for _, existing in starterGui:GetChildren() do
			if live == nil and existing:IsA("ScreenGui") and existing:GetAttribute("FigmaId") == root.id then
				live = existing
			end
		end
		for _, existing in starterGui:GetChildren() do
			if existing:IsA("ScreenGui") and existing ~= live and existing.Name == root.name then
				moveToOrphans(existing, root.name)
				summary.orphaned += 1
				table.insert(summary.warnings, existing.Name .. " is not from this import, moved to _QuadroOrphans")
			end
		end
		local target: ScreenGui = if live then live else Instance.new("ScreenGui")
		local plan: Plan.Result? = nil
		local duplicates: { [Instance]: boolean } = {}
		if live then
			local existing, instances, found = indexScreen(live)
			state.index = instances
			duplicates = found
			plan = Plan.diff(doc, existing)
			if next(found) ~= nil then
				table.insert(summary.warnings, "duplicate FigmaId in the live tree, duplicates left alone")
			end
		end
		if live == nil or not isLocked(target) then
			target.Name = root.name
			target.ResetOnSpawn = false
			target.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			target.ScreenInsets = if Units.fullScreen(root.box[3], root.box[4]) then Enum.ScreenInsets.DeviceSafeInsets else Enum.ScreenInsets.CoreUISafeInsets
		end
		target:SetAttribute("FigmaId", root.id)
		local screenW, screenH = screenBox(root)
		local reference: ParentBox = { innerW = screenW, innerH = screenH, pad = ZERO_PAD, hasLayout = false, dir = "", isRoot = false }
		local hasStates = buildTemplates(state)
		summary.runtime = Templates.syncRuntime(hasStates)
		syncNode(state, topFrame(root), target, reference, 1, true)
		if plan then
			for _, rename in plan.renamed do
				local instance = state.index[rename.id]
				if instance and not isLocked(instance) then
					table.insert(summary.warnings, rename.from .. " renamed to " .. rename.to)
					summary.warningTargets[tostring(#summary.warnings)] = rename.id
				end
			end
			for _, id in plan.orphan do
				local instance = state.index[id]
				if instance and instance:IsDescendantOf(target) then
					if lockedWithin(instance) then
						table.insert(summary.warnings, instance.Name .. ": travado, mantido apesar de removido no Figma")
						summary.warningTargets[tostring(#summary.warnings)] = id
					else
						local wrapper = wrapperOf(instance, "QuadroScrollWrap") or wrapperOf(instance, "QuadroSlot")
						moveToOrphans(instance, root.name)
						if wrapper then
							dropWrapper(wrapper, root.name, summary.warnings)
						end
						summary.orphaned += 1
						table.insert(summary.warnings, instance.Name .. " moved to _QuadroOrphans (contains your instances)")
					end
				end
			end
			for _, id in plan.remove do
				local instance = state.index[id]
				if instance and instance:IsDescendantOf(target) then
					if lockedWithin(instance) then
						table.insert(summary.warnings, instance.Name .. ": travado, mantido apesar de removido no Figma")
						summary.warningTargets[tostring(#summary.warnings)] = id
					else
						local wrapper = wrapperOf(instance, "QuadroScrollWrap") or wrapperOf(instance, "QuadroSlot")
						instance.Parent = nil
						if wrapper then
							dropWrapper(wrapper, root.name, summary.warnings)
						end
						summary.removed += 1
					end
				end
			end
		end
		if live == nil then
			target.Parent = starterGui
		end
		summary.kept = countKept(target, duplicates)
		summary.screenGui = target:GetFullName()
		summary.rootId = root.id
		local issues, issueTargets = Validate.run(target)
		for index, issue in issues do
			table.insert(summary.issues, issue)
			summary.issueTargets[tostring(#summary.issues)] = issueTargets[tostring(index)]
		end
		return state.created
	end, { nested = opts.nested })
	if not ok then
		summary.busy = cause == History.BUSY
		summary.crashed = not summary.busy
		table.insert(summary.issues, tostring(cause))
		return summary
	end
	summary.ok = true
	summary.created = state.created
	summary.updated = state.updated
	summary.pendingImages = state.pending
	return summary
end

return Build
