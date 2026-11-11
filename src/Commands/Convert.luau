--!strict
local CollectionService = game:GetService("CollectionService")
local History = require(script.Parent.Parent.Studio.History)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Convert = {}

Convert.CLASSES = {
	"Frame",
	"TextLabel",
	"TextButton",
	"ImageLabel",
	"ImageButton",
	"ViewportFrame",
	"CanvasGroup",
	"ScrollingFrame",
}

local COMMON = {
	"Name", "Position", "Size", "AnchorPoint", "Rotation", "Visible", "ZIndex", "LayoutOrder",
	"AutomaticSize", "SizeConstraint", "BackgroundColor3", "BackgroundTransparency",
	"BorderColor3", "BorderSizePixel", "BorderMode", "ClipsDescendants", "Active", "Selectable",
	"Interactable", "Archivable", "AutoLocalize", "RootLocalizationTable", "SelectionImageObject",
	"SelectionOrder", "NextSelectionUp", "NextSelectionDown", "NextSelectionLeft", "NextSelectionRight",
}
local TEXT = {
	"Text", "TextColor3", "TextSize", "FontFace", "TextScaled", "TextWrapped", "TextXAlignment",
	"TextYAlignment", "TextTransparency", "RichText", "TextStrokeColor3", "TextStrokeTransparency",
	"TextTruncate", "LineHeight", "MaxVisibleGraphemes",
}
local IMAGE = {
	"Image", "ImageColor3", "ImageTransparency", "ScaleType", "ResampleMode", "SliceCenter",
	"SliceScale", "TileSize", "ImageRectOffset", "ImageRectSize",
}
local BUTTON = { "AutoButtonColor", "Modal", "Selected" }
local SCROLLING = {
	"AutomaticCanvasSize", "BottomImage", "CanvasPosition", "CanvasSize", "ElasticBehavior",
	"HorizontalScrollBarInset", "MidImage", "ScrollBarImageColor3", "ScrollBarImageTransparency",
	"ScrollBarThickness", "ScrollingDirection", "ScrollingEnabled", "TopImage",
	"VerticalScrollBarInset", "VerticalScrollBarPosition",
}

local function copy(source: Instance, target: Instance, names: { string })
	for _, name in names do
		local readable, value = pcall(function()
			return (source :: any)[name]
		end)
		if readable and value ~= nil then
			pcall(function()
				(target :: any)[name] = value
			end)
		end
	end
end

local function convertOne(gui: GuiObject, className: string): GuiObject
	local replacement = Instance.new(className) :: GuiObject
	copy(gui, replacement, COMMON)
	if replacement:IsA("TextLabel") or replacement:IsA("TextButton") then
		if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
			copy(gui, replacement, TEXT)
		else
			(replacement :: any).Text = ""
		end
	end
	if replacement:IsA("ImageLabel") or replacement:IsA("ImageButton") then
		copy(gui, replacement, IMAGE)
	end
	if replacement:IsA("TextButton") or replacement:IsA("ImageButton") then
		copy(gui, replacement, BUTTON)
		replacement.Active = true
	end
	if replacement:IsA("ScrollingFrame") then
		copy(gui, replacement, SCROLLING)
	end
	for key, value in gui:GetAttributes() do
		replacement:SetAttribute(key, value)
	end
	for _, tag in CollectionService:GetTags(gui) do
		CollectionService:AddTag(replacement, tag)
	end
	for _, child in gui:GetChildren() do
		child.Parent = replacement
	end
	replacement.Parent = gui.Parent
	gui.Parent = nil
	return replacement
end

function Convert.register(registry: any)
	registry:define("convert.to", "cmd_convert", function(ctx, className: string)
		if not table.find(Convert.CLASSES, className) then
			return { ok = false, count = 0, message = "error_bad_class" }
		end
		local targets = Selection.guiTargets()
		if #targets == 0 then
			return { ok = false, count = 0, message = "error_no_selection" }
		end
		local result: { Instance } = {}
		local converted = 0
		local ok, cause = History.record("convert", function()
			for _, gui in targets do
				if gui.ClassName == className then
					table.insert(result, gui)
				else
					table.insert(result, convertOne(gui, className))
					converted += 1
				end
			end
			return converted
		end, { nested = ctx.fromHook })
		if not ok then
			if cause == "busy" then
				return { ok = false, count = 0, message = "error_busy" }
			end
			warn("[Quadro] convert.to: " .. tostring(cause))
			return { ok = false, count = 0, message = "error_command_failed" }
		end
		Selection.set(result)
		if converted == 0 then
			return { ok = false, count = 0, message = "result_already_class" }
		end
		ctx.notify(ctx.t("result_converted", converted), "success")
		return { ok = true, count = converted }
	end)
end

return Convert
