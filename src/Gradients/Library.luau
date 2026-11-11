--!strict
local Codec = require(script.Parent.Codec)
local Settings = require(script.Parent.Parent.Studio.Settings)

local Library = {}

Library.MAX_SAVED = 200

Library.cleanName = Codec.cleanName

function Library.toData(gradient: UIGradient, name: string?): Codec.Data
	local color: { Codec.Stop } = {}
	for _, point in gradient.Color.Keypoints do
		table.insert(color, { t = point.Time, c = point.Value:ToHex(), a = 0 })
	end
	local transparency: { { number } } = {}
	for _, point in gradient.Transparency.Keypoints do
		table.insert(transparency, { point.Time, point.Value })
	end
	local label: string = name or gradient.Name
	if name == nil and label == "UIGradient" then
		local owner = gradient.Parent
		if owner and owner:IsA("UIStroke") then
			owner = owner.Parent
		end
		label = if owner then owner.Name .. " Gradient" else "Gradient"
	end
	return Codec.normalize({
		name = Library.cleanName(label) or "Gradient",
		rotation = gradient.Rotation,
		offset = { gradient.Offset.X, gradient.Offset.Y },
		color = color,
		transparency = transparency,
	})
end

Library.GRADIENT_TYPES = { "Linear", "Radial", "Conical" }
Library.BASE_OFFSET = "QuadroGradientBaseOffset"
Library.BASE_ROTATION = "QuadroGradientBaseRotation"

Library.typeSupported = (function(): boolean
	local probe = Instance.new("UIGradient")
	local ok = pcall(function()
		return probe.Type
	end)
	probe:Destroy()
	return ok
end)()

function Library.baseHolder(gradient: UIGradient): Instance?
	local candidates: { Instance } = { gradient }
	if gradient.Parent then
		table.insert(candidates, gradient.Parent)
	end
	for _, candidate in candidates do
		if candidate:GetAttribute(Library.BASE_OFFSET) ~= nil or candidate:GetAttribute(Library.BASE_ROTATION) ~= nil then
			return candidate
		end
	end
	return nil
end

function Library.restData(gradient: UIGradient): Codec.Data
	local data = Library.toData(gradient)
	local holder = Library.baseHolder(gradient)
	if holder == nil then
		return data
	end
	local offset = holder:GetAttribute(Library.BASE_OFFSET)
	local rotation = holder:GetAttribute(Library.BASE_ROTATION)
	local finite = type(rotation) == "number" and rotation == rotation and math.abs(rotation) ~= math.huge
	return Codec.normalize({
		name = data.name,
		rotation = if finite then rotation else data.rotation,
		offset = if typeof(offset) == "Vector2" then { offset.X, offset.Y } else data.offset,
		color = data.color,
		transparency = data.transparency,
	})
end

function Library.colorSequence(stops: { Codec.Stop }): ColorSequence
	local points: { ColorSequenceKeypoint } = {}
	for _, stop in stops do
		table.insert(points, ColorSequenceKeypoint.new(stop.t, Color3.fromHex(stop.c)))
	end
	return ColorSequence.new(points)
end

function Library.numberSequence(points: { { number } }): NumberSequence
	local keypoints: { NumberSequenceKeypoint } = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

function Library.syncBase(gradient: UIGradient)
	local holder = Library.baseHolder(gradient)
	if holder then
		holder:SetAttribute(Library.BASE_OFFSET, gradient.Offset)
		holder:SetAttribute(Library.BASE_ROTATION, gradient.Rotation)
	end
end

function Library.write(gradient: UIGradient, data: Codec.Data): boolean
	local ok, err = pcall(function()
		gradient.Color = Library.colorSequence(data.color)
		gradient.Transparency = Library.numberSequence(data.transparency)
		gradient.Rotation = data.rotation
		gradient.Offset = Vector2.new(data.offset[1], data.offset[2])
		Library.syncBase(gradient)
	end)
	if not ok then
		warn("[Quadro] gradient write failed: " .. tostring(err))
	end
	return ok
end

function Library.list(store: any): { Codec.Data }
	local clean: { Codec.Data } = {}
	local stored = store:get().settings.gradients
	if type(stored) ~= "table" then
		return clean
	end
	for _, entry in stored do
		local data = Codec.sanitize(entry)
		if data then
			table.insert(clean, data)
		end
	end
	return clean
end

function Library.find(store: any, signature: string): Codec.Data?
	for _, data in Library.list(store) do
		if Codec.signature(data) == signature then
			return data
		end
	end
	return nil
end

local function persist(ctx: any, key: string, value: any): boolean
	if ctx.plugin and not Settings.save(ctx.plugin, key, value) then
		return false
	end
	local settings = table.clone(ctx.store:get().settings)
	settings[key] = value
	ctx.store:set({ settings = settings })
	return true
end

Library.persist = persist

function Library.add(ctx: any, batch: { Codec.Data }): (number, number, string?)
	local existing = Library.list(ctx.store)
	local known: { [string]: boolean } = {}
	for _, data in existing do
		known[Codec.signature(data)] = true
	end
	local merged: { Codec.Data } = {}
	local duplicates = 0
	for _, raw in batch do
		local data = Codec.sanitize(raw)
		if data then
			local signature = Codec.signature(data)
			if known[signature] then
				duplicates += 1
			else
				known[signature] = true
				table.insert(merged, data)
			end
		end
	end
	local added = #merged
	if added == 0 then
		return 0, duplicates, nil
	end
	if added + #existing > Library.MAX_SAVED then
		return 0, duplicates, "error_library_full"
	end
	table.move(existing, 1, #existing, added + 1, merged)
	if not persist(ctx, "gradients", merged) then
		return 0, duplicates, "error_command_failed"
	end
	return added, duplicates, nil
end

function Library.rename(ctx: any, signature: string, name: string): (boolean, string?)
	local clean = Library.cleanName(name)
	if not clean then
		return false, "error_gradient_bad_name"
	end
	local list = Library.list(ctx.store)
	for index, data in list do
		if Codec.signature(data) == signature then
			local renamed = table.clone(data)
			renamed.name = clean
			list[index] = renamed
			if persist(ctx, "gradients", list) then
				return true, nil
			end
			return false, "error_command_failed"
		end
	end
	return false, "error_gradient_missing"
end

function Library.remove(ctx: any, signature: string): (boolean, string?)
	local list = Library.list(ctx.store)
	for index, data in list do
		if Codec.signature(data) == signature then
			table.remove(list, index)
			if persist(ctx, "gradients", list) then
				return true, nil
			end
			return false, "error_command_failed"
		end
	end
	return false, "error_gradient_missing"
end

function Library.migrateFromEasel(ctx: any): number
	if ctx.store:get().settings.easelMigrated ~= false then
		return 0
	end
	local source = workspace:FindFirstChild("EaselGradients")
	if not source then
		return 0
	end
	local batch: { Codec.Data } = {}
	for _, instance in source:GetDescendants() do
		if instance:IsA("UIGradient") then
			table.insert(batch, Library.toData(instance, instance.Name))
		end
	end
	local added, _, failure = Library.add(ctx, batch)
	if failure == "error_library_full" then
		ctx.notify(ctx.t(failure), "error")
		persist(ctx, "easelMigrated", true)
		return 0
	elseif failure then
		return 0
	end
	persist(ctx, "easelMigrated", true)
	return added
end

return Library
