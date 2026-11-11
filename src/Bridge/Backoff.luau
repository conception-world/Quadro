--!strict
local Backoff = {}

export type State = { [string]: { failures: number, nextAt: number } }

local BASE_SECONDS = 2
local CAP_SECONDS = 60

function Backoff.delay(failures: number): number
	if failures < 1 then
		return 0
	end
	return math.min(BASE_SECONDS * 2 ^ (failures - 1), CAP_SECONDS)
end

function Backoff.fail(state: State, hash: string, now: number)
	local entry = state[hash]
	local failures = (if entry then entry.failures else 0) + 1
	state[hash] = { failures = failures, nextAt = now + Backoff.delay(failures) }
end

function Backoff.clear(state: State, hash: string)
	state[hash] = nil
end

function Backoff.due(state: State, hash: string, now: number): boolean
	local entry = state[hash]
	return entry == nil or now >= entry.nextAt
end

function Backoff.reset(state: State)
	table.clear(state)
end

return Backoff
