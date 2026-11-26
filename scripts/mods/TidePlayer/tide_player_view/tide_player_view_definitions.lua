-- tide_player_view_definitions.lua
-- 面板骨架：900×700，左边读数区，右边频道列表，底部一排方键。
-- 只用 rect / text，不依赖任何花哨材质——这就是游戏 UI 能稳定画出来的全部。

local mod = get_mod("TidePlayer")

local UIWorkspaceSettings = mod:original_require("scripts/settings/ui/ui_workspace_settings")
local UIFontSettings = mod:original_require("scripts/managers/ui/ui_font_settings")

local PANEL_WIDTH = 900
local PANEL_HEIGHT = 540
local PADDING = 16

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	panel = {
		parent = "screen",
		vertical_alignment = "center",
		horizontal_alignment = "center",
		size = {
			PANEL_WIDTH,
			PANEL_HEIGHT,
		},
		position = {
			0,
			0,
			10,
		},
	},
}

-- 统一 machine_medium：中文客户端就是中文字体。
local function make_text_style(font_size, color, alignment)
	local style = table.clone(UIFontSettings.body_medium)

	style.font_type = "machine_medium"
	style.font_size = font_size
	style.default_font_size = font_size
	style.text_color = color or Color.white(255, true)
	style.default_text_color = table.clone(style.text_color)
	style.text_horizontal_alignment = alignment or "left"
	style.text_vertical_alignment = "center"

	return style
end

local COLOR_GOLD = { 255, 216, 210, 192 }
local COLOR_AMBER = { 255, 234, 228, 206 }
local COLOR_GREEN = { 255, 152, 162, 134 }
local COLOR_DIM = { 255, 118, 128, 106 }
local COLOR_FAINT = { 255, 88, 98, 78 }
local COLOR_ROW = { 255, 178, 184, 160 }

local styles = {
	title = make_text_style(20, COLOR_GOLD, "left"),
	serial = make_text_style(11, COLOR_FAINT, "right"),
	label = make_text_style(12, COLOR_DIM, "left"),
	freq = make_text_style(42, COLOR_AMBER, "left"),
	song = make_text_style(28, COLOR_AMBER, "left"),
	artist = make_text_style(16, COLOR_GREEN, "left"),
	lyric = make_text_style(16, { 255, 224, 214, 184 }, "left"),
	lyric_next = make_text_style(14, COLOR_DIM, "left"),
	time = make_text_style(12, COLOR_DIM, "left"),
	row = make_text_style(13, COLOR_ROW, "left"),
	row_active = make_text_style(13, COLOR_AMBER, "left"),
	row_num = make_text_style(10, COLOR_FAINT, "left"),
	row_freq = make_text_style(10, COLOR_FAINT, "left"),
	button = make_text_style(14, COLOR_GOLD, "center"),
	button_active = make_text_style(14, COLOR_AMBER, "center"),
	status = make_text_style(12, COLOR_DIM, "left"),
}

local layout = {
	panel_width = PANEL_WIDTH,
	panel_height = PANEL_HEIGHT,
	padding = PADDING,

	header_y = 14,
	header_h = 30,

	stage_x = 16,
	stage_y = 58,
	stage_w = 520,
	stage_h = 380,

	list_x = 552,
	list_y = 58,
	list_w = 332,
	list_h = 380,

	ruler_x = 20,
	ruler_y = 170,
	ruler_step = 20,
	ruler_count = 24,
	ruler_width = 488,

	song_y = 90,
	song_h = 76,
	artist_y = 152,

	progress_y = 310,
	progress_h = 6,

	wave_y = 420,

	list_row_y = 64,
	list_row_h = 34,
	list_rows = 8,

	controls_y = 448,
	controls_h = 40,
}

return settings("TidePlayerViewDefinitions", {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = {},
	layout = layout,
	styles = styles,
})
