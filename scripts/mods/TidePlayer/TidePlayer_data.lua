local mod = get_mod("TidePlayer")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	allow_rehooking = true,
	options = {
		widgets = {
			{
				setting_id = "tide_player_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "open_player",
						type = "keybind",
						default_value = {
							"f9",
						},
						keybind_trigger = "pressed",
						keybind_type = "view_toggle",
						view_name = "tide_player_view",
					},
					{
						setting_id = "toggle_play_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "toggle_play",
					},
					{
						setting_id = "next_track_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "next_track",
					},
					{
						setting_id = "prev_track_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "previous_track",
					},
					{
						setting_id = "volume_up_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "volume_up",
					},
					{
						setting_id = "volume_down_key",
						type = "keybind",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "volume_down",
					},
					{
						setting_id = "duck_game_music",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "hud_extra_offset",
						type = "numeric",
						default_value = 0,
						range = {
							0,
							200,
						},
						step_size_value = 4,
					},
					{
						setting_id = "hud_scroll_speed",
						type = "numeric",
						default_value = 0.12,
						range = {
							0.04,
							0.6,
						},
						step_size_value = 0.02,
						decimals_number = 2,
					},
					{
						setting_id = "lyric_offset",
						type = "numeric",
						default_value = 0,
						range = {
							-3000,
							3000,
						},
						step_size_value = 50,
					},
					{
						setting_id = "volume",
						type = "numeric",
						default_value = 70,
						range = {
							0,
							100,
						},
						step_size_value = 5,
					},
				},
			},
		},
	},
}
