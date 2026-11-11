--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Catalog = require(script.Parent.Parent.Parent.App.Catalog)

type Props = {
	keyName: string?,
	pressText: string,
	emptyText: string,
	onCapture: (keyName: string?) -> (),
	layoutOrder: number?,
}

local MOUSE_BUTTONS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local ACTION = "Quadro_KeyCapture"

local KEY_CODES: { Enum.KeyCode } = {}
for _, item in Enum.KeyCode:GetEnumItems() do
	if item.Value > 0 and item.Value < 1000 and (item.Name == "Escape" or Catalog.capturable(item.Name)) then
		table.insert(KEY_CODES, item)
	end
end

local armed: (() -> ())? = nil

local KeyCapture = Roact.Component:extend("QuadroKeyCapture")

function KeyCapture:init()
	self:setState({ capturing = false })
	self.connections = {} :: { RBXScriptConnection }
	self.hovering = false
	self.active = false
	self.boxRef = Roact.createRef()
end

function KeyCapture:finish(keyName: string?)
	local props: Props = self.props
	self:stop()
	props.onCapture(keyName)
end

function KeyCapture:didUpdate(_: any, previousState: { capturing: boolean })
	if self.state.capturing and not previousState.capturing then
		local box = self.boxRef:getValue() :: TextBox?
		if box then
			box:CaptureFocus()
		end
	end
end

function KeyCapture:stop()
	self.active = false
	local box = self.boxRef:getValue() :: TextBox?
	if box and box:IsFocused() then
		box:ReleaseFocus()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if armed == self.disarm then
		ContextActionService:UnbindAction(ACTION)
		armed = nil
	end
	if self.state.capturing then
		self:setState({ capturing = false })
	end
end

function KeyCapture:begin()
	if armed then
		armed()
	end
	self.disarm = function()
		self:stop()
	end
	armed = self.disarm
	self.active = true
	ContextActionService:UnbindAction(ACTION)
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local focused = UserInputService:GetFocusedTextBox()
			if state ~= Enum.UserInputState.Begin or (focused ~= nil and focused ~= self.boxRef:getValue()) then
				return Enum.ContextActionResult.Pass
			end
			local keyName = input.KeyCode.Name
			self:finish(if keyName == "Escape" then nil else keyName)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(KEY_CODES)
	)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if MOUSE_BUTTONS[input.UserInputType] and not self.hovering then
				self:stop()
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.WindowFocusReleased:Connect(function()
			self:stop()
		end)
	)
	self:setState({ capturing = true })
end

function KeyCapture:willUnmount()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if armed == self.disarm then
		ContextActionService:UnbindAction(ACTION)
		armed = nil
	end
end

function KeyCapture:render()
	local props: Props = self.props
	local capturing: boolean = self.state.capturing
	return Roact.createElement("TextButton", {
		Size = UDim2.fromOffset(theme.sizes.keyWidth, theme.sizes.keyHeight),
		BackgroundColor3 = if capturing then theme.colors.accentPrimary else theme.colors.surface,
		BorderSizePixel = 0,
		AutoButtonColor = not capturing,
		Text = if capturing then props.pressText else (props.keyName or props.emptyText),
		TextColor3 = if capturing or props.keyName ~= nil then theme.colors.text else theme.colors.textMuted,
		Font = theme.typography.label.font,
		TextSize = theme.typography.label.size,
		LayoutOrder = props.layoutOrder,
		[Roact.Event.MouseEnter] = function()
			self.hovering = true
		end,
		[Roact.Event.MouseLeave] = function()
			self.hovering = false
		end,
		[Roact.Event.Activated] = function()
			if capturing then
				self:stop()
			else
				self:begin()
			end
		end,
	}, {
		capture = if capturing
			then Roact.createElement("TextBox", {
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				TextTransparency = 1,
				Text = "",
				ClearTextOnFocus = true,
				[Roact.Ref] = self.boxRef,
				[Roact.Event.InputBegan] = function(_: TextBox, input: InputObject)
					if not self.active or input.UserInputType ~= Enum.UserInputType.Keyboard then
						return
					end
					local keyName = input.KeyCode.Name
					if keyName == "Escape" then
						self:finish(nil)
					elseif Catalog.capturable(keyName) then
						self:finish(keyName)
					end
				end,
				[Roact.Event.FocusLost] = function()
					if self.active and not self.hovering then
						self:stop()
					end
				end,
			})
			else nil,
		corner = Roact.createElement("UICorner", { CornerRadius = UDim.new(0, theme.radius.pill) }),
	})
end

return KeyCapture
