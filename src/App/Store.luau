--!strict
export type State = { [string]: any }
export type Listener = (state: State) -> ()

type StoreData = {
	_state: State,
	_listeners: { Listener },
}

local Store = {}
Store.__index = Store

export type Store = typeof(setmetatable({} :: StoreData, Store))

function Store.new(initial: State): Store
	local data: StoreData = {
		_state = table.freeze(table.clone(initial)),
		_listeners = {},
	}
	return setmetatable(data, Store)
end

function Store.get(self: Store): State
	return self._state
end

function Store.set(self: Store, patch: State)
	local nextState = table.clone(self._state)
	local changed = false
	for key, value in patch do
		if nextState[key] ~= value then
			nextState[key] = value
			changed = true
		end
	end
	if not changed then
		return
	end
	self._state = table.freeze(nextState)
	for _, listener in table.clone(self._listeners) do
		listener(self._state)
	end
end

function Store.subscribe(self: Store, listener: Listener): () -> ()
	table.insert(self._listeners, listener)
	return function()
		local index = table.find(self._listeners, listener)
		if index then
			table.remove(self._listeners, index)
		end
	end
end

return Store
