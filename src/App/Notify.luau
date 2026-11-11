--!strict
local MAX_TOASTS = 3

local Notify = {}

local nextId = 0

function Notify.push(store: any, text: string, kind: string, now: number)
	nextId += 1
	local toasts = table.clone(store:get().toasts)
	table.insert(toasts, { id = nextId, text = text, kind = kind, at = now })
	while #toasts > MAX_TOASTS do
		table.remove(toasts, 1)
	end
	store:set({ toasts = toasts })
end

function Notify.expire(store: any, now: number, ttl: number)
	local current = store:get().toasts
	local kept = {}
	for _, toast in current do
		if now - toast.at < ttl then
			table.insert(kept, toast)
		end
	end
	if #kept ~= #current then
		store:set({ toasts = kept })
	end
end

return Notify
