--!strict
local History = {}

History.BUSY = "busy"
History.commits = 0

function History.record(name: string, fn: () -> number?, opts: { nested: boolean? }?): (boolean, any)
	local service = game:GetService("ChangeHistoryService")
	local recording = service:TryBeginRecording("Quadro_" .. name, "Quadro: " .. name)
	if recording == nil then
		if opts and opts.nested == true and not game:GetService("RunService"):IsRunning() then
			local ok, result = pcall(fn)
			if ok then
				History.commits += 1
			end
			return ok, result
		end
		return false, History.BUSY
	end
	local ok, result = pcall(fn)
	local operation = if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	local finished, finishError = pcall(service.FinishRecording, service, recording, operation)
	if not finished then
		return false, finishError
	end
	if ok then
		History.commits += 1
	end
	return ok, result
end

return History
