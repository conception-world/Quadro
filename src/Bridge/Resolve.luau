--!strict
local Resolve = {}

export type Loader = (decalId: number) -> number?
export type Hooks = { remember: (hash: string, url: string) -> (), failed: (hash: string, message: string) -> () }

local DEFAULT_TIMEOUT = 20
local POLL_STEP = 0.05

function Resolve.decalId(asset: string): number?
	local digits = string.match(asset, "^decal:(%d+)$")
	return if digits then tonumber(digits) else nil
end

function Resolve.imageId(texture: string): number?
	local digits = string.match(texture, "^rbxassetid://(%d+)$") or string.match(texture, "[?&]id=(%d+)")
	return if digits then tonumber(digits) else nil
end

local function loadDecal(decalId: number): number?
	local model = game:GetService("InsertService"):LoadAsset(decalId)
	local decal = model:FindFirstChildWhichIsA("Decal", true)
	local texture = if decal then decal.Texture else ""
	model:Destroy()
	return Resolve.imageId(texture)
end

local loader: Loader = loadDecal
local timeout = DEFAULT_TIMEOUT
local inflight: { [string]: boolean } = {}
local inflightCount = 0
local generation = 0

function Resolve.setLoader(fn: Loader)
	loader = fn
end

function Resolve.setTimeout(seconds: number)
	timeout = seconds
end

function Resolve.stop()
	generation += 1
	inflight = {}
	inflightCount = 0
end

function Resolve.reset()
	loader = loadDecal
	timeout = DEFAULT_TIMEOUT
	Resolve.stop()
end

function Resolve.loading(hash: string): boolean
	return inflight[hash] == true
end

function Resolve.busy(): boolean
	return inflightCount > 0
end

function Resolve.waitIdle(maxSeconds: number)
	local started = os.clock()
	while inflightCount > 0 and os.clock() - started < maxSeconds do
		task.wait(POLL_STEP)
	end
end

local function start(hash: string, decalId: number, hooks: Hooks)
	inflight[hash] = true
	inflightCount += 1
	local mine = generation
	task.spawn(function()
		local finished = false
		local imageId: number? = nil
		local failure = "timeout"
		local worker = task.spawn(function()
			local ok, result = pcall(loader, decalId)
			imageId = if ok then result else nil
			failure = if ok then "no image id" else tostring(result)
			finished = true
		end)
		local started = os.clock()
		while not finished and mine == generation and os.clock() - started < timeout do
			task.wait(POLL_STEP)
		end
		if not finished then
			pcall(task.cancel, worker)
		end
		if mine ~= generation then
			return
		end
		inflight[hash] = nil
		inflightCount -= 1
		if imageId ~= nil then
			hooks.remember(hash, "rbxassetid://" .. imageId)
		else
			hooks.failed(hash, string.format("decal %d: %s", decalId, failure))
		end
	end)
end

function Resolve.one(hash: string, asset: string?, cache: { [string]: string }, hooks: Hooks): string?
	if cache[hash] then
		return cache[hash]
	end
	if asset == nil then
		return nil
	end
	if string.match(asset, "^rbxassetid://%d+$") then
		return asset
	end
	local decalId = Resolve.decalId(asset)
	if decalId ~= nil and not inflight[hash] then
		start(hash, decalId, hooks)
	end
	return nil
end

function Resolve.all(images: { [string]: any }, cache: { [string]: string }, hooks: Hooks): { [string]: string }
	local out: { [string]: string } = {}
	for hash, entry in images do
		local asset = if type(entry) == "table" and type(entry.asset) == "string" then entry.asset else nil
		local url = Resolve.one(hash, asset, cache, hooks)
		if url then
			out[hash] = url
		end
	end
	return out
end

return Resolve
