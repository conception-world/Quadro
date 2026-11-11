--!strict
local Geometry = require(script.Parent.Parent.Geometry)
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Transform = {}

local function convertUDim(value: UDim, ref: number, unit: number, toScale: boolean, snap: boolean): UDim
	if ref <= 0 or unit <= 0 then
		return value
	end
	local px = value.Scale * ref + value.Offset * unit
	if toScale then
		return UDim.new(Geometry.toScale(px, ref), 0)
	end
	local offset = px / unit
	return UDim.new(0, if snap then Geometry.pixelSnap(offset) else offset)
end

local function convertPosition(gui: GuiObject, toScale: boolean, snap: boolean): boolean
	local parent = Gui.renderedParent(gui)
	local _, box, unit = Gui.contentBox(parent)
	if parent == nil or box.X <= 0 or box.Y <= 0 then
		return false
	end
	local position = gui.Position
	gui.Position = UDim2.new(
		convertUDim(position.X, box.X, unit, toScale, snap),
		convertUDim(position.Y, box.Y, unit, toScale, snap)
	)
	return true
end

local function convertSize(gui: GuiObject, toScale: boolean, snap: boolean): boolean
	local parent = Gui.renderedParent(gui)
	local _, box, unit = Gui.contentBox(parent)
	local refs = Gui.sizeRefs(gui, box)
	if parent == nil or refs.X <= 0 or refs.Y <= 0 then
		return false
	end
	local size = gui.Size
	gui.Size = UDim2.new(
		convertUDim(size.X, refs.X, unit, toScale, snap),
		convertUDim(size.Y, refs.Y, unit, toScale, snap)
	)
	if (gui:IsA("ImageLabel") or gui:IsA("ImageButton")) and gui.ScaleType == Enum.ScaleType.Tile then
		local absolute = gui.AbsoluteSize
		local tile = gui.TileSize
		gui.TileSize = UDim2.new(
			convertUDim(tile.X, absolute.X, unit, toScale, snap),
			convertUDim(tile.Y, absolute.Y, unit, toScale, snap)
		)
	end
	return true
end

local function define(registry: any, getSettings: () -> { [string]: any }, id: string, labelKey: string, isSize: boolean, toScale: boolean)
	registry:define(id, labelKey, function(ctx)
		local targets = Selection.guiTargets()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local snap = getSettings().pixelSnap == true
		local converted = 0
		local ignored = 0
		local ok, cause = History.record(id, function()
			for _, gui in targets do
				local done = if isSize then convertSize(gui, toScale, snap) else convertPosition(gui, toScale, snap)
				if done then
					converted += 1
				else
					ignored += 1
				end
			end
			return converted
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] " .. id .. ": " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		if converted > 0 then
			ctx.notify(ctx.t("result_converted", converted), "success")
		end
		if ignored > 0 then
			ctx.notify(ctx.t("result_ignored_no_parent", ignored), "warning")
		end
		if converted == 0 then
			return { ok = false, count = 0, message = "result_ignored_no_parent", args = { ignored } }
		end
		return { ok = true, count = converted }
	end)
end

function Transform.register(registry: any, getSettings: () -> { [string]: any })
	define(registry, getSettings, "transform.posScale", "cmd_pos_scale", false, true)
	define(registry, getSettings, "transform.posOffset", "cmd_pos_offset", false, false)
	define(registry, getSettings, "transform.sizeScale", "cmd_size_scale", true, true)
	define(registry, getSettings, "transform.sizeOffset", "cmd_size_offset", true, false)
end

return Transform
