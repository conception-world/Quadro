--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Section = require(script.Parent.Parent.Components.Section)
local Flow = require(script.Parent.Parent.Components.Flow)
local Toggle = require(script.Parent.Parent.Components.Toggle)
local KeyCapture = require(script.Parent.Parent.Components.KeyCapture)
local Catalog = require(script.Parent.Parent.Parent.App.Catalog)

type Translate = (key: string, ...any) -> string

type Props = {
	settings: { [string]: any },
	t: Translate,
	labelKeys: { [string]: string },
	setSetting: (key: string, value: any) -> (),
}

local LANGUAGES = { "pt", "en" }
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }
local TOGGLES = {
	{ key = "notifications", title = "set_notifications", subtitle = "set_notifications_sub" },
	{ key = "swatchAnimation", title = "set_swatch", subtitle = "set_swatch_sub" },
	{ key = "keyNudge", title = "set_nudge", subtitle = "set_nudge_sub" },
	{ key = "pixelSnap", title = "set_snap", subtitle = "set_snap_sub" },
	{ key = "previewEffects", title = "set_preview", subtitle = "set_preview_sub" },
}
local CHANGELOG_ITEMS = 5

local function caption(text: string, order: number)
	return Roact.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = theme.colors.textMuted,
		Font = theme.typography.caption.font,
		TextSize = theme.typography.caption.size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order,
	})
end

local function list(order: number, children: { [any]: any })
	children.layout = Roact.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, theme.spacing.sm),
	})
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, children)
end

local function Settings(props: Props)
	local t = props.t
	local settings = props.settings

	local languageButtons: { [any]: any } = {}
	for index, lang in LANGUAGES do
		languageButtons[lang] = Roact.createElement(Button, {
			text = t("lang_" .. lang),
			variant = if settings.lang == lang then "primary" else "ghost",
			compact = true,
			layoutOrder = index,
			onClick = function()
				props.setSetting("lang", lang)
			end,
		})
	end

	local scaleButtons: { [any]: any } = {}
	for index, scale in SCALES do
		scaleButtons["scale" .. index] = Roact.createElement(Button, {
			text = string.format("%d%%", math.floor(scale * 100 + 0.5)),
			variant = if settings.uiScale == scale then "primary" else "ghost",
			compact = true,
			layoutOrder = index,
			onClick = function()
				props.setSetting("uiScale", scale)
			end,
		})
	end

	local toggleRows: { [any]: any } = {}
	for index, entry in TOGGLES do
		toggleRows[entry.key] = Roact.createElement(Toggle, {
			title = t(entry.title),
			subtitle = t(entry.subtitle),
			value = settings[entry.key] == true,
			layoutOrder = index,
			onChange = function(value: boolean)
				props.setSetting(entry.key, value)
			end,
		})
	end

	local shortcuts: { [string]: string } = settings.shortcuts
	local shortcutRows: { [any]: any } = { hint = caption(t("shortcuts_hint"), 0) }
	local quickIds: { string } = settings.quickActions
	local quickRows: { [any]: any } = { hint = caption(t("quick_hint"), 0) }
	for index, id in Catalog.SELECTION_IDS do
		local label = t(props.labelKeys[id])
		shortcutRows[id] = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, theme.sizes.keyHeight),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, {
			label = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, -(theme.sizes.keyWidth + theme.spacing.md), 1, 0),
				BackgroundTransparency = 1,
				Text = label,
				TextColor3 = theme.colors.text,
				Font = theme.typography.body.font,
				TextSize = theme.typography.body.size,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			capture = Roact.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(theme.sizes.keyWidth, theme.sizes.keyHeight),
				BackgroundTransparency = 1,
			}, {
				key = Roact.createElement(KeyCapture, {
					keyName = shortcuts[id],
					pressText = t("shortcut_press"),
					emptyText = t("shortcut_none"),
					onCapture = function(keyName: string?)
						props.setSetting("shortcuts", Catalog.assignShortcut(shortcuts, id, keyName))
					end,
				}),
			}),
		})
		quickRows[id] = Roact.createElement(Toggle, {
			title = label,
			value = table.find(quickIds, id) ~= nil,
			layoutOrder = index,
			onChange = function(value: boolean)
				local next = {}
				for _, existing in quickIds do
					if existing ~= id then
						table.insert(next, existing)
					end
				end
				if value then
					table.insert(next, id)
				end
				props.setSetting("quickActions", next)
			end,
		})
	end

	local changelogRows: { [any]: any } = {}
	for index = 1, CHANGELOG_ITEMS do
		changelogRows["item" .. index] = caption("•  " .. t("changelog_item_" .. index), index)
	end

	return Roact.createFragment({
		language = Roact.createElement(Section, {
			title = t("set_language"),
			layoutOrder = 1,
			children = { body = Roact.createElement(Flow, { layoutOrder = 2, children = languageButtons }) },
		}),
		scale = Roact.createElement(Section, {
			title = t("set_scale"),
			layoutOrder = 2,
			children = { body = Roact.createElement(Flow, { layoutOrder = 2, children = scaleButtons }) },
		}),
		toggles = Roact.createElement(Section, {
			layoutOrder = 3,
			children = { body = list(1, toggleRows) },
		}),
		shortcuts = Roact.createElement(Section, {
			title = t("set_shortcuts"),
			layoutOrder = 4,
			children = { body = list(2, shortcutRows) },
		}),
		quick = Roact.createElement(Section, {
			title = t("card_quick"),
			layoutOrder = 5,
			children = { body = list(2, quickRows) },
		}),
		changelog = Roact.createElement(Section, {
			title = t("set_changelog"),
			subtitle = t("changelog_version"),
			layoutOrder = 6,
			children = { body = list(2, changelogRows) },
		}),
	})
end

return Settings
