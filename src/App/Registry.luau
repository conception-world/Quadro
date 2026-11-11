--!strict
export type Kind = "info" | "success" | "warning" | "error"
export type Context = {
	store: any,
	plugin: Plugin?,
	notify: (text: string, kind: Kind) -> (),
	t: (key: string, ...any) -> string,
	fromHook: boolean?,
}
export type Result = { ok: boolean, count: number, message: string?, args: { any }? }
type Command = { id: string, labelKey: string, run: (ctx: Context, ...any) -> Result }

local Registry = {}
Registry.__index = Registry

export type Registry = typeof(setmetatable(
	{} :: { _order: { Command }, _byId: { [string]: Command }, _holds: number, onHold: (() -> ())? },
	Registry
))

function Registry.new(): Registry
	return setmetatable({ _order = {}, _byId = {}, _holds = 0, onHold = nil }, Registry)
end

function Registry.define(self: Registry, id: string, labelKey: string, run: (ctx: Context, ...any) -> Result)
	local command = { id = id, labelKey = labelKey, run = run }
	local existing = self._byId[id]
	if existing then
		self._order[table.find(self._order, existing) :: number] = command
	else
		table.insert(self._order, command)
	end
	self._byId[id] = command
end

function Registry.run(self: Registry, id: string, ctx: Context, ...: any): Result
	local command = self._byId[id]
	if not command then
		return { ok = false, count = 0, message = "error_unknown_command" }
	end
	self._holds += 1
	local hold = self.onHold
	if hold then
		local held, failure = pcall(hold)
		if not held then
			warn("[Quadro] hold: " .. tostring(failure))
		end
	end
	local ok, result = pcall(command.run, ctx, ...)
	self._holds -= 1
	if not ok then
		warn(string.format("[Quadro] command %s failed: %s", id, tostring(result)))
		return { ok = false, count = 0, message = "error_command_failed" }
	end
	if type(result) ~= "table" or type((result :: any).ok) ~= "boolean" then
		warn(string.format("[Quadro] command %s returned an invalid result", id))
		return { ok = false, count = 0, message = "error_command_failed" }
	end
	return result
end

function Registry.held(self: Registry): boolean
	return self._holds > 0
end

function Registry.list(self: Registry): { { id: string, labelKey: string } }
	local out = {}
	for _, command in self._order do
		table.insert(out, { id = command.id, labelKey = command.labelKey })
	end
	return out
end

return Registry
