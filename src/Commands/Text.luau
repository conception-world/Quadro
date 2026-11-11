--!strict
local History = require(script.Parent.Parent.Studio.History)

local Text = {}

local function isText(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function collect(): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function add(instance: Instance)
		if isText(instance) and not seen[instance] then
			seen[instance] = true
			table.insert(found, instance)
		end
	end
	for _, selected in game:GetService("Selection"):Get() do
		add(selected)
		for _, descendant in selected:GetDescendants() do
			add(descendant)
		end
	end
	return found
end

Text.collect = collect

function Text.any(): boolean
	for _, selected in game:GetService("Selection"):Get() do
		if
			isText(selected)
			or selected:FindFirstChildWhichIsA("TextLabel", true)
			or selected:FindFirstChildWhichIsA("TextButton", true)
			or selected:FindFirstChildWhichIsA("TextBox", true)
		then
			return true
		end
	end
	return false
end

function Text.register(registry: any)
	registry:define("text.scale", "cmd_scale_text", function(ctx)
		local targets = collect()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_text" }
		end
		local ok, cause = History.record("scaleText", function()
			for _, instance in targets do
				local label = instance :: TextLabel
				if label:FindFirstChildOfClass("UITextSizeConstraint") == nil then
					local limit = Instance.new("UITextSizeConstraint")
					limit.MaxTextSize = label.TextSize
					limit.Parent = label
				end
				label.TextScaled = true
			end
			return #targets
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] text.scale: " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		ctx.notify(ctx.t("result_text_scaled", #targets), "success")
		return { ok = true, count = #targets }
	end)
end

return Text
