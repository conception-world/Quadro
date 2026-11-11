local Codec = require("../src/Gradients/Codec")

local function sample(name)
	return {
		name = name,
		rotation = 90,
		offset = { 0, 0 },
		color = { { t = 0, c = "78ff9a", a = 0 }, { t = 1, c = "0fff73", a = 0 } },
		transparency = { { 0, 0 }, { 1, 0 } },
	}
end

return function(t)
	t.case("signature ignores the name", function()
		t.eq(Codec.signature(sample("Confirmation")), Codec.signature(sample("Other")))
	end)
	t.case("signature changes with the colors", function()
		local changed = sample("x")
		changed.color[2].c = "ff0000"
		t.eq(Codec.signature(sample("x")) ~= Codec.signature(changed), true)
	end)
	t.case("signature changes with the rotation", function()
		local rotated = sample("x")
		rotated.rotation = -90
		t.eq(Codec.signature(sample("x")) ~= Codec.signature(rotated), true)
	end)
	t.case("signature tolerates float noise below three decimals", function()
		local noisy = sample("x")
		noisy.color[2].t = 1.0000001
		t.eq(Codec.signature(sample("x")), Codec.signature(noisy))
	end)
	t.case("normalize lowercases hex and rounds rotation", function()
		local raw = sample("x")
		raw.color[1].c = "78FF9A"
		raw.rotation = 89.6
		local n = Codec.normalize(raw)
		t.eq(n.color[1].c, "78ff9a")
		t.eq(n.rotation, 90)
	end)
	t.case("sanitize accepts valid data", function()
		local d = Codec.sanitize(sample("Ok"))
		t.eq(d ~= nil and d.name, "Ok")
	end)
	t.case("sanitize rejects 21 color keypoints", function()
		local big = sample("x")
		big.color = {}
		for i = 0, 20 do
			table.insert(big.color, { t = i / 20, c = "ffffff", a = 0 })
		end
		t.eq(Codec.sanitize(big), nil)
	end)
	t.case("sanitize rejects a missing t=1 endpoint", function()
		local bad = sample("x")
		bad.color[2].t = 0.9
		t.eq(Codec.sanitize(bad), nil)
	end)
	t.case("sanitize rejects bad hex", function()
		local bad = sample("x")
		bad.color[1].c = "zzzzzz"
		t.eq(Codec.sanitize(bad), nil)
	end)
	t.case("sanitize clamps rotation", function()
		local wild = sample("x")
		wild.rotation = 999
		local d = Codec.sanitize(wild)
		t.eq(d ~= nil and d.rotation, 360)
	end)
	t.case("sanitize clamps offset", function()
		local wild = sample("x")
		wild.offset = { 5, -5 }
		local d = Codec.sanitize(wild)
		t.eq(d ~= nil and d.offset[1] == 1 and d.offset[2] == -1, true)
	end)
	t.case("sanitize converts the Easel legacy shape", function()
		local d = Codec.sanitize({
			name = "Legacy",
			rotation = 90,
			offset = { x = 0, y = 0 },
			color = { { time = 0, r = 1, g = 0, b = 0 }, { time = 1, r = 0, g = 0, b = 1 } },
			transparency = { { time = 0, value = 0, envelope = 0 }, { time = 1, value = 0.5, envelope = 0 } },
		})
		t.eq(d ~= nil and d.color[1].c, "ff0000")
		t.eq(d ~= nil and d.color[2].c, "0000ff")
		t.eq(d ~= nil and d.transparency[2][2], 0.5)
	end)
	t.case("sanitize rejects non-tables", function()
		t.eq(Codec.sanitize("x"), nil)
		t.eq(Codec.sanitize(nil), nil)
	end)
	t.case("sanitize caps the name length", function()
		local long = sample(string.rep("a", 100))
		local d = Codec.sanitize(long)
		t.eq(d ~= nil and #d.name, 60)
	end)
	t.case("sanitize clamps the stop alpha", function()
		local raw = sample("x")
		raw.color[1].a = 5
		raw.color[2].a = -3
		local clean = Codec.sanitize(raw)
		t.eq(clean ~= nil and clean.color[1].a, 1)
		t.eq(clean ~= nil and clean.color[2].a, 0)
	end)
end
