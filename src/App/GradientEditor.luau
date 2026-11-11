--!strict
local SelectionService = game:GetService("Selection")
local Codec = require(script.Parent.Parent.Gradients.Codec)
local Library = require(script.Parent.Parent.Gradients.Library)
local Selection = require(script.Parent.Parent.Studio.Selection)
local Stops = require(script.Parent.Parent.Gradients.Stops)

export type Kind = Stops.Kind
export type Picked = { kind: Kind, index: number }
export type Drag = { kind: Kind, index: number, start: Codec.Data, railX: number?, railWidth: number? }
export type State = {
	target: string,
	status: string,
	data: Codec.Data?,
	gradientType: string,
	selected: Picked?,
	dragging: Drag?,
	recent: { string },
}
export type Env = { store: any, run: (id: string, ...any) -> any }
export type Api = {
	load: () -> (),
	setTarget: (target: string) -> (),
	create: () -> (),
	select: (kind: Kind, index: number) -> (),
	addStop: (kind: Kind) -> (),
	removeStop: () -> (),
	setColor: (hex: string) -> (),
	setValue: (value: number) -> (),
	setRotation: (rotation: number) -> (),
	setType: (name: string) -> (),
	dragBegin: (kind: Kind, index: number, rail: GuiObject?) -> (),
	dragMove: (t: number) -> (),
	dragTo: (x: number) -> (),
	dragEnd: () -> (),
	dragCancel: () -> (),
}

local GradientEditor = {}

GradientEditor.writes = 0

local liveRail: GuiObject? = nil

local RECENT_MAX = 8
local WATCHED = { "Color", "Transparency", "Rotation", "Type" }

function GradientEditor.initial(): State
	return { target = "fill", status = "none", data = nil, gradientType = "Linear", selected = nil, dragging = nil, recent = {} }
end

local function current(store: any): State
	return store:get().gradientEditor or GradientEditor.initial()
end

local function put(store: any, patch: { [string]: any })
	local nextState = table.clone(current(store)) :: any
	for key, value in patch do
		nextState[key] = value
	end
	for _, key in { "data", "selected", "dragging" } do
		if patch[key] == false then
			nextState[key] = nil
		end
	end
	GradientEditor.writes += 1
	store:set({ gradientEditor = nextState })
end

local function resolve(target: string): (GuiObject?, UIGradient?)
	local subject = Selection.firstGui()
	if subject == nil then
		return nil, nil
	end
	local host: Instance? = if target == "stroke" then subject:FindFirstChildOfClass("UIStroke") else subject
	return subject, if host then host:FindFirstChildOfClass("UIGradient") else nil
end

function GradientEditor.subject(target: string): UIGradient?
	local _, gradient = resolve(target)
	return gradient
end

function GradientEditor.load(store: any)
	local state = current(store)
	if state.dragging then
		return
	end
	local subject, gradient = resolve(state.target)
	if subject == nil or gradient == nil then
		put(store, { status = if subject then "missing" else "none", data = false, selected = false })
		return
	end
	local data = Library.restData(gradient)
	local gradientType = if Library.typeSupported then gradient.Type.Name else "Linear"
	local selected = state.selected
	if selected and selected.index > #Stops.list(data, selected.kind) then
		selected = nil
	end
	local previous = state.data
	if
		state.status == "ready"
		and previous ~= nil
		and previous.name == data.name
		and Codec.signature(previous) == Codec.signature(data)
		and state.gradientType == gradientType
		and state.selected == selected
	then
		return
	end
	put(store, {
		status = "ready",
		data = data,
		gradientType = gradientType,
		selected = selected or false,
	})
end

function GradientEditor.bind(env: Env): Api
	local store = env.store
	local api = {} :: Api

	local function edit(patch: { [string]: any })
		env.run("gradient.edit", current(store).target, patch)
		GradientEditor.load(store)
	end

	local function editList(data: Codec.Data, kind: Kind)
		edit({ [kind] = Stops.list(data, kind) })
	end

	function api.load()
		GradientEditor.load(store)
	end

	function api.setTarget(target: string)
		if target ~= "fill" and target ~= "stroke" then
			return
		end
		liveRail = nil
		put(store, { target = target, selected = false, dragging = false })
		GradientEditor.load(store)
	end

	function api.create()
		edit({})
	end

	function api.select(kind: Kind, index: number)
		local data = current(store).data
		if data and index >= 1 and index <= #Stops.list(data, kind) then
			put(store, { selected = { kind = kind, index = index } })
		end
	end

	function api.addStop(kind: Kind)
		local data = current(store).data
		if data == nil then
			return
		end
		local added, index = Stops.add(data, kind)
		if added and index then
			put(store, { selected = { kind = kind, index = index } })
			editList(added, kind)
		end
	end

	function api.removeStop()
		local state = current(store)
		local selected = state.selected
		if state.data == nil or selected == nil then
			return
		end
		local removed = Stops.remove(state.data, selected.kind, selected.index)
		if removed then
			put(store, { selected = false })
			editList(removed, selected.kind)
		end
	end

	function api.setColor(hex: string)
		local state = current(store)
		local selected = state.selected
		local clean = Stops.parseHex(hex)
		if state.data == nil or selected == nil or selected.kind ~= "color" or clean == nil then
			return
		end
		local recent = { clean }
		for _, known in state.recent do
			if known ~= clean and #recent < RECENT_MAX then
				table.insert(recent, known)
			end
		end
		put(store, { recent = recent })
		editList(Stops.set(state.data, "color", selected.index, clean), "color")
	end

	function api.setValue(value: number)
		local state = current(store)
		local selected = state.selected
		if state.data == nil or selected == nil or selected.kind ~= "transparency" or value ~= value then
			return
		end
		editList(Stops.set(state.data, "transparency", selected.index, value), "transparency")
	end

	function api.setRotation(rotation: number)
		if rotation == rotation then
			edit({ rotation = rotation })
		end
	end

	function api.setType(name: string)
		edit({ type = name })
	end

	function api.dragBegin(kind: Kind, index: number, rail: GuiObject?)
		local data = current(store).data
		if data == nil or index < 1 or index > #Stops.list(data, kind) then
			return
		end
		local picked = { kind = kind, index = index }
		if Stops.isEndpoint(data, kind, index) then
			put(store, { selected = picked })
			return
		end
		liveRail = rail
		put(store, {
			selected = picked,
			dragging = {
				kind = kind,
				index = index,
				start = data,
				railX = if rail then rail.AbsolutePosition.X else nil,
				railWidth = if rail then rail.AbsoluteSize.X else nil,
			},
		})
	end

	local function moveDraft(t: number, railX: number?, railWidth: number?)
		local state = current(store)
		local drag = state.dragging
		if drag == nil or state.data == nil or t ~= t then
			return
		end
		local moved, index = Stops.move(state.data, drag.kind, drag.index, t)
		put(store, {
			data = moved,
			selected = { kind = drag.kind, index = index },
			dragging = { kind = drag.kind, index = index, start = drag.start, railX = railX, railWidth = railWidth },
		})
	end

	function api.dragMove(t: number)
		local drag = current(store).dragging
		moveDraft(t, drag and drag.railX, drag and drag.railWidth)
	end

	function api.dragTo(x: number)
		local drag = current(store).dragging
		if drag == nil then
			return
		end
		local railX, railWidth = drag.railX, drag.railWidth
		local rail = liveRail
		if rail and rail.Parent and rail.AbsoluteSize.X > 0 then
			railX, railWidth = rail.AbsolutePosition.X, rail.AbsoluteSize.X
		end
		if railX == nil or railWidth == nil or railWidth <= 0 then
			return
		end
		moveDraft((x - railX) / railWidth, railX, railWidth)
	end

	function api.dragEnd()
		local state = current(store)
		local drag = state.dragging
		if drag == nil then
			return
		end
		liveRail = nil
		put(store, { dragging = false })
		local data = state.data
		if data and Codec.signature(data) ~= Codec.signature(drag.start) then
			editList(data, drag.kind)
		else
			GradientEditor.load(store)
		end
	end

	function api.dragCancel()
		liveRail = nil
		if current(store).dragging ~= nil then
			put(store, { dragging = false })
			GradientEditor.load(store)
		end
	end

	return api
end

function GradientEditor.watch(store: any, active: (state: { [string]: any }) -> boolean): () -> ()
	local connections: { RBXScriptConnection } = {}
	local pending = false
	local alive = true
	local stale = false

	local function clear()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local schedule: () -> ()

	local function refresh()
		pending = false
		if not alive then
			return
		end
		clear()
		GradientEditor.load(store)
		local subject = Selection.firstGui()
		if subject == nil then
			return
		end
		table.insert(connections, subject.DescendantAdded:Connect(schedule))
		table.insert(connections, subject.DescendantRemoving:Connect(schedule))
		local stroke = subject:FindFirstChildOfClass("UIStroke")
		for _, host in { subject, stroke } do
			local gradient = host and host:FindFirstChildOfClass("UIGradient")
			if gradient then
				local holder = Library.baseHolder(gradient)
				for _, property in WATCHED do
					local animated = holder ~= nil and property == "Rotation"
					if not animated and (property ~= "Type" or Library.typeSupported) then
						table.insert(connections, gradient:GetPropertyChangedSignal(property):Connect(schedule))
					end
				end
				if holder then
					table.insert(connections, holder:GetAttributeChangedSignal(Library.BASE_ROTATION):Connect(schedule))
					table.insert(connections, holder:GetAttributeChangedSignal(Library.BASE_OFFSET):Connect(schedule))
				end
			end
		end
	end

	schedule = function()
		if not active(store:get()) then
			stale = true
			return
		end
		if not pending then
			pending = true
			task.defer(refresh)
		end
	end

	local selectionConnection = SelectionService.SelectionChanged:Connect(schedule)
	local unsubscribe = store:subscribe(function(state: { [string]: any })
		if stale and active(state) then
			stale = false
			schedule()
		end
	end)
	if active(store:get()) then
		refresh()
	else
		stale = true
	end
	return function()
		alive = false
		selectionConnection:Disconnect()
		unsubscribe()
		clear()
	end
end

return GradientEditor
