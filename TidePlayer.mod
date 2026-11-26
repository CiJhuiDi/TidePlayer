return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`TidePlayer` encountered an error loading the Darktide Mod Framework.")

		new_mod("TidePlayer", {
			mod_script       = "TidePlayer/scripts/mods/TidePlayer/TidePlayer",
			mod_data         = "TidePlayer/scripts/mods/TidePlayer/TidePlayer_data",
			mod_localization = "TidePlayer/scripts/mods/TidePlayer/TidePlayer_localization",
		})
	end,
	packages = {},
	version = "0.3.0",
	author = "CJDYZ",
}

