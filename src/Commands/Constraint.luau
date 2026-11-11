--!strict
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Constraint = {}

function Constraint.register(registry: any)
	registry:define("constraint.aspect", "cmd_aspect", function(ctx)
		local targets = Selection.guiTargets()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local changed = 0
		local ok, cause = History.record("aspect", function()
			for _, gui in targets do
				local size = gui.AbsoluteSize
				if size.X > 0 and size.Y > 0 then
					local constraint = gui:FindFirstChildOfClass("UIAspectRatioConstraint")
					if constraint == nil then
						constraint = Instance.new("UIAspectRatioConstraint")
						constraint.Parent = gui
					end
					constraint.AspectRatio = math.round(size.X / size.Y * 10000) / 10000
					changed += 1
				end
			end
			return changed
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] constraint.aspect: " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		if changed == 0 then
			return { ok = false, count = 0, message = "error_no_size" }
		end
		ctx.notify(ctx.t("result_aspect", changed), "success")
		return { ok = true, count = changed }
	end)
end

return Constraint
