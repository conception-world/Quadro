local Store = require("../src/App/Store")

return function(t)
	t.case("get returns a copy of the initial state", function()
		local initial = { tab = "tools" }
		local store = Store.new(initial)
		initial.tab = "figma"
		t.eq(store:get().tab, "tools")
	end)
	t.case("set notifies subscribers with the next state", function()
		local store = Store.new({ tab = "tools" })
		local seen = nil
		store:subscribe(function(state)
			seen = state.tab
		end)
		store:set({ tab = "figma" })
		t.eq(seen, "figma")
		t.eq(store:get().tab, "figma")
	end)
	t.case("set without changes does not notify", function()
		local store = Store.new({ tab = "tools" })
		local calls = 0
		store:subscribe(function()
			calls += 1
		end)
		store:set({ tab = "tools" })
		t.eq(calls, 0)
	end)
	t.case("unsubscribe stops notifications", function()
		local store = Store.new({ n = 0 })
		local calls = 0
		local unsubscribe = store:subscribe(function()
			calls += 1
		end)
		unsubscribe()
		store:set({ n = 1 })
		t.eq(calls, 0)
	end)
	t.case("a listener that unsubscribes mid-notify does not skip the others", function()
		local store = Store.new({ n = 0 })
		local calls = 0
		local unsubscribeFirst
		unsubscribeFirst = store:subscribe(function()
			unsubscribeFirst()
		end)
		store:subscribe(function()
			calls += 1
		end)
		store:set({ n = 1 })
		t.eq(calls, 1)
	end)
	t.case("listeners see the latest state when a listener sets during notify", function()
		local store = Store.new({ n = 0, derived = 0 })
		local lastSeen = nil
		store:subscribe(function(state)
			if state.derived ~= state.n * 2 then
				store:set({ derived = state.n * 2 })
			end
		end)
		store:subscribe(function(state)
			lastSeen = state.derived
		end)
		store:set({ n = 5 })
		t.eq(store:get().derived, 10)
		t.eq(lastSeen, 10)
	end)
	t.case("state returned by get is frozen", function()
		local store = Store.new({ a = 1 })
		t.eq(table.isfrozen(store:get()), true)
		store:set({ a = 2 })
		t.eq(table.isfrozen(store:get()), true)
		t.eq(store:get().a, 2)
	end)
end
