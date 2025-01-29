local M = {}

local default_signs = {
	left = "",
	right = "",
	diag = "●",
	arrow = "    ",
	up_arrow = "    ",
	vertical = " │",
	vertical_end = " └",
}

local function create_preset(overrides)
	local preset = {
		signs = vim.tbl_extend("force", default_signs, overrides.signs or {}),
		blend = {
			factor = overrides.blend and overrides.blend.factor or 0.22,
		},
	}
	return preset
end

function M.build(name, transparent_bg)
	local presets = {
		classic = create_preset({
			signs = {
				diag = "●",
				vertical = " │",
				vertical_end = " └",
			},
			blend = { factor = 0 },
		}),
		simple = create_preset({
			signs = {
				left = "",
				right = "",
				diag = "",
			},
		}),
		minimal = create_preset({
			signs = {
				left = "",
				right = "",
				diag = "",
				arrow = "",
				up_arrow = "",
				vertical = "  │",
				vertical_end = "  └",
			},
			blend = { factor = 0 },
		}),
		nonerdfont = create_preset({
			signs = {
				left = "░",
				right = "░",
				diag = "●",
				arrow = "   ",
			},
		}),
		ghost = create_preset({
			signs = {
				left = "",
				right = "",
				diag = "󰊠",
			},
		}),
		amongus = create_preset({
			signs = {
				left = "",
				right = "",
				diag = "ඞ",
			},
		}),
		powerline = create_preset({
			signs = {
				left = "",
				right = " ",
			},
		}),
	}

	local preset = presets[name] or create_preset({})

	if transparent_bg then
		preset.signs.left = ""
		preset.signs.right = ""
	end

	return preset
end

return M
