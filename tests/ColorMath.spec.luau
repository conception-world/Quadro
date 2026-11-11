local ColorMath = require("../src/ColorMath")

return function(t)
	t.case("hsv to rgb covers the six sectors", function()
		local cases = {
			{ 0, "ff0000" },
			{ 1 / 6, "ffff00" },
			{ 1 / 3, "00ff00" },
			{ 0.5, "00ffff" },
			{ 2 / 3, "0000ff" },
			{ 5 / 6, "ff00ff" },
			{ 1, "ff0000" },
		}
		for _, case in cases do
			t.eq(ColorMath.toHex(case[1], 1, 1), case[2])
		end
		t.eq(ColorMath.toHex(0.3, 0, 1), "ffffff")
		t.eq(ColorMath.toHex(0.3, 1, 0), "000000")
		t.eq(ColorMath.toHex(1 / 3, 1, 0.5), "008000")
	end)
	t.case("rgb to hsv round-trips through hex", function()
		for _, hex in { "00e5ff", "ff8800", "123456", "808080", "ffffff", "000000", "8338ec", "06d6a0" } do
			local h, s, v = ColorMath.fromHex(hex)
			t.eq(ColorMath.toHex(h, s, v), hex)
		end
		local h, s, v = ColorMath.fromHex("00ff00")
		t.near(h, 1 / 3)
		t.near(s, 1)
		t.near(v, 1)
		h, s, v = ColorMath.fromHex("808080")
		t.eq(h, 0)
		t.eq(s, 0)
		t.near(v, 128 / 255)
	end)
	t.case("polar: hue is the angle from the right, counter-clockwise", function()
		local h, s = ColorMath.polar(1, 0)
		t.near(h, 0)
		t.near(s, 1)
		h, s = ColorMath.polar(0, -1)
		t.near(h, 0.25)
		h = ColorMath.polar(-1, 0)
		t.near(h, 0.5)
		h = ColorMath.polar(0, 1)
		t.near(h, 0.75)
		h, s = ColorMath.polar(math.cos(math.rad(120)), -math.sin(math.rad(120)))
		t.near(h, 1 / 3)
		t.near(s, 1)
		t.eq(ColorMath.toHex(h, s, 1), "00ff00")
		t.eq(ColorMath.toHex(h, s, 0.5), "008000")
	end)
	t.case("polar clamps outside the disc and centers at zero saturation", function()
		local h, s = ColorMath.polar(3, 4)
		t.eq(s, 1)
		t.near(h, (math.atan2(-4, 3) / (2 * math.pi)) % 1)
		local _, center = ColorMath.polar(0, 0)
		t.eq(center, 0)
		local _, half = ColorMath.polar(0.3, -0.4)
		t.near(half, 0.5)
	end)
	t.case("point inverts polar inside the disc", function()
		for _, sample in { { 0.1, 0.4 }, { 0.5, 1 }, { 0.9, 0.75 }, { 1 / 3, 1 } } do
			local x, y = ColorMath.point(sample[1], sample[2])
			local h, s = ColorMath.polar(x, y)
			t.near(h, sample[1])
			t.near(s, sample[2])
		end
		local x, y = ColorMath.point(0.25, 1)
		t.near(x, 0)
		t.near(y, -1)
	end)
	t.case("wheel pixels: white center, hue at the rim, transparent corners", function()
		local size = 180
		local pixels = ColorMath.wheel(size)
		t.eq(buffer.len(pixels), size * size * 4)
		local function at(column, row)
			local offset = (row * size + column) * 4
			return buffer.readu8(pixels, offset), buffer.readu8(pixels, offset + 1), buffer.readu8(pixels, offset + 2), buffer.readu8(pixels, offset + 3)
		end
		local r, g, b, a = at(90, 90)
		t.eq(a, 255)
		t.eq(r >= 250 and g >= 250 and b >= 250, true)
		r, g, b, a = at(178, 90)
		t.eq(r, 255)
		t.eq(g < 10 and b < 10, true)
		t.eq(a >= 250, true)
		r, g, b = at(90, 2)
		t.eq(g, 255)
		t.eq(r > 120 and r < 145 and b < 10, true)
		local _, _, _, corner = at(0, 0)
		t.eq(corner, 0)
		local _, _, _, outside = at(179, 90)
		t.eq(outside > 0 and outside < 255, true)
		local _, _, _, inside = at(175, 90)
		t.eq(inside, 255)
	end)
end
