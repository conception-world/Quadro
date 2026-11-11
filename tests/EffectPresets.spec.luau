local EffectPresets = require("../src/EffectPresets")

return function(t)
	t.case("every drop preset has one or two valid layers", function()
		for _, name in EffectPresets.SHADOW_ORDER do
			if name ~= EffectPresets.INNER_PRESET then
				local layers = EffectPresets.SHADOWS[name]
				assert(layers ~= nil and #layers >= 1 and #layers <= 2, name)
				for _, layer in layers do
					assert(layer.y >= 0 and layer.blur > 0, name)
					assert(layer.transparency > 0 and layer.transparency < 1, name)
				end
			end
		end
		t.eq(EffectPresets.SHADOWS[EffectPresets.SHADOW_DEFAULT] ~= nil, true)
	end)
	t.case("drop presets climb the elevation scale", function()
		local previous = nil
		for _, name in { "soft", "medium", "deep", "float" } do
			local key = EffectPresets.SHADOWS[name][1]
			if previous then
				assert(key.y > previous.y, name .. " offset")
				assert(key.blur > previous.blur, name .. " blur")
				assert(key.transparency >= previous.transparency, name .. " opacity")
			end
			previous = key
		end
	end)
	t.case("inner preset is a frame gradient, not a UIShadow layer", function()
		t.eq(EffectPresets.SHADOWS[EffectPresets.INNER_PRESET], nil)
		t.eq(table.find(EffectPresets.SHADOW_ORDER, EffectPresets.INNER_PRESET) ~= nil, true)
		local inner = EffectPresets.INNER
		assert(inner.top > 0 and inner.top < 1, "top")
		assert(inner.fade > 0 and inner.fade < 1, "fade")
		assert(inner.rim > 0 and inner.rimTransparency > inner.top, "rim")
	end)
	t.case("neon layers ramp blur up and opacity down", function()
		local layers = EffectPresets.neonLayers(EffectPresets.NEON_MAX_LAYERS)
		t.eq(#layers, 4)
		local blurs = { 4, 8, 16, 32 }
		local alphas = { 0.3, 0.45, 0.6, 0.75 }
		for index, layer in layers do
			t.near(layer.blur, blurs[index])
			t.near(layer.transparency, alphas[index])
		end
		t.eq(#EffectPresets.neonLayers(1), 1)
		t.near(EffectPresets.neonLayers(2)[2].blur, 8)
	end)
	t.case("slice rect from margins", function()
		local rect = EffectPresets.sliceRect(10, 12, 14, 16, 100, 80)
		assert(rect ~= nil)
		t.eq(table.concat(rect, ","), "10,12,86,64")
		rect = EffectPresets.sliceRect(0, 0, 0, 0, 64, 64)
		assert(rect ~= nil)
		t.eq(table.concat(rect, ","), "0,0,64,64")
	end)
	t.case("slice rect validation", function()
		local function problem(...)
			local rect, key = EffectPresets.sliceRect(...)
			t.eq(rect, nil)
			return key
		end
		t.eq(problem(-1, 0, 0, 0, 100, 100), "slice_error_margin")
		t.eq(problem(0, 0, 0, 0 / 0, 100, 100), "slice_error_margin")
		t.eq(problem(50, 0, 50, 0, 100, 100), "slice_error_width")
		t.eq(problem(60, 0, 41, 0, 100, 100), "slice_error_width")
		t.eq(problem(0, 50, 0, 50, 100, 100), "slice_error_height")
		t.eq(problem(0, 0, 0, 0, 0, 100), "slice_error_size")
		t.eq(problem(0, 0, 0, 0, 100, math.huge), "slice_error_size")
		t.eq(EffectPresets.sliceRect(49, 0, 50, 0, 100, 100) ~= nil, true)
	end)
	t.case("slice args send the size only for a single image", function()
		local fields = { l = 1, t = 2, r = 3, b = 4, scale = 50, w = 100, h = 80, images = 1 }
		local one = EffectPresets.sliceArgs(fields)
		t.eq(#one, 7)
		t.eq(one[5], 0.5)
		t.eq(one[6], 100)
		t.eq(one[7], 80)
		fields.images = 2
		local many = EffectPresets.sliceArgs(fields)
		t.eq(#many, 5)
		t.eq(table.concat(many, ","), "1,2,3,4,0.5")
		fields.images = 1
		fields.w = nil
		t.eq(#EffectPresets.sliceArgs(fields), 5)
	end)
end
