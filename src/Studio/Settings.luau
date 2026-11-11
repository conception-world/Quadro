--!strict
local LibraryData = require("../LibraryData")

local Settings = {}

Settings.TAB_IDS = { "tools", "effects", "layout", "builders", "library", "figma", "settings" }

Settings.SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }

Settings.SECTIONS = {
	tools = { "quick", "transform", "anchor", "convert", "layout", "text", "hybrid", "stroke", "corner", "padding", "textFit", "responsive" },
	effects = { "studio", "library", "strokeGlow", "shadow", "motion", "textMask", "nineSlice" },
	layout = { "align", "organize", "match", "structure" },
	builders = { "path", "drag", "pages" },
	library = { "tokens", "components", "file" },
} :: { [string]: { string } }

Settings.VALID = {
	tab = Settings.TAB_IDS,
	uiScale = Settings.SCALES,
	lang = { "pt", "en" },
} :: { [string]: { any } }

Settings.DEFAULTS = {
	lang = "pt",
	tab = "tools",
	uiScale = 1,
	notifications = true,
	swatchAnimation = true,
	keyNudge = true,
	pixelSnap = true,
	anchorPreserve = true,
	hybridX = 0.7,
	hybridY = 0.7,
	textMin = 8,
	textMax = 48,
	previewEffects = true,
	openSections = {},
	quickActions = { "transform.sizeScale", "transform.posScale", "constraint.aspect", "layout.group" },
	shortcuts = {},
	gradients = {},
	easelMigrated = false,
	bridgeToken = "",
	bridgePort = 34872,
	resolvedImages = {},
	globalLibrary = { tokens = {}, components = {} },
} :: { [string]: any }

Settings.codec = {
	encode = function(value: any): string
		return game:GetService("HttpService"):JSONEncode(value)
	end,
	decode = function(text: string): any
		return game:GetService("HttpService"):JSONDecode(text)
	end,
}

local function copyValue(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copyValue(v)
	end
	return out
end

local function unwrap(raw: any): any
	if type(raw) ~= "string" then
		return raw
	end
	local ok, decoded = pcall(Settings.codec.decode, raw)
	if ok and type(decoded) == "table" then
		return decoded.v
	end
	return raw
end

local function validBridge(key: string, value: any): boolean
	if key == "bridgePort" then
		return value == math.floor(value) and value >= 1 and value <= 65535
	elseif key == "resolvedImages" then
		for hash, url in value do
			if type(hash) ~= "string" or type(url) ~= "string" then
				return false
			end
		end
	end
	return true
end

local function sanitize(out: { [string]: any })
	for _, key in { "hybridX", "hybridY" } do
		local value = out[key]
		if type(value) ~= "number" or value ~= value then
			out[key] = Settings.DEFAULTS[key]
		else
			out[key] = math.clamp(value, 0, 1)
		end
	end
	for _, key in { "textMin", "textMax" } do
		local value = out[key]
		if type(value) ~= "number" or value ~= value then
			out[key] = Settings.DEFAULTS[key]
		else
			out[key] = math.clamp(math.round(value), 1, 100)
		end
	end
	if out.textMin > out.textMax then
		out.textMax = out.textMin
	end
	local saved = if type(out.openSections) == "table" then out.openSections else {}
	local open: { [string]: { [string]: boolean } } = {}
	for tab, ids in Settings.SECTIONS do
		local value = saved[tab]
		local set: { [string]: boolean } = {}
		if type(value) == "table" then
			for _, id in ids do
				if value[id] == true then
					set[id] = true
				end
			end
		elseif value == "" then
			set = {}
		elseif Settings.sectionValid(tab, value) then
			set[value] = true
		else
			set[ids[1]] = true
		end
		open[tab] = set
	end
	out.openSections = open
	out.globalLibrary = LibraryData.sanitizeGlobal(out.globalLibrary)
end

function Settings.sectionValid(tab: any, id: any): boolean
	local ids = if type(tab) == "string" then Settings.SECTIONS[tab] else nil
	return ids ~= nil and type(id) == "string" and table.find(ids, id) ~= nil
end

function Settings.load(plugin: Plugin): { [string]: any }
	local out: { [string]: any } = {}
	for key, default in Settings.DEFAULTS do
		out[key] = copyValue(default)
	end
	for key, default in Settings.DEFAULTS do
		local ok, raw = pcall(plugin.GetSetting, plugin, "Quadro_" .. key)
		if ok and raw ~= nil then
			local value = unwrap(raw)
			if key == "tab" and value == "gradients" then
				value = "effects"
			end
			if typeof(value) == typeof(default) and (Settings.VALID[key] == nil or table.find(Settings.VALID[key], value)) and validBridge(key, value) then
				out[key] = copyValue(value)
			end
		end
	end
	sanitize(out)
	return out
end

function Settings.save(plugin: Plugin, key: string, value: any): boolean
	local name = "Quadro_" .. key
	local ok, err = pcall(function()
		local encoded = Settings.codec.encode({ v = value })
		plugin:SetSetting(name, encoded)
		if plugin:GetSetting(name) ~= encoded then
			error("read-back mismatch")
		end
	end)
	if not ok then
		warn(string.format("[Quadro] failed to save setting %s: %s", key, tostring(err)))
	end
	return ok
end

return Settings
