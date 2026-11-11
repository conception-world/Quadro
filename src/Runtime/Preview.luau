--!strict
local Installer = require("./Installer")

local Preview = {}

export type Controller = { suspend: () -> (), unmount: () -> () }

local STEP = 1 / 60
local SCAN = 0.5
local TRANSIENT = "QuadroTransient"
local PROPERTIES: { [string]: { string } } = {
	UIGradient = { "Offset", "Rotation" },
	UIStroke = { "Thickness" },
	UIScale = { "Scale" },
}

type Snapshot = {
	values: { [Instance]: { [string]: any } },
	last: { [Instance]: { [string]: any } },
	seen: { [Instance]: { [string]: boolean } },
}

local function ownOrChild(instance: Instance, className: string): Instance?
	if instance:IsA(className) then
		return instance
	end
	return instance:FindFirstChildOfClass(className)
end

local function remember(snapshot: Snapshot, target: Instance)
	local names = PROPERTIES[target.ClassName]
	if names == nil or snapshot.values[target] ~= nil then
		return
	end
	local values = {}
	for _, name in names do
		values[name] = (target :: any)[name]
	end
	snapshot.values[target] = values
end

local function record(snapshot: Snapshot, tag: string, instance: Instance, fromBase: boolean)
	local tags = snapshot.seen[instance] or {}
	if tags[tag] then
		return
	end
	tags[tag] = true
	snapshot.seen[instance] = tags
	remember(snapshot, instance)
	for _, child in instance:GetChildren() do
		remember(snapshot, child)
	end
	if not fromBase then
		return
	end
	if tag == "QuadroAnimatedGradient" then
		local gradient = ownOrChild(instance, "UIGradient")
		local values = if gradient then snapshot.values[gradient] else nil
		if values then
			values.Offset = instance:GetAttribute("QuadroGradientBaseOffset")
			values.Rotation = instance:GetAttribute("QuadroGradientBaseRotation")
		end
	elseif tag == "QuadroStrokeScale" then
		local stroke = ownOrChild(instance, "UIStroke")
		local values = if stroke then snapshot.values[stroke] else nil
		if values then
			values.Thickness = instance:GetAttribute("QuadroStrokeBase")
		end
	end
end

local function restore(snapshot: Snapshot)
	for target, values in snapshot.values do
		local object = target :: any
		for name, value in values do
			if object[name] ~= value then
				object[name] = value
			end
		end
	end
	for host in snapshot.seen do
		for _, child in host:GetChildren() do
			if not child.Archivable and child:GetAttribute(TRANSIENT) == true then
				child:Destroy()
			end
		end
	end
end

local function capture(snapshot: Snapshot)
	for target, values in snapshot.values do
		local last = snapshot.last[target] or {}
		for name in values do
			last[name] = (target :: any)[name]
		end
		snapshot.last[target] = last
	end
end

local function adoptExternal(snapshot: Snapshot): boolean
	local changed = false
	for target, last in snapshot.last do
		local values = snapshot.values[target]
		for name, value in last do
			local live = (target :: any)[name]
			if live ~= value then
				values[name] = live
				changed = true
			end
		end
	end
	return changed
end

function Preview.mount(isActive: () -> boolean): Controller
	local StarterGui = game:GetService("StarterGui")
	local runtime: any = nil
	local running = false
	local starting = false
	local failed = false
	local snapshot: Snapshot? = nil
	local pending = 0
	local sinceScan = 0

	local function accept(tag: string, instance: Instance): boolean
		if not runtime.eligible(instance, tag) then
			return false
		end
		local current = snapshot
		if current then
			record(current, tag, instance, not starting)
		end
		return true
	end

	local function finish()
		if running then
			running = false
			local ok, err = pcall(runtime.stop)
			if not ok then
				warn("[Quadro] preview stop: " .. tostring(err))
			end
		end
		local current = snapshot
		snapshot = nil
		pending = 0
		sinceScan = 0
		if current then
			restore(current)
		end
	end

	local function begin(): boolean
		if runtime == nil then
			runtime = Installer.load()
			if runtime == nil then
				failed = true
				warn("[Quadro] preview: runtime failed to load")
				return false
			end
		end
		snapshot = { values = {}, last = {}, seen = {} }
		running = true
		starting = true
		local ok, err = pcall(runtime.start, StarterGui, accept)
		starting = false
		if not ok then
			failed = true
			warn("[Quadro] preview start: " .. tostring(err))
			finish()
			return false
		end
		return true
	end

	local connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		if not isActive() then
			failed = false
			finish()
			return
		end
		if failed or (not running and not begin()) then
			return
		end
		pending += dt
		sinceScan += dt
		if pending < STEP then
			return
		end
		local current = snapshot :: Snapshot
		if adoptExternal(current) then
			finish()
			return
		end
		if sinceScan >= SCAN then
			sinceScan = 0
			local refreshed, failure = pcall(runtime.refresh)
			if not refreshed then
				warn("[Quadro] preview refresh: " .. tostring(failure))
			end
		end
		local ok, err = pcall(runtime.step, pending)
		pending = 0
		if not ok then
			failed = true
			warn("[Quadro] preview step: " .. tostring(err))
			finish()
			return
		end
		capture(current)
	end)

	return {
		suspend = finish,
		unmount = function()
			connection:Disconnect()
			finish()
		end,
	}
end

return Preview
