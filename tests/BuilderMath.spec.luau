local BuilderMath = require("../src/BuilderMath")

local function bezier(a, b, t)
	local p0 = a.position
	local p3 = b.position
	local p1 = { p0[1] + a.right[1], p0[2] + a.right[2] }
	local p2 = { p3[1] + b.left[1], p3[2] + b.left[2] }
	local u = 1 - t
	local function axis(i)
		return u * u * u * p0[i] + 3 * u * u * t * p1[i] + 3 * u * t * t * p2[i] + t * t * t * p3[i]
	end
	return axis(1), axis(2)
end

return function(t)
	t.case("every preset has points inside the unit square", function()
		for _, name in BuilderMath.PRESETS do
			local points = BuilderMath.controlPoints(name)
			assert(points and #points >= 2, name)
			for _, p in points do
				assert(p.position[1] >= 0 and p.position[1] <= 1 and p.position[2] >= 0 and p.position[2] <= 1, name)
			end
		end
		t.eq(BuilderMath.controlPoints("zigzag"), nil)
	end)
	t.case("preset point counts", function()
		t.eq(#BuilderMath.controlPoints("line"), 2)
		t.eq(#BuilderMath.controlPoints("curve"), 2)
		t.eq(#BuilderMath.controlPoints("arc"), 3)
		t.eq(#BuilderMath.controlPoints("wave"), 4)
	end)
	t.case("curve is a quarter circle", function()
		local points = BuilderMath.controlPoints("curve")
		local x, y = bezier(points[1], points[2], 0.5)
		t.near(x, 1 - math.cos(math.pi / 4), 0.005)
		t.near(y, 1 - math.sin(math.pi / 4), 0.005)
	end)
	t.case("wave alternates crest and trough with end tangents open", function()
		local points = BuilderMath.controlPoints("wave")
		assert(points[1].position[2] > points[2].position[2])
		assert(points[2].position[2] < points[3].position[2])
		t.eq(points[1].left[1], 0)
		t.eq(points[4].right[1], 0)
	end)
	t.case("sample times are evenly spaced and hit both ends", function()
		local times = BuilderMath.sampleTimes(5)
		t.eq(#times, 5)
		t.eq(times[1], 0)
		t.eq(times[5], 1)
		t.near(times[3] - times[2], times[4] - times[3])
		t.eq(#BuilderMath.sampleTimes(BuilderMath.SAMPLE_MAX), BuilderMath.SAMPLE_MAX)
	end)
	t.case("sample count validation", function()
		t.eq(BuilderMath.validCount(2), true)
		t.eq(BuilderMath.validCount(64), true)
		t.eq(BuilderMath.validCount(1), false)
		t.eq(BuilderMath.validCount(65), false)
		t.eq(BuilderMath.validCount(3.5), false)
		t.eq(BuilderMath.validCount("8"), false)
	end)
	t.case("bounds cover every box", function()
		local box = BuilderMath.bounds({ { x = 10, y = 20, w = 100, h = 50 }, { x = 50, y = 5, w = 100, h = 30 } })
		t.eq(box.x, 10)
		t.eq(box.y, 5)
		t.eq(box.w, 140)
		t.eq(box.h, 65)
	end)
	t.case("nav buttons sit inside the area's bottom edge and split its width", function()
		local previous, following = BuilderMath.navBoxes({ x = 10, y = 20, w = 200, h = 100 })
		local inset = 100 * BuilderMath.BUTTON_INSET
		t.eq(previous.y, following.y)
		t.near(previous.y + previous.h, 120 - inset)
		assert(previous.y > 70)
		t.near(previous.x, 10 + inset)
		assert(following.x > previous.x + previous.w)
		t.near(following.x + following.w, 210 - inset)
		t.near(previous.w, following.w)
	end)
end
