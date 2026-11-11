--!strict
local Roact = require(script.Parent.Parent.Parent.Packages.Roact)
local theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)

export type Tab = { id: string, label: string }

type Props = {
	tabs: { Tab },
	active: string,
	onSelect: (id: string) -> (),
	layoutOrder: number?,
}

local Tabs = Roact.Component:extend("Tabs")

function Tabs:init()
	self.strip = Roact.createRef()
	self.settleConnection = nil :: RBXScriptConnection?
	self.revealPending = false
end

function Tabs:revealActive()
	local strip = self.strip:getValue() :: ScrollingFrame?
	if strip == nil then
		return
	end
	local pill = strip:FindFirstChild("tab_" .. (self.props :: Props).active)
	if pill == nil or not pill:IsA("GuiObject") then
		return
	end
	local window = strip.AbsoluteWindowSize.X
	local canvas = strip.AbsoluteCanvasSize.X
	if window <= 0 or canvas <= window then
		return
	end
	local current = strip.CanvasPosition.X
	local left = pill.AbsolutePosition.X - strip.AbsolutePosition.X + current
	local right = left + pill.AbsoluteSize.X
	local inset = theme.sizes.tabStripInset
	local target = current
	if left - inset < current then
		target = left - inset
	elseif right + inset > current + window then
		target = right + inset - window
	end
	target = math.clamp(target, 0, canvas - window)
	if target ~= current then
		strip.CanvasPosition = Vector2.new(target, 0)
	end
end

function Tabs:scheduleReveal()
	if self.revealPending then
		return
	end
	self.revealPending = true
	task.defer(function()
		self.revealPending = false
		self:revealActive()
	end)
end

function Tabs:didMount()
	local strip = self.strip:getValue() :: ScrollingFrame?
	if strip ~= nil then
		self.settleConnection = strip:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			self:scheduleReveal()
		end)
	end
	self:scheduleReveal()
end

function Tabs:didUpdate(previousProps: Props)
	if previousProps.active ~= (self.props :: Props).active then
		self:scheduleReveal()
	end
end

function Tabs:willUnmount()
	if self.settleConnection ~= nil then
		self.settleConnection:Disconnect()
		self.settleConnection = nil
	end
end

function Tabs:render()
	local props = self.props :: Props
	local inset = theme.sizes.tabStripInset
	local barClearance = theme.sizes.tabScrollBar + theme.sizes.tabBarGap
	local children: { [any]: any } = {
		layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, theme.spacing.sm),
		}),
		padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, inset),
			PaddingRight = UDim.new(0, inset),
			PaddingTop = UDim.new(0, inset),
			PaddingBottom = UDim.new(0, barClearance),
		}),
	}
	for index, tab in props.tabs do
		children["tab_" .. tab.id] = Roact.createElement(Button, {
			text = tab.label,
			variant = if tab.id == props.active then "primary" else "ghost",
			layoutOrder = index,
			compact = true,
			onClick = function()
				props.onSelect(tab.id)
			end,
		})
	end
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, theme.sizes.row + inset + barClearance),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		strip = Roact.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(-inset, 0),
			Size = UDim2.new(1, 2 * inset, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollBarThickness = theme.sizes.tabScrollBar,
			ScrollBarImageColor3 = theme.colors.surfaceActive,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			VerticalScrollBarInset = Enum.ScrollBarInset.None,
			HorizontalScrollBarInset = Enum.ScrollBarInset.None,
			[Roact.Ref] = self.strip,
			[Roact.Event.InputChanged] = function(strip: ScrollingFrame, input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.MouseWheel then
					return
				end
				local maxX = math.max(0, strip.AbsoluteCanvasSize.X - strip.AbsoluteWindowSize.X)
				local x = math.clamp(strip.CanvasPosition.X - input.Position.Z * theme.sizes.tabWheelStep, 0, maxX)
				strip.CanvasPosition = Vector2.new(x, 0)
			end,
		}, children),
	})
end

return Tabs
