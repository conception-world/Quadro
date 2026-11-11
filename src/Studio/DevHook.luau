--!strict
local DevHook = {}

function DevHook.mount(handlers: { [string]: (...any) -> any }): () -> ()
	local existing = game:GetService("CoreGui"):FindFirstChild("QuadroDev")
	if existing then
		existing:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "QuadroDev"
	hook.Archivable = false
	hook.OnInvoke = function(method: string, ...: any): any
		local handler = handlers[method]
		if not handler then
			return "unknown method"
		end
		return handler(...)
	end
	hook.Parent = game:GetService("CoreGui")
	return function()
		hook:Destroy()
	end
end

return DevHook
