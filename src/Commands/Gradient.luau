--!strict
local Codec = require(script.Parent.Parent.Gradients.Codec)
local Files = require(script.Parent.Parent.Gradients.Files)
local Library = require(script.Parent.Parent.Gradients.Library)
local Scan = require(script.Parent.Parent.Gradients.Scan)
local History = require(script.Parent.Parent.Studio.History)

local Gradient = {}

type Result = { ok: boolean, count: number, message: string?, args: { any }? }

local function fail(message: string, ...: any): Result
	return { ok = false, count = 0, message = message, args = { ... } }
end

local function failed(name: string, cause: any): Result
	if cause == "busy" then
		return fail("error_busy")
	end
	warn("[Quadro] " .. name .. ": " .. tostring(cause))
	return fail("error_command_failed")
end

function Gradient.refresh(store: any)
	store:set({ gradientScan = Scan.summary(Scan.collect()) })
end

local function selectedGradients(): { Codec.Data }
	local found: { Codec.Data } = {}
	local seen: { [Instance]: boolean } = {}
	for _, selected in game:GetService("Selection"):Get() do
		local candidates: { Instance } = if selected:IsA("UIGradient")
			then { selected }
			elseif selected.Parent ~= game then selected:GetDescendants()
			else {}
		for _, candidate in candidates do
			if candidate:IsA("UIGradient") and not seen[candidate] then
				seen[candidate] = true
				table.insert(found, Library.toData(candidate))
			end
		end
	end
	return found
end

local function lookup(ctx: any, signature: string): Codec.Data?
	local saved = Library.find(ctx.store, signature)
	if saved then
		return saved
	end
	for _, group in Scan.collect() do
		if group.signature == signature then
			return group.data
		end
	end
	return nil
end

function Gradient.register(registry: any)
	registry:define("gradient.apply", "cmd_gradient_apply", function(ctx, signature: string)
		local data = lookup(ctx, signature)
		if not data then
			return fail("error_gradient_missing")
		end
		local targets = Scan.targets()
		if #targets == 0 then
			return fail("error_gradient_target")
		end
		local ok, cause = History.record("applyGradient", function()
			return Scan.apply(data, targets)
		end, { nested = ctx.fromHook })
		if not ok then
			return failed("gradient.apply", cause)
		end
		local applied: number = cause or 0
		if applied == 0 then
			return fail("error_gradient_target")
		end
		Gradient.refresh(ctx.store)
		ctx.notify(ctx.t("result_gradient_applied", applied), "success")
		return { ok = true, count = applied }
	end)

	registry:define("gradient.save", "cmd_gradient_save", function(ctx)
		local found = selectedGradients()
		if #found == 0 then
			return fail("error_gradient_none_selected")
		end
		local added, duplicates, failure = Library.add(ctx, found)
		if failure then
			return fail(failure)
		end
		if added == 0 then
			ctx.notify(ctx.t("result_gradient_duplicates", duplicates), "warning")
			return fail("result_gradient_duplicates", duplicates)
		end
		ctx.notify(ctx.t("result_gradient_saved", added), "success")
		return { ok = true, count = added }
	end)

	registry:define("gradient.rename", "cmd_gradient_rename", function(ctx, signature: string, name: string)
		if Library.cleanName(name) == nil then
			return fail("error_gradient_bad_name")
		end
		local renamed, failure = Library.rename(ctx, signature, name)
		if not renamed then
			return fail(failure or "error_command_failed")
		end
		return { ok = true, count = 1 }
	end)

	registry:define("gradient.delete", "cmd_gradient_delete", function(ctx, signature: string)
		local removed, failure = Library.remove(ctx, signature)
		if not removed then
			return fail(failure or "error_command_failed")
		end
		ctx.notify(ctx.t("result_gradient_deleted"), "info")
		return { ok = true, count = 1 }
	end)

	registry:define("gradient.select", "cmd_gradient_select", function(_ctx, signature: string)
		local count = Scan.selectReferences(signature)
		if count == 0 then
			return fail("error_gradient_missing")
		end
		return { ok = true, count = count }
	end)

	registry:define("gradient.refresh", "cmd_gradient_refresh", function(ctx)
		Gradient.refresh(ctx.store)
		return { ok = true, count = #ctx.store:get().gradientScan }
	end)

	registry:define("gradient.export", "cmd_gradient_export", function(ctx)
		if Files.isExporting() then
			return fail("error_busy")
		end
		local list = Library.list(ctx.store)
		if #list == 0 or ctx.plugin == nil then
			return fail("error_gradient_library_empty")
		end
		local ok, saved = Files.export(ctx.plugin, list)
		if not ok then
			warn("[Quadro] gradient.export: " .. tostring(saved))
			return fail("error_gradient_export_failed")
		end
		if saved ~= true then
			ctx.notify(ctx.t("result_gradient_cancelled"), "info")
			return { ok = true, count = 0, message = "result_gradient_cancelled" }
		end
		ctx.notify(ctx.t("result_gradient_exported", #list), "success")
		return { ok = true, count = #list, message = "result_gradient_exported", args = { #list } }
	end)

	registry:define("gradient.import", "cmd_gradient_import", function(ctx)
		local found, errorKey, detail = Files.import()
		if errorKey then
			ctx.notify(ctx.t(errorKey, detail or ""), "error")
			return fail(errorKey, detail or "")
		end
		if found == nil then
			ctx.notify(ctx.t("result_gradient_cancelled"), "info")
			return { ok = true, count = 0, message = "result_gradient_cancelled" }
		end
		if #found == 0 then
			ctx.notify(ctx.t("error_gradient_import_empty"), "warning")
			return fail("error_gradient_import_empty")
		end
		local added, duplicates, failure = Library.add(ctx, found)
		if failure then
			ctx.notify(ctx.t(failure), "error")
			return fail(failure)
		end
		if added == 0 then
			ctx.notify(ctx.t("result_gradient_duplicates", duplicates), "warning")
			return fail("result_gradient_duplicates", duplicates)
		end
		ctx.notify(ctx.t("result_gradient_imported", added), "success")
		return { ok = true, count = added }
	end)
end

return Gradient
