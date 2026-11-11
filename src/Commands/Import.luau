--!strict
local HttpService = game:GetService("HttpService")
local Library = require(script.Parent.Parent.Gradients.Library)
local Build = require(script.Parent.Parent.Import.Build)
local Spec = require(script.Parent.Parent.Import.Spec)
local Validate = require(script.Parent.Parent.Import.Validate)
local ToolsPlus = require(script.Parent.ToolsPlus)

local Import = {}

local BOM = string.char(239, 187, 191)

local function failed(ctx: any, message: string): Build.Summary
	local summary: Build.Summary = {
		ok = false,
		created = 0,
		updated = 0,
		kept = 0,
		removed = 0,
		orphaned = 0,
		pendingImages = 0,
		warnings = {},
		issues = { message },
		warningTargets = {},
		issueTargets = {},
		screenGui = nil,
		rootId = nil,
	}
	ctx.store:set({ lastImport = summary })
	return summary
end

local function normalizedName(name: string): string
	return string.lower(string.match(name, "^%s*(.-)%s*$") or "")
end

function Import.run(ctx: any, json: any): Build.Summary
	if type(json) ~= "string" then
		return failed(ctx, ctx.t("import_not_string"))
	end
	if string.sub(json, 1, 3) == BOM then
		json = string.sub(json, 4)
	end
	local decoded, raw = pcall(HttpService.JSONDecode, HttpService, json)
	if not decoded then
		return failed(ctx, ctx.t("import_invalid_json", tostring(raw)))
	end
	local doc, errors = Spec.parse(raw)
	if not doc then
		return failed(ctx, table.concat(errors, "; "))
	end
	local summary = Build.run(doc, {
		nested = ctx.fromHook,
		library = {
			lookup = function(name: string): any?
				for _, data in Library.list(ctx.store) do
					if normalizedName(data.name) == name then
						return data
					end
				end
				return nil
			end,
			write = Library.write,
		},
	})
	ctx.store:set({ lastImport = summary })
	return summary
end

local function selectedScreenGui(): ScreenGui?
	for _, instance in game:GetService("Selection"):Get() do
		local screen = if instance:IsA("ScreenGui") then instance else instance:FindFirstAncestorOfClass("ScreenGui")
		if screen then
			return screen
		end
	end
	return nil
end

function Import.register(registry: any)
	registry:define("import.spec", "cmd_import", function(ctx, json)
		local summary = Import.run(ctx, json)
		if not summary.ok then
			if summary.busy then
				return { ok = false, count = 0, message = "error_busy" }
			end
			if summary.crashed then
				return { ok = false, count = 0, message = "import_failed", args = { table.concat(summary.issues, "; ") } }
			end
			return { ok = false, count = 0, message = "import_bad_spec", args = { table.concat(summary.issues, "; ") } }
		end
		ctx.notify(ctx.t("import_summary", summary.created, summary.updated, summary.removed, #summary.warnings), "success")
		ToolsPlus.announceRuntime(ctx, summary.runtime)
		if #summary.issues > 0 then
			ctx.notify(ctx.t("import_validator_issues", #summary.issues), "warning")
		end
		return { ok = true, count = summary.created }
	end)
	registry:define("import.validate", "cmd_validate", function(ctx)
		local screen = selectedScreenGui()
		if not screen then
			return { ok = false, count = 0, message = "error_no_screen_gui" }
		end
		local issues = Validate.run(screen)
		if #issues == 0 then
			ctx.notify(ctx.t("import_validator_ok"), "success")
			return { ok = true, count = 0 }
		end
		for _, issue in issues do
			warn("[Quadro] " .. issue)
		end
		return { ok = false, count = #issues, message = "import_validator_issues", args = { #issues } }
	end)
end

return Import
