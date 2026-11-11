--!strict
local Roact = require(script.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Theme)
local Heading = require(script.Parent.Components.Heading)
local Badge = require(script.Parent.Components.Badge)
local Settings = require(script.Parent.Parent.Studio.Settings)
local Tabs = require(script.Parent.Components.Tabs)
local Toast = require(script.Parent.Components.Toast)
local Tools = require(script.Parent.Tabs.Tools)
local Effects = require(script.Parent.Tabs.Effects)
local LayoutTab = require(script.Parent.Tabs.Layout)
local BuildersTab = require(script.Parent.Tabs.Builders)
local LibraryTab = require(script.Parent.Tabs.Library)
local FigmaTab = require(script.Parent.Tabs.Figma)
local SettingsTab = require(script.Parent.Tabs.Settings)
local Codec = require(script.Parent.Parent.Gradients.Codec)
local GradientEditor = require(script.Parent.Parent.App.GradientEditor)
local SliceEditor = require(script.Parent.Parent.App.SliceEditor)
local ColorPicker = require(script.Parent.Parent.App.ColorPicker)

local TOP_HEIGHT = 104
local CAPTURE_LAYER = 100

type Translate = (key: string, ...any) -> string

type Props = {
	state: { [string]: any },
	t: Translate,
	showFigma: boolean,
	onSelectTab: (id: string) -> (),
	plugin: Plugin?,
	labelKeys: { [string]: string },
	run: (id: string, ...any) -> (),
	setSetting: (key: string, value: any) -> (),
	notify: (text: string, kind: string) -> (),
	saveData: (data: Codec.Data) -> (),
	bridge: { importPush: (id: string) -> (), setToken: (token: string) -> () },
	editor: GradientEditor.Api,
	slice: SliceEditor.Api,
	picker: ColorPicker.Api,
	disclose: (id: string, open: boolean) -> (),
	toggleSection: (tab: string, id: string) -> (),
	libraryRemove: (section: string, scope: string, key: string) -> (),
}

local function selectionText(t: Translate, count: number): string
	if count == 0 then
		return t("selection_none")
	elseif count == 1 then
		return t("selection_one")
	end
	return t("selection_many", count)
end

local function tabContent(props: Props): any
	local t = props.t
	local tab: string = props.state.tab
	local openSection: { [string]: boolean } = props.state.settings.openSections[tab] or {}
	local picker: ColorPicker.Handle = { state = props.state.colorPicker or ColorPicker.initial(), api = props.picker }
	local function toggleSection(id: string)
		props.toggleSection(tab, id)
	end
	if tab == "tools" then
		local disclosures: { [string]: boolean } = props.state.disclosures or {}
		return Roact.createElement(Tools, {
			settings = props.state.settings,
			applicable = props.state.applicable,
			t = t,
			labelKeys = props.labelKeys,
			run = props.run,
			setSetting = props.setSetting,
			openSection = openSection,
			toggleSection = toggleSection,
			presets = function(id: string)
				return {
					open = disclosures[id] == true,
					toggle = function()
						props.disclose(id, disclosures[id] ~= true)
					end,
				}
			end,
		})
	elseif tab == "effects" then
		return Roact.createElement(Effects, {
			state = props.state,
			t = t,
			plugin = props.plugin,
			run = props.run,
			saveData = props.saveData,
			editor = props.editor,
			slice = props.slice,
			picker = picker,
			disclose = props.disclose,
			openSection = openSection,
			toggleSection = toggleSection,
		})
	elseif tab == "layout" then
		local disclosures: { [string]: boolean } = props.state.disclosures or {}
		return Roact.createElement(LayoutTab, {
			t = t,
			run = props.run,
			openSection = openSection,
			toggleSection = toggleSection,
			presets = function(id: string)
				return {
					open = disclosures[id] == true,
					toggle = function()
						props.disclose(id, disclosures[id] ~= true)
					end,
				}
			end,
		})
	elseif tab == "builders" then
		local disclosures: { [string]: boolean } = props.state.disclosures or {}
		return Roact.createElement(BuildersTab, {
			t = t,
			run = props.run,
			picker = picker,
			openSection = openSection,
			toggleSection = toggleSection,
			presets = function(id: string)
				return {
					open = disclosures[id] == true,
					toggle = function()
						props.disclose(id, disclosures[id] ~= true)
					end,
				}
			end,
		})
	elseif tab == "library" then
		local disclosures: { [string]: boolean } = props.state.disclosures or {}
		return Roact.createElement(LibraryTab, {
			t = t,
			run = props.run,
			library = props.state.library,
			pending = props.state.libraryPending,
			remove = props.libraryRemove,
			picker = picker,
			openSection = openSection,
			toggleSection = toggleSection,
			presets = function(id: string)
				return {
					open = disclosures[id] == true,
					toggle = function()
						props.disclose(id, disclosures[id] ~= true)
					end,
				}
			end,
		})
	elseif tab == "figma" then
		return Roact.createElement(FigmaTab, {
			state = props.state,
			t = t,
			run = props.run,
			notify = props.notify,
			bridge = props.bridge,
		})
	elseif tab == "settings" then
		return Roact.createElement(SettingsTab, {
			settings = props.state.settings,
			t = t,
			labelKeys = props.labelKeys,
			setSetting = props.setSetting,
		})
	end
	return nil
end

type Drag = { move: (x: number, y: number) -> (), finish: () -> () }

local function activeDrag(props: Props): Drag?
	local editor = props.state.gradientEditor
	if editor ~= nil and editor.dragging ~= nil then
		return {
			move = function(x: number)
				props.editor.dragTo(x)
			end,
			finish = props.editor.dragEnd,
		}
	end
	local picker = props.state.colorPicker
	if picker ~= nil and picker.dragging ~= nil then
		return { move = props.picker.dragTo, finish = props.picker.dragEnd }
	end
	return nil
end

local function capture(props: Props): any
	local drag = activeDrag(props)
	if drag == nil then
		return nil
	end
	return Roact.createElement("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Active = true,
		Text = "",
		ZIndex = CAPTURE_LAYER,
		[Roact.Event.InputChanged] = function(_: TextButton, input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				drag.move(input.Position.X, input.Position.Y)
			end
		end,
		[Roact.Event.InputBegan] = function(_: TextButton, input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				drag.finish()
			end
		end,
		[Roact.Event.InputEnded] = function(_: TextButton, input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				drag.finish()
			end
		end,
		[Roact.Event.MouseLeave] = function()
			drag.finish()
		end,
	})
end

local function App(props: Props)
	local t = props.t
	local uiScale: number = props.state.settings.uiScale
	local count: number = props.state.selectionCount
	local tabs = {}
	for _, id in Settings.TAB_IDS do
		if id ~= "figma" or props.showFigma then
			table.insert(tabs, { id = id, label = t("tab_" .. id) })
		end
	end
	local toasts = {}
	for index, toast in props.state.toasts do
		toasts["toast" .. toast.id] = Roact.createElement(Toast, {
			text = toast.text,
			kind = toast.kind,
			layoutOrder = index,
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.colors.background,
		BorderSizePixel = 0,
	}, {
		top = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, TOP_HEIGHT),
			BackgroundTransparency = 1,
		}, {
			padding = Roact.createElement("UIPadding", {
				PaddingTop = UDim.new(0, theme.spacing.md),
				PaddingLeft = UDim.new(0, theme.spacing.md),
				PaddingRight = UDim.new(0, theme.spacing.md),
			}),
			layout = Roact.createElement("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, theme.spacing.md),
			}),
			header = Roact.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				title = Roact.createElement("Frame", {
					Size = UDim2.new(1, -150, 1, 0),
					BackgroundTransparency = 1,
				}, {
					heading = Roact.createElement(Heading, {
						title = "Quadro",
						subtitle = t("tagline"),
					}),
				}),
				selection = Roact.createElement("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromOffset(150, 22),
					BackgroundTransparency = 1,
				}, {
					layout = Roact.createElement("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
					}),
					badge = Roact.createElement(Badge, {
						text = selectionText(t, count),
						color = if count > 0 then theme.colors.accentAccept else theme.colors.textMuted,
					}),
				}),
			}),
			tabs = Roact.createElement(Tabs, {
				tabs = tabs,
				active = props.state.tab,
				onSelect = props.onSelectTab,
				layoutOrder = 2,
			}),
		}),
		toasts = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -theme.spacing.md),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			layout = Roact.createElement("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, theme.spacing.sm),
			}),
			list = Roact.createFragment(toasts),
		}),
		capture = capture(props),
		content = Roact.createElement("Frame", {
			Position = UDim2.fromOffset(0, TOP_HEIGHT),
			Size = UDim2.new(1, 0, 1, -TOP_HEIGHT),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			scroller = Roact.createElement("ScrollingFrame", {
				Size = UDim2.fromScale(1 / uiScale, 1 / uiScale),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = theme.colors.surfaceActive,
			}, {
				scale = Roact.createElement("UIScale", { Scale = uiScale }),
				padding = Roact.createElement("UIPadding", {
					PaddingTop = UDim.new(0, theme.spacing.sm),
					PaddingBottom = UDim.new(0, theme.spacing.md),
					PaddingLeft = UDim.new(0, theme.spacing.md),
					PaddingRight = UDim.new(0, theme.spacing.md),
				}),
				layout = Roact.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, theme.spacing.md),
				}),
				tab = tabContent(props),
			}),
		}),
	})
end

return App
