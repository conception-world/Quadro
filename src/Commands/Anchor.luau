--!strict
local Geometry = require(script.Parent.Parent.Geometry)
local Gui = require(script.Parent.Parent.Studio.Gui)
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Anchor = {}

local function apply(gui: GuiObject, anchor: Vector2, preserve: boolean): boolean
	local parent = Gui.renderedParent(gui)
	local origin, box, unit = Gui.contentBox(parent)
	if parent == nil or box.X <= 0 or box.Y <= 0 then
		return false
	end
	if not preserve then
		gui.AnchorPoint = anchor
		return true
	end
	local topLeft = gui.AbsolutePosition - origin
	local size = gui.AbsoluteSize
	local position, guiSize = gui.Position, gui.Size
	gui.AnchorPoint = anchor
	local xScale, xOffset =
		Geometry.solveAxis(position.X.Scale, position.X.Offset, Geometry.anchorShift(topLeft.X, size.X, 0, anchor.X), box.X, unit, guiSize.X.Scale ~= 0)
	local yScale, yOffset =
		Geometry.solveAxis(position.Y.Scale, position.Y.Offset, Geometry.anchorShift(topLeft.Y, size.Y, 0, anchor.Y), box.Y, unit, guiSize.Y.Scale ~= 0)
	gui.Position = UDim2.new(xScale, xOffset, yScale, yOffset)
	return true
end

function Anchor.register(registry: any, getSettings: () -> { [string]: any })
	registry:define("anchor.set", "cmd_anchor", function(ctx, x: number, y: number)
		local targets = Selection.guiTargets()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local anchor = Vector2.new(x, y)
		local preserve = getSettings().anchorPreserve == true
		local changed = 0
		local ignored = 0
		local ok, cause = History.record("anchor", function()
			for _, gui in targets do
				if apply(gui, anchor, preserve) then
					changed += 1
				else
					ignored += 1
				end
			end
			return changed
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] anchor.set: " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		if changed > 0 then
			ctx.notify(ctx.t("result_anchor_set", changed), "success")
		end
		if ignored > 0 then
			ctx.notify(ctx.t("result_ignored_no_parent", ignored), "warning")
		end
		if changed == 0 then
			return { ok = false, count = 0, message = "result_ignored_no_parent", args = { ignored } }
		end
		return { ok = true, count = changed }
	end)
end

return Anchor
