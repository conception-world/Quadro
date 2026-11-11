local Store = require("../src/App/Store")
local Notify = require("../src/App/Notify")

return function(t)
	t.case("push appends a toast", function()
		local store = Store.new({ toasts = {} })
		Notify.push(store, "Saved", "success", 10)
		local toasts = store:get().toasts
		t.eq(#toasts, 1)
		t.eq(toasts[1].text, "Saved")
		t.eq(toasts[1].kind, "success")
	end)
	t.case("keeps at most three toasts, dropping the oldest", function()
		local store = Store.new({ toasts = {} })
		for i = 1, 4 do
			Notify.push(store, "t" .. i, "info", i)
		end
		local toasts = store:get().toasts
		t.eq(#toasts, 3)
		t.eq(toasts[1].text, "t2")
		t.eq(toasts[3].text, "t4")
	end)
	t.case("expire removes toasts older than the ttl", function()
		local store = Store.new({ toasts = {} })
		Notify.push(store, "old", "info", 0)
		Notify.push(store, "new", "info", 5)
		Notify.expire(store, 6, 3)
		local toasts = store:get().toasts
		t.eq(#toasts, 1)
		t.eq(toasts[1].text, "new")
	end)
end
