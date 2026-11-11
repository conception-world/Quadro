--!strict
local StudioService = game:GetService("StudioService")
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Section = require(script.Parent.Parent.Components.Section)
local Badge = require(script.Parent.Parent.Components.Badge)
local Selection = require(script.Parent.Parent.Parent.Studio.Selection)
local Client = require(script.Parent.Parent.Parent.Bridge.Client)

type Translate = (key: string, ...any) -> string

type Props = {
	state: { [string]: any },
	t: Translate,
	run: (id: string, ...any) -> any,
	notify: (text: string, kind: string) -> (),
	bridge: { importPush: (id: string) -> (), setToken: (token: string) -> () },
}

local MAX_FILE_BYTES = 5 * 1024 * 1024
local importing = false
local STATS = {
	{ key = "created", label = "stat_created" },
	{ key = "updated", label = "stat_updated" },
	{ key = "kept", label = "stat_kept" },
	{ key = "removed", label = "stat_removed" },
	{ key = "orphaned", label = "stat_orphaned" },
	{ key = "pendingImages", label = "stat_pending" },
}

local function caption(text: string, order: number, color: Color3?)
	return Roact.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color or theme.colors.textMuted,
		Font = theme.typography.caption.font,
		TextSize = theme.typography.caption.size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order,
	})
end

local function column(order: number, children: { [any]: any })
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

local function findByFigmaId(rootId: string?, id: string): Instance?
	if rootId == nil then
		return nil
	end
	for _, screen in game:GetService("StarterGui"):GetChildren() do
		if screen:IsA("ScreenGui") and screen:GetAttribute("FigmaId") == rootId then
			if id == rootId then
				return screen
			end
			for _, descendant in screen:GetDescendants() do
				if descendant:GetAttribute("FigmaId") == id then
					return descendant
				end
			end
			return nil
		end
	end
	return nil
end

local MAX_ROWS = 200

local MessageList = Roact.Component:extend("QuadroMessageList")

function MessageList:init()
	self:setState({ content = 0 })
end

function MessageList:render()
	local children: { [any]: any } = table.clone(self.props.rows)
	children.layout = Roact.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, theme.spacing.sm),
		[Roact.Change.AbsoluteContentSize] = function(layout: UIListLayout)
			self:setState({ content = layout.AbsoluteContentSize.Y })
		end,
	})
	return Roact.createElement("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, math.min(self.state.content, theme.sizes.listMaxHeight)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = theme.sizes.scrollBar,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ScrollBarImageColor3 = theme.colors.surfaceActive,
		LayoutOrder = self.props.order,
	}, children)
end

local function messageRows(props: Props, messages: { string }, targets: { [string]: string }, rootId: string?, order: number)
	local rows: { [any]: any } = {}
	local shown = math.min(#messages, MAX_ROWS)
	for index = 1, shown do
		local message = messages[index]
		local targetId = targets[tostring(index)]
		local children: { [any]: any } = {
			text = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, if targetId then -(theme.sizes.selectWidth + theme.spacing.sm) else 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = message,
				TextColor3 = theme.colors.text,
				Font = theme.typography.caption.font,
				TextSize = theme.typography.caption.size,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}),
		}
		if targetId then
			children.select = Roact.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(theme.sizes.selectWidth, theme.sizes.keyHeight),
				BackgroundTransparency = 1,
			}, {
				button = Roact.createElement(Button, {
					text = props.t("import_select"),
					variant = "ghost",
					compact = true,
					size = UDim2.fromScale(1, 1),
					onClick = function()
						local target = findByFigmaId(rootId, targetId)
						if target then
							Selection.set({ target })
						else
							props.notify(props.t("figma_not_found"), "warning")
						end
					end,
				}),
			})
		end
		rows["row" .. index] = Roact.createElement("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, children)
	end
	if #messages > shown then
		rows.more = Roact.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = props.t("import_more", #messages - shown),
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = shown + 1,
		})
	end
	return Roact.createElement(MessageList, { order = order, rows = rows })
end

local function importFile(props: Props)
	if importing then
		return
	end
	importing = true
	local ok, contents = pcall(function(): string?
		local file = StudioService:PromptImportFileAsync({ "json" })
		if not file then
			return nil
		end
		return file:GetBinaryContents()
	end)
	importing = false
	if not ok then
		props.notify(props.t("error_import_failed", tostring(contents)), "error")
		return
	end
	if contents == nil then
		return
	end
	local text: string = contents
	if #text > MAX_FILE_BYTES then
		props.notify(props.t("import_file_too_large"), "error")
		return
	end
	props.run("import.spec", text)
end

local function statCell(t: Translate, stat: { key: string, label: string }, value: number, order: number)
	return Roact.createElement("Frame", {
		BackgroundColor3 = theme.colors.surface,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, {
		corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.spacing.sm),
			PaddingRight = UDim.new(0, theme.spacing.sm),
		}),
		label = Roact.createElement("TextLabel", {
			Size = UDim2.fromScale(0.7, 1),
			BackgroundTransparency = 1,
			Text = t(stat.label),
			TextColor3 = theme.colors.textMuted,
			Font = theme.typography.caption.font,
			TextSize = theme.typography.caption.size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		value = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.3, 1),
			BackgroundTransparency = 1,
			Text = tostring(value),
			TextColor3 = theme.colors.text,
			Font = theme.typography.label.font,
			TextSize = theme.typography.label.size,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

local function summaryBody(props: Props, summary: any)
	local t = props.t
	local statChildren: { [any]: any } = {
		grid = Roact.createElement("UIGridLayout", {
			CellSize = UDim2.new(0.5, -theme.spacing.sm / 2, 0, theme.sizes.row),
			CellPadding = UDim2.fromOffset(theme.spacing.sm, theme.spacing.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, stat in STATS do
		statChildren[stat.key] = statCell(t, stat, summary[stat.key], index)
	end
	local body: { [any]: any } = {}
	if summary.ok then
		body.stats = Roact.createElement("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, statChildren)
	end
	local warnings: { string } = summary.warnings
	local issues: { string } = summary.issues
	if #warnings > 0 then
		body.warningsTitle = caption(t("import_warnings", #warnings), 2, theme.colors.accentWarning)
		body.warnings = messageRows(props, warnings, summary.warningTargets, summary.rootId, 3)
	end
	if #issues > 0 then
		body.issuesTitle = caption(t("import_issues", #issues), 4, theme.colors.accentDecline)
		body.issues = messageRows(props, issues, summary.issueTargets, summary.rootId, 5)
	end
	return column(2, body)
end

local TokenField = Roact.Component:extend("QuadroTokenField")

function TokenField:init()
	self:setState({ focused = false })
end

function TokenField:render()
	local token: string = self.props.token
	local dots = "\u{2022}\u{2022}\u{2022}\u{2022}"
	local masked = if token == "" then "" elseif #token > 8 then dots .. string.sub(token, -4) else dots
	return Roact.createElement("TextBox", {
		Size = self.props.size,
		BackgroundColor3 = theme.colors.surface,
		BorderSizePixel = 0,
		Text = if self.state.focused then "" else masked,
		PlaceholderText = self.props.placeholder,
		PlaceholderColor3 = theme.colors.textMuted,
		TextColor3 = theme.colors.text,
		Font = theme.typography.body.font,
		TextSize = theme.typography.body.size,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = true,
		LayoutOrder = self.props.order,
		[Roact.Event.Focused] = function()
			self:setState({ focused = true })
		end,
		[Roact.Event.FocusLost] = function(box: TextBox)
			local typed = string.match(box.Text, "^%s*(.-)%s*$") or ""
			self:setState({ focused = false })
			if typed ~= "" then
				self.props.onToken(typed)
			end
		end,
	}, {
		corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.sm) }),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.spacing.sm),
			PaddingRight = UDim.new(0, theme.spacing.sm),
		}),
	})
end

type Listed = Client.Push & { reimport: boolean }

local function pushRow(props: Props, push: Listed, order: number)
	local t = props.t
	local reimport = push.reimport
	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		texts = Roact.createElement("Frame", {
			Size = UDim2.new(1, -(theme.sizes.selectWidth + theme.spacing.sm), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			layout = Roact.createElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			name = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, theme.typography.label.size + theme.spacing.tight),
				BackgroundTransparency = 1,
				Text = push.name,
				TextColor3 = theme.colors.text,
				Font = theme.typography.label.font,
				TextSize = theme.typography.label.size,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			meta = caption(Client.clock(push.time) .. "  " .. t("bridge_counts", push.done, push.pending, push.failed), 2),
		}),
		action = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(theme.sizes.selectWidth, theme.sizes.keyHeight),
			BackgroundTransparency = 1,
		}, {
			button = Roact.createElement(Button, {
				text = t(if reimport then "bridge_reimport" else "bridge_import"),
				variant = if reimport then "ghost" else "primary",
				compact = true,
				size = UDim2.fromScale(1, 1),
				onClick = function()
					task.spawn(props.bridge.importPush, push.id)
				end,
			}),
		}),
	})
end

local function bridgeStatus(props: Props): any
	local t = props.t
	local info: any = props.state.bridge
	local status: string? = if info then info.status else nil
	if status == nil then
		return Roact.createElement(Badge, { text = t("bridge_checking"), color = theme.colors.textMuted })
	elseif status == "connected" then
		if info.uploads == false then
			return Roact.createElement(Badge, { text = t("bridge_connected_no_uploads"), color = theme.colors.accentDecline })
		end
		return Roact.createElement(Badge, { text = t("bridge_connected"), color = theme.colors.accentAccept })
	end
	return Roact.createElement(Badge, { text = t("bridge_status_" .. status), color = theme.colors.accentDecline })
end

local function bridgeChildren(props: Props): { [any]: any }
	local t = props.t
	local info: any = props.state.bridge
	local status: string? = if info then info.status else nil
	local token: string = props.state.settings.bridgeToken
	local clearWidth = theme.sizes.selectWidth + theme.spacing.sm
	local tokenRowChildren: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, theme.spacing.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		field = Roact.createElement(TokenField, {
			order = 1,
			size = if token ~= "" then UDim2.new(1, -clearWidth, 0, theme.sizes.row) else UDim2.new(1, 0, 0, theme.sizes.row),
			token = token,
			placeholder = t("bridge_token_placeholder"),
			onToken = props.bridge.setToken,
		}),
	}
	if token ~= "" then
		tokenRowChildren.clear = Roact.createElement(Button, {
			text = t("bridge_token_clear"),
			variant = "ghost",
			compact = true,
			size = UDim2.fromOffset(theme.sizes.selectWidth, theme.sizes.keyHeight),
			layoutOrder = 2,
			onClick = function()
				props.bridge.setToken("")
			end,
		})
	end
	local children: { [any]: any } = {
		token = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, theme.sizes.row),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, tokenRowChildren),
	}
	if status ~= nil and status ~= "connected" then
		children.hint = caption(t("bridge_hint_" .. status), 3, theme.colors.accentDecline)
	end
	if status == "connected" and info.uploads == false then
		children.hint = caption(t("bridge_hint_no_uploads"), 3, theme.colors.accentDecline)
	end
	if status == "connected" then
		local pushes: { Listed } = info.pushes
		children.pushesTitle = caption(t("bridge_pushes"), 4)
		if #pushes == 0 then
			children.pushes = caption(t("bridge_no_pushes"), 5)
		else
			local rows: { [any]: any } = {}
			for index, push in pushes do
				rows["push" .. push.id] = pushRow(props, push, index)
			end
			children.pushes = Roact.createElement(MessageList, { order = 5, rows = rows })
		end
	end
	return children
end

local function Figma(props: Props)
	local t = props.t
	local summary: any = props.state.lastImport
	local lastBody: any
	if summary then
		lastBody = summaryBody(props, summary)
	else
		lastBody = caption(t("import_none"), 2)
	end
	return Roact.createFragment({
		bridge = Roact.createElement(Section, {
			title = t("card_bridge"),
			accessory = bridgeStatus(props),
			layoutOrder = 1,
			children = bridgeChildren(props),
		}),
		import = Roact.createElement(Section, {
			title = t("card_import"),
			layoutOrder = 2,
			children = {
				hint = caption(t("import_pick_hint"), 2),
				pick = Roact.createElement(Button, {
					text = t("import_pick"),
					variant = "primary",
					layoutOrder = 3,
					onClick = function()
						task.spawn(importFile, props)
					end,
				}),
			},
		}),
		last = Roact.createElement(Section, {
			title = t("card_last_import"),
			layoutOrder = 3,
			children = { body = lastBody },
		}),
		validate = Roact.createElement(Section, {
			title = t("card_validate"),
			layoutOrder = 4,
			children = {
				button = Roact.createElement(Button, {
					text = t("btn_validate"),
					variant = "ghost",
					layoutOrder = 2,
					onClick = function()
						props.run("import.validate")
					end,
				}),
			},
		}),
	})
end

return Figma
