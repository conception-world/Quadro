local serde = require("@lune/serde")
local fs = require("@lune/fs")
local Spec = require("../src/Import/Spec")
local luneTask = require("@lune/task")
local Settings = require("../src/Studio/Settings")
local Client = require("../src/Bridge/Client")
local Resolve = require("../src/Bridge/Resolve")
local Backoff = require("../src/Bridge/Backoff")
local Session = require("../src/Bridge/Session")

local resolveEnv: any = getfenv(Resolve.one)
resolveEnv.task = luneTask

Settings.codec = {
	encode = function(value)
		return serde.encode("json", value)
	end,
	decode = function(text)
		return serde.decode("json", text)
	end,
}

return function(t)
	t.case("interpret maps statuses and bodies", function()
		t.eq(Client.interpret({ StatusCode = 200, Body = '{"version":1}' }).ok, true)
		t.eq(Client.interpret({ StatusCode = 200, Body = '{"version":1}' }).data.version, 1)
		t.eq(Client.interpret({ StatusCode = 401, Body = "{}" }).reason, "unauthorized")
		t.eq(Client.interpret({ StatusCode = 500, Body = "{}" }).reason, "bad_response")
		t.eq(Client.interpret({ StatusCode = 200, Body = "not json" }).reason, "bad_response")
		t.eq(Client.interpret({ StatusCode = 200, Body = "42" }).reason, "bad_response")
	end)
	t.case("reasonFor separates blocked HTTP from offline", function()
		t.eq(Client.reasonFor("HttpService: Http requests are not enabled"), "http_denied")
		t.eq(Client.reasonFor("Http request permission denied"), "http_denied")
		t.eq(Client.reasonFor("Couldn't connect to server"), "offline")
		t.eq(Client.reasonFor("ConnectFail"), "offline")
	end)
	t.case("get sends the token and port through the transport", function()
		local seen
		Client.setTransport(function(request)
			seen = request
			return { StatusCode = 200, Body = "[]" }
		end)
		local result = Client.pushes({ token = "abc", port = 1234 })
		Client.reset()
		t.eq(result.ok, true)
		t.eq(seen.Url, "http://127.0.0.1:1234/pushes")
		t.eq(seen.Headers["X-Quadro-Token"], "abc")
	end)
	t.case("get maps transport errors", function()
		Client.setTransport(function()
			error("Http requests are not enabled")
		end)
		local denied = Client.health({ token = "a", port = 1 })
		Client.setTransport(function()
			error("ConnectFail")
		end)
		local offline = Client.health({ token = "a", port = 1 })
		Client.reset()
		t.eq(denied.reason, "http_denied")
		t.eq(offline.reason, "offline")
	end)
	t.case("parsePushes keeps valid rows and defaults counts", function()
		local rows = Client.parsePushes({
			{ id = "p1", name = "Shop", rootId = "9:1", time = 1000, images = 3, done = 2, pending = 1, failed = 0 },
			{ id = 5, name = "bad" },
			{ id = "p2", name = "Bare" },
		})
		t.eq(#rows, 2)
		t.eq(rows[1].done, 2)
		t.eq(rows[1].rootId, "9:1")
		t.eq(rows[2].rootId, "")
		t.eq(rows[2].time, 0)
		t.eq(rows[2].failed, 0)
	end)
	t.case("clock formats HH:MM", function()
		t.eq(Client.clock(1700000000000), os.date("%H:%M", 1700000000))
		t.eq(#Client.clock(0), 5)
	end)
	t.case("decalId and imageId parse asset strings", function()
		t.eq(Resolve.decalId("decal:111"), 111)
		t.eq(Resolve.decalId("pending"), nil)
		t.eq(Resolve.decalId("decal:abc"), nil)
		t.eq(Resolve.imageId("rbxassetid://999"), 999)
		t.eq(Resolve.imageId("http://www.roblox.com/asset/?id=77"), 77)
		t.eq(Resolve.imageId(""), nil)
	end)
	t.case("resolve caches, passes rbxassetid through and leaves pending", function()
		local calls = 0
		Resolve.setLoader(function(id)
			calls += 1
			return if id == 111 then 999 else nil
		end)
		local cache = {}
		local failed = {}
		local hooks = {
			remember = function(hash, url)
				cache[hash] = url
			end,
			failed = function(hash)
				failed[hash] = true
			end,
		}
		local out = Resolve.all({
			a = { asset = "decal:111" },
			b = { asset = "pending" },
			c = { asset = "rbxassetid://5" },
			d = { asset = "decal:222" },
		}, cache, hooks)
		t.eq(out.c, "rbxassetid://5")
		t.eq(out.b, nil)
		t.eq(cache.a, "rbxassetid://999")
		t.eq(cache.c, nil)
		t.eq(failed.d, true)
		t.eq(failed.b, nil)
		Resolve.all({ a = { asset = "decal:111" } }, cache, hooks)
		t.eq(calls, 2)
		Resolve.reset()
	end)
	t.case("resolve never loads the same hash concurrently and does not block", function()
		local calls = 0
		Resolve.setLoader(function()
			calls += 1
			task.wait(0.1)
			return 7
		end)
		local cache = {}
		local hooks = {
			remember = function(hash, url)
				cache[hash] = url
			end,
			failed = function() end,
		}
		t.eq(Resolve.one("h", "decal:1", cache, hooks), nil)
		t.eq(Resolve.one("h", "decal:1", cache, hooks), nil)
		t.eq(Resolve.loading("h"), true)
		t.eq(Resolve.busy(), true)
		Resolve.waitIdle(2)
		t.eq(calls, 1)
		t.eq(cache.h, "rbxassetid://7")
		t.eq(Resolve.busy(), false)
		Resolve.reset()
	end)
	t.case("resolve gives up after the timeout", function()
		Resolve.setLoader(function()
			task.wait(0.4)
			return 7
		end)
		Resolve.setTimeout(0.1)
		local cache = {}
		local failed = false
		local hooks = {
			remember = function(hash, url)
				cache[hash] = url
			end,
			failed = function()
				failed = true
			end,
		}
		Resolve.one("h", "decal:1", cache, hooks)
		Resolve.waitIdle(2)
		t.eq(failed, true)
		t.eq(cache.h, nil)
		task.wait(0.5)
		t.eq(cache.h, nil)
		Resolve.reset()
	end)
	t.case("resolve survives a throwing loader", function()
		Resolve.setLoader(function()
			error("moderated")
		end)
		local failed = false
		Resolve.one("h", "decal:1", {}, { remember = function() end, failed = function() failed = true end })
		Resolve.waitIdle(2)
		t.eq(failed, true)
		Resolve.reset()
	end)
	t.case("results after a reset are discarded", function()
		Resolve.setLoader(function()
			task.wait(0.2)
			return 7
		end)
		local remembered, failed = false, false
		local hooks = {
			remember = function()
				remembered = true
			end,
			failed = function()
				failed = true
			end,
		}
		Resolve.one("h", "decal:1", {}, hooks)
		Resolve.reset()
		t.eq(Resolve.busy(), false)
		task.wait(0.5)
		t.eq(remembered, false)
		t.eq(failed, false)
	end)
	t.case("resolve reports why a decal failed", function()
		local messages = {}
		local hooks = {
			remember = function() end,
			failed = function(hash, message)
				messages[hash] = message
			end,
		}
		Resolve.setLoader(function(id)
			if id == 1 then
				error("moderated")
			end
			return nil
		end)
		Resolve.one("a", "decal:1", {}, hooks)
		Resolve.one("b", "decal:2", {}, hooks)
		Resolve.waitIdle(2)
		t.eq(string.find(messages.a, "^decal 1: .*moderated") ~= nil, true)
		t.eq(messages.b, "decal 2: no image id")
		Resolve.setLoader(function()
			task.wait(0.4)
			return 7
		end)
		Resolve.setTimeout(0.1)
		Resolve.one("c", "decal:3", {}, hooks)
		Resolve.waitIdle(2)
		t.eq(messages.c, "decal 3: timeout")
		Resolve.reset()
	end)
	t.case("bridge push fixture from the exporter parses and carries decal assets", function()
		local raw = serde.decode("json", fs.readFile("tests/fixtures/bridge-push.json"))
		local d, errors = Spec.parse(raw)
		t.eq(#errors, 0)
		t.eq(d ~= nil, true)
		t.eq(d.root.id, "2:1")
		local count = 0
		for _, entry in d.images do
			count += 1
			t.eq(string.match(entry.asset or "", "^decal:%d+$") ~= nil, true)
		end
		t.eq(count, 2)
	end)
	t.case("redact handles pattern characters in the secret", function()
		t.eq(Session.redact("bad ** token", "**"), "bad *** token")
		t.eq(Session.redact("x 100%d y", "%d"), "x 100*** y")
		t.eq(Session.redact("a%b%", "%"), "a***b***")
		t.eq(Session.redact("nothing", ""), "nothing")
	end)
	t.case("backoff schedule doubles up to the cap", function()
		t.eq(Backoff.delay(0), 0)
		t.eq(Backoff.delay(1), 2)
		t.eq(Backoff.delay(2), 4)
		t.eq(Backoff.delay(3), 8)
		t.eq(Backoff.delay(5), 32)
		t.eq(Backoff.delay(6), 60)
		t.eq(Backoff.delay(20), 60)
	end)
	t.case("backoff state tracks due, fail, clear and reset", function()
		local state = {}
		t.eq(Backoff.due(state, "h", 0), true)
		Backoff.fail(state, "h", 10)
		t.eq(Backoff.due(state, "h", 11), false)
		t.eq(Backoff.due(state, "h", 12), true)
		Backoff.fail(state, "h", 12)
		t.eq(Backoff.due(state, "h", 15), false)
		t.eq(Backoff.due(state, "h", 16), true)
		Backoff.clear(state, "h")
		t.eq(Backoff.due(state, "h", 0), true)
		Backoff.fail(state, "a", 0)
		Backoff.reset(state)
		t.eq(Backoff.due(state, "a", 0), true)
	end)
	t.case("push url encodes the id", function()
		local seen
		Client.setTransport(function(request)
			seen = request.Url
			return { StatusCode = 200, Body = "{}" }
		end)
		local original = Client.encode
		Client.encode = function(text)
			return (string.gsub(text, "[^%w]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end
		Client.push({ token = "a", port = 9 }, "a/b")
		Client.encode = original
		Client.reset()
		t.eq(seen, "http://127.0.0.1:9/push/a%2Fb")
	end)
	t.case("settings reject bad bridge values", function()
		local stored = {}
		local plugin = {
			GetSetting = function(_, key)
				return stored[key]
			end,
		}
		stored.Quadro_bridgePort = serde.encode("json", { v = 99999 })
		stored.Quadro_resolvedImages = serde.encode("json", { v = { a = 5 } })
		stored.Quadro_bridgeToken = serde.encode("json", { v = "tok" })
		local loaded = Settings.load(plugin :: any)
		t.eq(loaded.bridgePort, 34872)
		t.eq(next(loaded.resolvedImages), nil)
		t.eq(loaded.bridgeToken, "tok")
	end)
end
