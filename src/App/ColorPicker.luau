--!strict
local ColorMath = require(script.Parent.Parent.ColorMath)
local Stops = require(script.Parent.Parent.Gradients.Stops)

export type Kind = "wheel" | "value"
export type State = {
	open: boolean,
	owner: string,
	original: string,
	h: number,
	s: number,
	v: number,
	dragging: Kind?,
	recent: { string },
}
export type Handlers = { commit: (hex: string) -> () }
export type Api = {
	toggle: (owner: string, hex: string) -> (),
	setHex: (text: string) -> (),
	dragBegin: (kind: Kind, area: GuiObject) -> (),
	dragTo: (x: number, y: number) -> (),
	dragEnd: () -> (),
	commit: (handlers: Handlers?) -> (),
	cancel: () -> (),
	release: (owner: string, force: boolean?) -> (),
	bind: (owner: string, handlers: Handlers) -> () -> (),
}
export type Handle = { state: State, api: Api }

local ColorPicker = {}

local RECENT_MAX = 8

local liveArea: GuiObject? = nil
local bindings: { { owner: string, handlers: Handlers } } = {}

function ColorPicker.initial(): State
	return { open = false, owner = "", original = "ffffff", h = 0, s = 0, v = 1, dragging = nil, recent = {} }
end

function ColorPicker.hex(state: State): string
	return ColorMath.toHex(state.h, state.s, state.v)
end

function ColorPicker.isOpen(state: State?, owner: string): boolean
	return state ~= nil and state.open and state.owner == owner
end

function ColorPicker.shown(state: State?, owner: string, fallback: string): string
	if state and ColorPicker.isOpen(state, owner) then
		return ColorPicker.hex(state)
	end
	return fallback
end

local function current(store: any): State
	return store:get().colorPicker or ColorPicker.initial()
end

local function put(store: any, patch: { [string]: any })
	local nextState = table.clone(current(store)) :: any
	for key, value in patch do
		nextState[key] = value
	end
	if patch.dragging == false then
		nextState.dragging = nil
	end
	store:set({ colorPicker = nextState })
end

local function bound(owner: string): Handlers?
	for index = #bindings, 1, -1 do
		if bindings[index].owner == owner then
			return bindings[index].handlers
		end
	end
	return nil
end

function ColorPicker.bind(store: any): Api
	local api = {} :: Api

	function api.toggle(owner: string, hex: string)
		local state = current(store)
		if state.open and state.owner == owner then
			api.commit()
			return
		end
		local clean = Stops.parseHex(hex) or state.original
		local h, s, v = ColorMath.fromHex(clean)
		liveArea = nil
		put(store, { open = true, owner = owner, original = clean, h = h, s = s, v = v, dragging = false })
	end

	function api.setHex(text: string)
		local state = current(store)
		local clean = Stops.parseHex(text)
		if not state.open or clean == nil then
			return
		end
		local h, s, v = ColorMath.fromHex(clean)
		if v == 0 then
			h, s = state.h, state.s
		elseif s == 0 then
			h = state.h
		end
		put(store, { h = h, s = s, v = v })
	end

	function api.dragBegin(kind: Kind, area: GuiObject)
		if not current(store).open then
			return
		end
		liveArea = area
		put(store, { dragging = kind })
	end

	function api.dragTo(x: number, y: number)
		local state = current(store)
		local area = liveArea
		if state.dragging == nil or area == nil or area.Parent == nil or area.AbsoluteSize.X <= 0 or area.AbsoluteSize.Y <= 0 then
			return
		end
		local origin, size = area.AbsolutePosition, area.AbsoluteSize
		if state.dragging == "wheel" then
			local h, s = ColorMath.polar((x - origin.X) / (size.X / 2) - 1, (y - origin.Y) / (size.Y / 2) - 1)
			put(store, { h = h, s = s })
		else
			put(store, { v = math.clamp(1 - (y - origin.Y) / size.Y, 0, 1) })
		end
	end

	function api.dragEnd()
		liveArea = nil
		if current(store).dragging ~= nil then
			put(store, { dragging = false })
		end
	end

	function api.commit(handlers: Handlers?)
		local state = current(store)
		if not state.open then
			return
		end
		local hex = ColorPicker.hex(state)
		local target = handlers or bound(state.owner)
		local recent = { hex }
		for _, known in state.recent do
			if known ~= hex and #recent < RECENT_MAX then
				table.insert(recent, known)
			end
		end
		liveArea = nil
		put(store, { open = false, dragging = false, recent = recent })
		if target and hex ~= state.original then
			target.commit(hex)
		end
	end

	function api.cancel()
		liveArea = nil
		if current(store).open then
			put(store, { open = false, dragging = false })
		end
	end

	function api.release(owner: string, force: boolean?)
		local state = current(store)
		if state.open and state.owner == owner and (force == true or bound(owner) == nil) then
			api.cancel()
		end
	end

	function api.bind(owner: string, handlers: Handlers): () -> ()
		local entry = { owner = owner, handlers = handlers }
		table.insert(bindings, entry)
		return function()
			local index = table.find(bindings, entry)
			if index then
				table.remove(bindings, index)
			end
		end
	end

	return api
end

return ColorPicker
