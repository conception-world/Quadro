--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Gui = require(script.Parent.Parent.Studio.Gui)
local Selection = require(script.Parent.Parent.Studio.Selection)

local Nudge = {}

local ARROWS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
}
local ACTION = "Quadro_ArrowNudge"
local REPEAT_BIND = "Quadro_NudgeRepeat"
local BACKUP_KEY = "Quadro_cameraSpeedBackup"
local REPEAT_DELAY = 0.35
local REPEAT_RATE = 0.045
local SHIFT_STEP = 10
local MAX_STEPS_PER_FRAME = 2

local function nudgeAxis(value: UDim, delta: number, ref: number, unit: number): UDim
	if delta == 0 then
		return value
	end
	if value.Offset == 0 and value.Scale ~= 0 and ref > 0 then
		return UDim.new(value.Scale + delta * unit / ref, 0)
	end
	return UDim.new(value.Scale, value.Offset + delta)
end

local function moveSelection(dx: number, dy: number): number
	local targets = Selection.guiTargets()
	local selected: { [Instance]: boolean } = {}
	for _, target in targets do
		selected[target] = true
	end
	local moved = 0
	for _, target in targets do
		local ancestor = target.Parent
		while ancestor and not selected[ancestor] do
			ancestor = ancestor.Parent
		end
		if not ancestor then
			local parent = Gui.renderedParent(target)
			local _, box, unit = Gui.contentBox(parent)
			if parent ~= nil and box.X > 0 and box.Y > 0 then
				local position = target.Position
				target.Position = UDim2.new(nudgeAxis(position.X, dx, box.X, unit), nudgeAxis(position.Y, dy, box.Y, unit))
				moved += 1
			end
		end
	end
	return moved
end

function Nudge.attach(plugin: Plugin, getSettings: () -> { [string]: any }, notify: (string, string) -> ()): () -> ()
	local studioSettings = settings().Studio
	local held: { [Enum.KeyCode]: boolean } = {}
	local active = false
	local frozenSpeed: number? = nil
	local recording: string? = nil
	local moved = false
	local repeatClock = 0
	local nextRepeat = 0
	local busyNotified = false

	local function freezeCamera()
		local ok, speed = pcall(function()
			return (studioSettings :: any)["Camera Speed"]
		end)
		if not ok or type(speed) ~= "number" or speed <= 0 then
			return
		end
		frozenSpeed = speed
		pcall(plugin.SetSetting, plugin, BACKUP_KEY, speed)
		pcall(function()
			(studioSettings :: any)["Camera Speed"] = 0
		end)
	end

	local function unfreezeCamera()
		local speed = frozenSpeed
		if not speed then
			return
		end
		frozenSpeed = nil
		pcall(function()
			(studioSettings :: any)["Camera Speed"] = speed
		end)
		pcall(plugin.SetSetting, plugin, BACKUP_KEY, false)
	end

	local okBackup, backup = pcall(plugin.GetSetting, plugin, BACKUP_KEY)
	if okBackup and type(backup) == "number" and backup > 0 then
		pcall(function()
			if (studioSettings :: any)["Camera Speed"] == 0 then
				(studioSettings :: any)["Camera Speed"] = backup
			end
		end)
		pcall(plugin.SetSetting, plugin, BACKUP_KEY, false)
	end

	local function step(delta: Vector2): number
		local size = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			then SHIFT_STEP
			else 1
		return moveSelection(delta.X * size, delta.Y * size)
	end

	local function combined(): Vector2
		local sum = Vector2.zero
		for keyCode in held do
			sum += ARROWS[keyCode]
		end
		return sum
	end

	local function endSession()
		if active then
			active = false
			pcall(RunService.UnbindFromRenderStep, RunService, REPEAT_BIND)
			unfreezeCamera()
		end
		table.clear(held)
		if recording then
			local current = recording
			recording = nil
			local ok, err = pcall(function()
				ChangeHistoryService:FinishRecording(
					current :: any,
					if moved then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
				)
			end)
			if not ok then
				warn("[Quadro] nudge: " .. tostring(err))
			end
		end
		moved = false
	end

	local function onRenderStep(dt: number)
		if next(held) == nil then
			return
		end
		local anyDown = false
		for keyCode in held do
			if UserInputService:IsKeyDown(keyCode) then
				anyDown = true
			end
		end
		if not anyDown then
			endSession()
			return
		end
		repeatClock += dt
		local steps = 0
		while repeatClock >= nextRepeat and steps < MAX_STEPS_PER_FRAME do
			steps += 1
			repeatClock -= nextRepeat
			nextRepeat = REPEAT_RATE
			local delta = combined()
			if delta ~= Vector2.zero and step(delta) > 0 then
				moved = true
			end
		end
		if repeatClock >= nextRepeat then
			repeatClock = 0
		end
	end

	local function startSession(): boolean
		if active then
			return true
		end
		local began, result = pcall(function()
			return ChangeHistoryService:TryBeginRecording("Quadro_Nudge", "Quadro: Nudge") :: any
		end)
		if not began then
			warn("[Quadro] nudge: " .. tostring(result))
		end
		if not began or result == nil then
			if not busyNotified then
				busyNotified = true
				notify("error_busy", "error")
			end
			return false
		end
		recording = result
		active = true
		freezeCamera()
		local bound, bindError = pcall(function()
			RunService:BindToRenderStep(REPEAT_BIND, Enum.RenderPriority.Last.Value, function(dt: number)
				local ok, err = pcall(onRenderStep, dt)
				if not ok then
					warn("[Quadro] nudge: " .. tostring(err))
					endSession()
				end
			end)
		end)
		if not bound then
			warn("[Quadro] nudge: " .. tostring(bindError))
			endSession()
			return false
		end
		return true
	end

	local function onAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
		local delta = ARROWS[input.KeyCode]
		if not delta then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			if getSettings().keyNudge ~= true or #Selection.guiTargets() == 0 then
				return Enum.ContextActionResult.Pass
			end
			if not startSession() then
				return Enum.ContextActionResult.Pass
			end
			held[input.KeyCode] = true
			repeatClock = 0
			nextRepeat = REPEAT_DELAY
			local ok, moves = pcall(step, delta)
			if not ok then
				warn("[Quadro] nudge: " .. tostring(moves))
				endSession()
			elseif moves > 0 then
				moved = true
			end
			return Enum.ContextActionResult.Sink
		elseif state == Enum.UserInputState.End then
			busyNotified = false
			local wasHeld = held[input.KeyCode]
			held[input.KeyCode] = nil
			if next(held) == nil then
				endSession()
			end
			return if wasHeld then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Pass
	end

	ContextActionService:BindActionAtPriority(
		ACTION,
		onAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right
	)
	local inputEnded = UserInputService.InputEnded:Connect(function(input: InputObject)
		if held[input.KeyCode] then
			held[input.KeyCode] = nil
			if next(held) == nil then
				endSession()
			end
		end
	end)

	local focusReleased = UserInputService.WindowFocusReleased:Connect(endSession)

	return function()
		inputEnded:Disconnect()
		focusReleased:Disconnect()
		ContextActionService:UnbindAction(ACTION)
		endSession()
	end
end

return Nudge
