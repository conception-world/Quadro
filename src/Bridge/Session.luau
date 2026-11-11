--!strict
local History = require("../Studio/History")
local Settings = require("../Studio/Settings")
local Backoff = require("./Backoff")
local Client = require("./Client")
local Resolve = require("./Resolve")

type Store = { get: (any) -> { [string]: any }, set: (any, { [string]: any }) -> () }

type Deps = {
	store: Store,
	setSetting: (key: string, value: any) -> (),
	t: (key: string, ...any) -> string,
	notify: (text: string, kind: string) -> (),
}

export type Listed = Client.Push & { reimport: boolean }

type Update = { instance: Instance, hash: string, url: string }

local Session = {}

local POLL_SECONDS = 2
local MAX_PUSH_SCANS = 10
local PREPARE_WAIT_SECONDS = 5

local function underLock(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if current:GetAttribute("QuadroLock") == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function countsKey(push: Client.Push): string
	return string.format("%d:%d:%d", push.done, push.pending, push.failed)
end

function Session.redact(message: string, secret: string): string
	if secret == "" then
		return message
	end
	local pattern = string.gsub(secret, "%p", "%%%0")
	local redacted = string.gsub(message, pattern, "***")
	return redacted
end

function Session.new(deps: Deps)
	local store = deps.store
	local polling = false
	local stopped = false
	local loopPolls = 0
	local lastPublished = ""
	local lastListSignature = ""
	local lastFillError = ""
	local warnedFailures: { [string]: boolean } = {}
	local retry: Backoff.State = {}
	local lastCounts: { [string]: string } = {}
	local knownHashes: { [string]: { [string]: boolean } } = {}

	local function config(): Client.Config
		local settings = store:get().settings
		return { token = settings.bridgeToken, port = settings.bridgePort }
	end

	local function cache(): { [string]: string }
		return store:get().settings.resolvedImages
	end

	local hooks: Resolve.Hooks = {
		remember = function(hash: string, url: string)
			Backoff.clear(retry, hash)
			local copy = table.clone(cache())
			copy[hash] = url
			deps.setSetting("resolvedImages", copy)
		end,
		failed = function(hash: string, message: string)
			Backoff.fail(retry, hash, os.clock())
			local safe = Session.redact(message, store:get().settings.bridgeToken)
			local key = hash .. "|" .. safe
			if not warnedFailures[key] then
				warnedFailures[key] = true
				warn("[Quadro] pending images: " .. safe)
			end
		end,
	}

	local function hasRoot(rootId: string): boolean
		if rootId == "" then
			return false
		end
		for _, screen in game:GetService("StarterGui"):GetChildren() do
			if screen:IsA("ScreenGui") and screen:GetAttribute("FigmaId") == rootId then
				return true
			end
		end
		return false
	end

	local function publish(status: string, pushes: { Client.Push }, uploads: boolean)
		local listed: { Listed } = {}
		for _, push in pushes do
			local copy: any = table.clone(push)
			copy.reimport = hasRoot(push.rootId)
			table.insert(listed, copy)
		end
		local signature = Settings.codec.encode({ status, listed, uploads })
		if signature == lastPublished then
			return
		end
		lastPublished = signature
		store:set({ bridge = { status = status, pushes = listed, uploads = uploads } })
	end

	local function pendingGroups(): { [string]: { Instance } }
		local groups: { [string]: { Instance } } = {}
		local roots: { Instance } = { game:GetService("StarterGui") }
		local templates = game:GetService("ReplicatedStorage"):FindFirstChild("QuadroTemplates")
		if templates then
			table.insert(roots, templates)
		end
		for _, root in roots do
			for _, descendant in root:GetDescendants() do
				local hash = descendant:GetAttribute("QuadroPendingImage")
				if type(hash) == "string" and not underLock(descendant) then
					local list = groups[hash] or {}
					table.insert(list, descendant)
					groups[hash] = list
				end
			end
		end
		return groups
	end

	local function scan(bridgeConfig: Client.Config, pushes: { Client.Push }, due: { [string]: boolean }, direct: { [string]: string })
		local wanted = table.clone(due)
		for index = 1, math.min(#pushes, MAX_PUSH_SCANS) do
			if next(wanted) == nil then
				break
			end
			local push = pushes[index]
			local key = countsKey(push)
			local known = knownHashes[push.id]
			local relevant = known == nil or lastCounts[push.id] ~= key
			if not relevant then
				for hash in wanted do
					if (known :: { [string]: boolean })[hash] then
						relevant = true
						break
					end
				end
			end
			if relevant then
				local response = Client.push(bridgeConfig, push.id)
				local images = if response.ok then response.data.images else nil
				if type(images) == "table" then
					lastCounts[push.id] = key
					local set: { [string]: boolean } = {}
					for hash in images do
						set[hash] = true
					end
					knownHashes[push.id] = set
					for hash in wanted do
						local entry = images[hash]
						if type(entry) == "table" then
							local asset = if type(entry.asset) == "string" then entry.asset else nil
							local url = Resolve.one(hash, asset, cache(), hooks)
							if url then
								direct[hash] = url
								Backoff.clear(retry, hash)
							end
							if url or Resolve.loading(hash) then
								wanted[hash] = nil
							end
						end
					end
				end
			end
		end
		local now = os.clock()
		for hash in due do
			if cache()[hash] == nil and direct[hash] == nil and not Resolve.loading(hash) then
				Backoff.fail(retry, hash, now)
			end
		end
	end

	local function fill(bridgeConfig: Client.Config, pushes: { Client.Push }, nested: boolean): number
		local groups = pendingGroups()
		if next(groups) == nil then
			return 0
		end
		local now = os.clock()
		local due: { [string]: boolean } = {}
		for hash in groups do
			if cache()[hash] == nil and not Resolve.loading(hash) and Backoff.due(retry, hash, now) then
				due[hash] = true
			end
		end
		local direct: { [string]: string } = {}
		if next(due) ~= nil then
			scan(bridgeConfig, pushes, due, direct)
		end
		if stopped then
			return 0
		end
		local updates: { Update } = {}
		for hash, instances in groups do
			local url = cache()[hash] or direct[hash]
			if url then
				for _, instance in instances do
					table.insert(updates, { instance = instance, hash = hash, url = url })
				end
			end
		end
		if #updates == 0 then
			return 0
		end
		local ok, result = History.record("Quadro images", function(): number
			local changed = 0
			for _, update in updates do
				local instance = update.instance
				if instance.Parent ~= nil and instance:GetAttribute("QuadroPendingImage") == update.hash and not underLock(instance) then
					(instance :: any).Image = update.url
					instance:SetAttribute("QuadroPendingImage", nil)
					changed += 1
				end
			end
			return changed
		end, { nested = nested })
		if not ok then
			if result == History.BUSY then
				return 0
			end
			error(tostring(result), 0)
		end
		return if type(result) == "number" then result else 0
	end

	local self = {}

	function self.poll(nested: boolean): { [string]: any }
		while polling do
			task.wait(0.05)
		end
		polling = true
		local summary: { [string]: any } = { status = "offline", pushes = 0, filled = 0 }
		local ok, err = pcall(function()
			if stopped then
				return
			end
			local cfg = config()
			if cfg.token == "" then
				summary.status = "no_token"
				publish("no_token", {}, true)
				return
			end
			local health = Client.health(cfg)
			if not health.ok then
				summary.status = health.reason
				publish(health.reason, {}, true)
				return
			end
			local listed = Client.pushes(cfg)
			if not listed.ok then
				summary.status = listed.reason
				publish(listed.reason, {}, true)
				return
			end
			local pushes = Client.parsePushes(listed.data)
			local parts = {}
			for _, push in pushes do
				table.insert(parts, push.id .. "=" .. countsKey(push))
			end
			local signature = table.concat(parts, ",")
			if signature ~= lastListSignature then
				lastListSignature = signature
				Backoff.reset(retry)
			end
			summary.status = "connected"
			summary.pushes = #pushes
			publish("connected", pushes, health.data.uploads ~= false)
			local filledOk, filled = pcall(fill, cfg, pushes, nested)
			if filledOk then
				summary.filled = filled
				lastFillError = ""
				if filled > 0 then
					deps.notify(deps.t("bridge_images_filled", filled), "success")
				end
			else
				local message = Session.redact(tostring(filled), cfg.token)
				warn("[Quadro] pending images: " .. message)
				if message ~= lastFillError then
					lastFillError = message
					deps.notify(deps.t("bridge_fill_failed", message), "error")
				end
			end
		end)
		polling = false
		if not ok then
			warn("[Quadro] bridge poll: " .. Session.redact(tostring(err), store:get().settings.bridgeToken))
		end
		summary.loopPolls = loopPolls
		return summary
	end

	function self.prepare(id: string): (string?, string?)
		if config().token == "" then
			return nil, "no_token"
		end
		local response = Client.push(config(), id)
		if not response.ok then
			return nil, response.reason
		end
		local spec = response.data
		if type(spec.images) == "table" then
			local direct = Resolve.all(spec.images, cache(), hooks)
			Resolve.waitIdle(PREPARE_WAIT_SECONDS)
			for hash, entry in spec.images do
				if type(entry) == "table" then
					entry.asset = cache()[hash] or direct[hash]
				end
			end
		end
		return Settings.codec.encode(spec), nil
	end

	function self.start(isActive: () -> boolean): () -> ()
		local running = true
		task.spawn(function()
			while running do
				if isActive() then
					loopPolls += 1
					self.poll(false)
				end
				task.wait(POLL_SECONDS)
			end
		end)
		return function()
			running = false
			stopped = true
			Resolve.stop()
		end
	end

	function self.loopPolls(): number
		return loopPolls
	end

	return self
end

return Session
