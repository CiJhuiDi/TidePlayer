-- TidePlayer_volume_hud.lua
-- 调音量时在屏幕上方中央亮一条「VOL 70」，1.5 秒后消失。
-- 和迷你 HUD 分开，因为迷你 HUD 只在游戏内（alive/dead）显示，大厅里跑不到。

local mod = get_mod("TidePlayer")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")

require("scripts/ui/hud/elements/hud_element_base")

local WIDTH = 260
local HEIGHT = 46

local COLOR_TEXT = UIHudSettings.color_tint_main_1
-- 弹窗/面板用的可拉伸底，左右两边都是完整的
local COLOR_BACKGROUND = Color.terminal_grid_background(235, true)

local function is_visible(content)
	return content.visible == true
end

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	hud = {
		parent = "screen",
		scale = "fit",
		-- 放在屏幕底部中央，比体力条再低一截
		vertical_alignment = "bottom",
		horizontal_alignment = "center",
		size = {
			WIDTH,
			HEIGHT,
		},
		position = {
			0,
			-110,
			100,
		},
	},
}

local widget_definitions = {
	background = UIWidget.create_definition({
		{
			style_id = "background",
			pass_type = "texture",
			value = "content/ui/materials/backgrounds/terminal_basic",
			visibility_function = is_visible,
			style = {
				vertical_alignment = "top",
				size = {
					WIDTH,
					HEIGHT,
				},
				offset = {
					0,
					0,
					0,
				},
				color = table.clone(COLOR_BACKGROUND),
			},
		},
	}, "hud", {
		visible = false,
	}, {
		WIDTH,
		HEIGHT,
	}),

	text = UIWidget.create_definition({
		{
			value_id = "text",
			pass_type = "text",
			visibility_function = is_visible,
			style = {
				font_type = "machine_medium",
				font_size = 24,
				drop_shadow = true,
				text_color = table.clone(COLOR_TEXT),
				default_text_color = table.clone(COLOR_TEXT),
				offset = {
					0,
					10,
					2,
				},
				size = {
					WIDTH,
					26,
				},
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
			},
		},
	}, "hud", {
		text = "",
		visible = false,
	}, {
		WIDTH,
		HEIGHT,
	}),
}

local TidePlayerVolumeHud = class("TidePlayerVolumeHud", "HudElementBase")

TidePlayerVolumeHud.init = function (self, parent, draw_layer, start_scale)
	TidePlayerVolumeHud.super.init(self, parent, draw_layer, start_scale, {
		scenegraph_definition = scenegraph_definition,
		widget_definitions = widget_definitions,
	})

	self._was_visible = nil
	self._last_text = nil
end

TidePlayerVolumeHud.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	TidePlayerVolumeHud.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local visible = mod.volume_toast and mod.volume_toast()

	if self._was_visible ~= visible then
		self._was_visible = visible

		for _, widget in pairs(self._widgets_by_name) do
			widget.content.visible = visible
			widget.dirty = true
		end
	end

	if not visible then
		return
	end

	local text = string.format("VOL %d", mod.volume())

	if text ~= self._last_text then
		self._last_text = text
		self._widgets_by_name.text.content.text = text
	end
end

return TidePlayerVolumeHud
