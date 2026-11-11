--!strict
local AssetService = game:GetService("AssetService")
local SelectionService = game:GetService("Selection")
local EffectPresets = require(script.Parent.Parent.EffectPresets)
local Selection = require(script.Parent.Parent.Studio.Selection)

export type State = {
	target: Instance?,
	uri: string?,
	images: number,
	w: number?,
	h: number?,
	l: number,
	t: number,
	r: number,
	b: number,
	scale: number,
}
export type Env = { store: any, run: (id: string, ...any) -> any }
export type Api = {
	pick: () -> (),
	set: (key: string, value: number) -> (),
	apply: () -> (),
}

local SliceEditor = {}

local FIELDS = { l = true, t = true, r = true, b = true, w = true, h = true, scale = true }
local CLEARABLE = { "target", "uri", "w", "h" }

local sizes: { [string]: Vector2 } = {}
local failed: { [string]: boolean } = {}
local fetching: { [string]: boolean } = {}

function SliceEditor.initial(): State
	return { images = 0, l = 0, t = 0, r = 0, b = 0, scale = EffectPresets.SLICE_PERCENT }
end

local function current(store: any): State
	return store:get().sliceEditor or SliceEditor.initial()
end

local function put(store: any, patch: { [string]: any })
	local nextState = table.clone(current(store)) :: any
	for key, value in patch do
		nextState[key] = value
	end
	for _, key in CLEARABLE do
		if patch[key] == false then
			nextState[key] = nil
		end
	end
	store:set({ sliceEditor = nextState })
end

local function isImage(target: Instance): boolean
	return target:IsA("ImageLabel") or target:IsA("ImageButton")
end

local function selectedImages(): (Instance?, number)
	local first: Instance? = nil
	local count = 0
	for _, target in Selection.candidates() do
		if isImage(target) then
			count += 1
			first = first or target
		end
	end
	return first, count
end

local function adopt(image: any, size: Vector2?): { [string]: any }
	local patch: { [string]: any } = { l = 0, t = 0, r = 0, b = 0, scale = EffectPresets.SLICE_PERCENT, w = false, h = false }
	if size == nil then
		return patch
	end
	patch.w, patch.h = size.X, size.Y
	if image.ScaleType == Enum.ScaleType.Slice then
		local center: Rect = image.SliceCenter
		local l, t = center.Min.X, center.Min.Y
		local r, b = size.X - center.Max.X, size.Y - center.Max.Y
		if EffectPresets.sliceRect(l, t, r, b, size.X, size.Y) then
			patch.l, patch.t, patch.r, patch.b = l, t, r, b
			patch.scale = math.clamp(math.round(image.SliceScale * EffectPresets.SLICE_PERCENT), EffectPresets.SLICE_SCALE_MIN, EffectPresets.SLICE_SCALE_MAX)
		end
	end
	return patch
end

local function knownSize(image: any): Vector2?
	local region: Vector2 = image.ImageRectSize
	if region.X > 0 and region.Y > 0 then
		return region
	end
	return sizes[image.Image]
end

local ensureSize: (store: any) -> ()

function SliceEditor.pick(store: any, force: boolean?)
	local state = current(store)
	local image: any, count = selectedImages()
	if image == nil then
		if state.target ~= nil or state.images ~= 0 then
			put(store, { target = false, uri = false, images = 0 })
		end
		return
	end
	local uri: string = image.Image
	if not force and image == state.target and uri == state.uri then
		if count ~= state.images then
			put(store, { images = count })
		end
		ensureSize(store)
		return
	end
	local patch = adopt(image, knownSize(image))
	patch.target, patch.uri, patch.images = image, uri, count
	put(store, patch)
	ensureSize(store)
end

local function fetch(store: any, uri: string)
	fetching[uri] = true
	task.spawn(function()
		local ok, result = pcall(function(): any
			return (AssetService :: any):CreateEditableImageAsync(Content.fromUri(uri))
		end)
		fetching[uri] = nil
		if ok and result ~= nil then
			sizes[uri] = result.Size
			result:Destroy()
		else
			failed[uri] = true
			warn("[Quadro] 9-slice: image size unavailable for " .. uri .. ": " .. tostring(result))
		end
		local state = current(store)
		if state.uri == uri then
			SliceEditor.pick(store, true)
		end
	end)
end

ensureSize = function(store: any)
	local state = current(store)
	local uri = state.uri
	if state.target == nil or state.w ~= nil or uri == nil or uri == "" then
		return
	end
	if failed[uri] or fetching[uri] or sizes[uri] or store:get().tab ~= "effects" then
		return
	end
	fetch(store, uri)
end

function SliceEditor.bind(env: Env): Api
	local api = {}
	function api.pick()
		SliceEditor.pick(env.store)
	end
	function api.set(key: string, value: number)
		if FIELDS[key] and type(value) == "number" and value == value then
			put(env.store, { [key] = value })
		end
	end
	function api.apply()
		env.run("effect.nineSlice", table.unpack(EffectPresets.sliceArgs(current(env.store))))
	end
	return api
end

function SliceEditor.public(state: State?): { [string]: any }
	local copy: { [string]: any } = table.clone(state or SliceEditor.initial()) :: any
	copy.target = if state and state.target then state.target.Name else nil
	copy.sizeFailed = state ~= nil and state.uri ~= nil and failed[state.uri] == true
	return copy
end

function SliceEditor.watch(store: any, active: (state: { [string]: any }) -> boolean): () -> ()
	local imageConnection: RBXScriptConnection? = nil
	local lastTab = store:get().tab
	local stale = false
	local function follow()
		if imageConnection then
			imageConnection:Disconnect()
			imageConnection = nil
		end
		SliceEditor.pick(store)
		local target = current(store).target
		if target then
			imageConnection = target:GetPropertyChangedSignal("Image"):Connect(function()
				SliceEditor.pick(store)
			end)
		end
	end
	local function changed()
		if active(store:get()) then
			follow()
		else
			stale = true
		end
	end
	local selectionConnection = SelectionService.SelectionChanged:Connect(changed)
	local unsubscribe = store:subscribe(function(state: { [string]: any })
		if state.tab ~= lastTab then
			lastTab = state.tab
			task.defer(ensureSize, store)
		end
		if stale and active(state) then
			stale = false
			task.defer(follow)
		end
	end)
	changed()
	return function()
		selectionConnection:Disconnect()
		unsubscribe()
		if imageConnection then
			imageConnection:Disconnect()
		end
	end
end

return SliceEditor
