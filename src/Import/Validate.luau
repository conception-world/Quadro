--!strict
local Validate = {}

local CENTER = Vector2.new(0.5, 0.5)
local CORNER_KEYS = { "CornerRadius", "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }
local PADDING_KEYS = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" }

local function udimOffset(value: any): boolean
	return typeof(value) == "UDim" and value.Offset ~= 0
end

local function udim2Offset(value: any): boolean
	return typeof(value) == "UDim2" and (value.X.Offset ~= 0 or value.Y.Offset ~= 0)
end

function Validate.isEffectPiece(instance: Instance): boolean
	return not instance:IsA("GuiObject") and instance:GetAttribute("QuadroOwned") == true and instance:GetAttribute("QuadroEffect") ~= nil
end

function Validate.run(root: Instance): ({ string }, { [string]: string })
	local issues: { string } = {}
	local targets: { [string]: string } = {}
	local function report(instance: Instance, problem: string)
		table.insert(issues, instance:GetFullName() .. ": " .. problem)
		local owner: Instance? = instance
		while owner and owner:GetAttribute("FigmaId") == nil do
			owner = owner.Parent
		end
		if owner then
			targets[tostring(#issues)] = owner:GetAttribute("FigmaId")
		end
	end
	for _, d in root:GetDescendants() do
		if Validate.isEffectPiece(d) or d:GetAttribute("QuadroScrollWrap") == true or d:GetAttribute("QuadroFlowWrap") == true then
			continue
		elseif d:IsA("GuiObject") then
			if udim2Offset(d.Size) then
				report(d, "Size has Offset")
			end
			if udim2Offset(d.Position) then
				report(d, "Position has Offset")
			end
			if d.AnchorPoint ~= CENTER and d:GetAttribute("AnchorReason") == nil then
				report(d, "AnchorPoint off center without AnchorReason")
			end
			if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and not d.TextScaled then
				report(d, "TextScaled is false")
			end
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image == "" and d:GetAttribute("QuadroPendingImage") == nil then
				report(d, "empty Image without QuadroPendingImage")
			end
		elseif d:IsA("UIStroke") then
			if d.StrokeSizingMode ~= Enum.StrokeSizingMode.ScaledSize then
				report(d, "UIStroke not in ScaledSize")
			end
			if d.Thickness > 1 then
				report(d, "UIStroke Thickness above 1")
			end
			if udimOffset(d.BorderOffset) then
				report(d, "UIStroke BorderOffset has Offset")
			end
		elseif d:IsA("UICorner") then
			for _, key in CORNER_KEYS do
				local ok, value = pcall(function(): any
					return (d :: any)[key]
				end)
				if ok and udimOffset(value) then
					report(d, key .. " has Offset")
				end
			end
		elseif d:IsA("UIListLayout") then
			if udimOffset(d.Padding) then
				report(d, "UIListLayout Padding has Offset")
			end
		elseif d:IsA("UIGridLayout") then
			if udim2Offset(d.CellSize) or udim2Offset(d.CellPadding) then
				report(d, "UIGridLayout has Offset")
			end
		elseif d:IsA("UIPadding") then
			for _, key in PADDING_KEYS do
				if udimOffset((d :: any)[key]) then
					report(d, key .. " has Offset")
				end
			end
		elseif d:IsA("UIShadow") then
			if udim2Offset(d.Offset) or udimOffset(d.BlurRadius) or udim2Offset(d.Spread) then
				report(d, "UIShadow has Offset")
			end
		end
	end
	return issues, targets
end

return Validate
