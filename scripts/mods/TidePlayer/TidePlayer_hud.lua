-- TidePlayer_hud.lua
-- 播放时挂在右上角任务目标下面的一条迷你 HUD。
--
-- 视觉照抄原游戏的 HudElementMissionObjectiveFeed：
--   * 背景是 terminal_background_weapon 渐变 + 右缘 4px 竖线
--   * 图标走 objectives/bonus，颜色 color_tint_main_1
--   * 文字用 hud_body 字体（machine_medium）
--   * 进度条是 default_square 材质 + scale 控长度，不是改 size
-- 位置默认 y=280，正好落在任务目标列表（从 y=50 起，每条 40）下方。

local mod = get_mod("TidePlayer")
local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")

require("scripts/ui/hud/elements/hud_element_base")

local WIDTH = 460
local HEIGHT = 58
-- 和原生任务目标条目对齐：图标占 10(offset) + 32(icon) + 10(side)，
-- 文字和进度条都从这条线开始，才和上面几行的文字列对得上。
local SIDE_OFFSET = 10
local TEXT_LEFT = 10 + 32 + 10
local BAR_HEIGHT = 3
local BAR_WIDTH = WIDTH - TEXT_LEFT - SIDE_OFFSET

local COLOR_BACKGROUND = Color.terminal_background_gradient(255, true)
local COLOR_EDGE = Color.terminal_corner_hover(nil, true)
local COLOR_TEXT = UIHudSettings.color_tint_main_1
local COLOR_ICON_PAUSED = { 150, 201, 161, 90 }
local COLOR_MUTED = UIHudSettings.color_tint_4
local COLOR_BAR_BACKGROUND = UIHudSettings.color_tint_0
local COLOR_BAR = UIHudSettings.color_tint_main_1

local FONT_TYPE = "machine_medium"

-- 长歌名滚动：按视觉宽度铺满标题区（19 个全角宽），每 0.12 秒走一格
local TITLE_UNITS = 19
local SCROLL_INTERVAL = 0.12
local SCROLL_GAP = 4

local function build_chars(text)
	local chars = {}
	local widths = {}

	for ch in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do
		local first = string.byte(ch, 1)
		-- 三/四字节的 UTF-8 当全角，一/两字节当半角
		local width = (first and first >= 0xE0) and 1 or 0.5

		chars[#chars + 1] = ch
		widths[#widths + 1] = width
	end

	return chars, widths
end

local function scroll_text(chars, widths, offset)
	local count = #chars

	if count == 0 then
		return ""
	end

	local out = {}
	local used = 0
	local index = offset

	while used < TITLE_UNITS do
		local slot = index % (count + SCROLL_GAP) + 1
		local ch = " "
		local width = 0.5

		if slot <= count then
			ch = chars[slot]
			width = widths[slot]
		end

		if used + width > TITLE_UNITS then
			break
		end

		out[#out + 1] = ch
		used = used + width
		index = index + 1
	end

	return table.concat(out)
end

local function is_visible(content)
	return content.visible == true
end

local function text_style(font_size, color, offset, size)
	return {
		font_type = FONT_TYPE,
		font_size = font_size,
		drop_shadow = true,
		text_color = table.clone(color),
		default_text_color = table.clone(color),
		offset = offset,
		size = size,
		text_horizontal_alignment = "left",
		text_vertical_alignment = "center",
	}
end

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	hud = {
		parent = "screen",
		scale = "fit",
		vertical_alignment = "top",
		horizontal_alignment = "right",
		size = {
			WIDTH,
			HEIGHT,
		},
		position = {
			-50,
			50,
			100,
		},
	},
}

local widget_definitions = {
	background = UIWidget.create_definition({
		{
			style_id = "background",
			pass_type = "texture",
			value = "content/ui/materials/hud/backgrounds/terminal_background_weapon",
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
				color = Color.terminal_background_gradient(255, true),
			},
		},
		{
			style_id = "edge",
			pass_type = "texture",
			value = "content/ui/materials/backgrounds/default_square",
			visibility_function = is_visible,
			style = {
				horizontal_alignment = "right",
				vertical_alignment = "top",
				size = {
					4,
					HEIGHT,
				},
				offset = {
					0,
					0,
					1,
				},
				color = Color.terminal_corner_hover(nil, true),
			},
		},
	}, "hud", {
		visible = false,
	}),

	-- 进度遮罩：从左边铺满已播放部分，叠在背景之上、文字之下
	progress_mask = UIWidget.create_definition({
		{
			style_id = "mask",
			pass_type = "texture",
			value = "content/ui/materials/backgrounds/default_square",
			visibility_function = is_visible,
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					WIDTH,
					HEIGHT,
				},
				offset = {
					0,
					0,
					1,
				},
				color = {
					80,
					196,
					52,
					40,
				},
				scale = {
					0,
					1,
				},
			},
		},
	}, "hud", {
		visible = false,
	}),

	-- 图标列：和原生任务目标条目同一个位置（x=10，32×32）。
	-- radio 是暗潮里的收音机图标，比 objectives/bonus 的菱形更贴播放器，也不会撞次要目标。
	-- 播放/暂停靠图标明暗区分，不再额外放 > / II 符号（会跟图标叠在一起）。
	icon = UIWidget.create_definition({
		{
			style_id = "icon",
			pass_type = "texture",
			value = "content/ui/materials/icons/hud/radio",
			visibility_function = is_visible,
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "center",
				size = {
					32,
					32,
				},
				offset = {
					10,
					0,
					6,
				},
				color = COLOR_TEXT,
			},
		},
	}, "hud", {
		visible = false,
	}),

	title = UIWidget.create_definition({
		{
			value_id = "title",
			pass_type = "text",
			visibility_function = is_visible,
			style = text_style(20, COLOR_TEXT, { TEXT_LEFT, 2, 6 }, { BAR_WIDTH, 22 }),
		},
	}, "hud", {
		title = "",
		visible = false,
	}),
}

-- 频谱条：替代进度条，24 个频段，从文字列开始，底部对齐向上长
local WAVE_COUNT = 24
local WAVE_X = 52
local WAVE_STEP = 16
local WAVE_BAR_W = 4
local WAVE_BASE = 56

for i = 1, WAVE_COUNT do
	widget_definitions["wave_" .. i] = UIWidget.create_definition({
		{
			style_id = "rect",
			pass_type = "rect",
			visibility_function = is_visible,
			style = {
				color = table.clone(COLOR_BAR),
				offset = {
					0,
					0,
					0,
				},
				size = {
					WAVE_BAR_W,
					2,
				},
			},
		},
	}, "hud", {
		visible = false,
	}, nil, nil, {
		offset = {
			WAVE_X + (i - 1) * WAVE_STEP,
			WAVE_BASE - 2,
			6,
		},
	})
end

local TidePlayerHud = class("TidePlayerHud", "HudElementBase")

-- 每个 widget 都必须带 size：UIWidget 的 pass 做 "center/right" 这类对齐时要读
-- content.size，缺了它对齐会退化成屏幕中心（之前图标就是这么跑到中央的）。
for _, definition in pairs(widget_definitions) do
	definition.size = {
		WIDTH,
		HEIGHT,
	}
end

-- 目标列表最后一条的底部（屏幕坐标，从上往下）。
-- 用目标列表背景的实际高度（_align_objective_widgets 里算出来的总高），
-- 它比逐个 widget 加高度更贴边——widget 的 content.size 里还含条目内边距。
-- 没有条目时返回任务目标 HUD 自己的起点，让迷你 HUD 顶替它的位置。
local function objective_anchor()
	local ui = Managers.ui
	local hud = ui and ui._hud
	local feed = hud and hud.element and hud:element("HudElementMissionObjectiveFeed")

	if not feed then
		return nil, false
	end

	local scenegraph = feed._ui_scenegraph
	local area = scenegraph and scenegraph.area
	local background = scenegraph and scenegraph.background

	if not area then
		return nil, false
	end

	local base_y = (area.position and area.position[2]) or 50

	if background and background.position then
		base_y = base_y + background.position[2]
	end

	local height = background and background.size and background.size[2] or 0

	if height and height > 0 and feed._objective_widgets_counter and feed._objective_widgets_counter > 0 then
		return base_y + height, true
	end

	-- 没有条目：待在任务目标 HUD 的起点
	return base_y, false
end

TidePlayerHud.init = function (self, parent, draw_layer, start_scale)
	TidePlayerHud.super.init(self, parent, draw_layer, start_scale, {
		scenegraph_definition = scenegraph_definition,
		widget_definitions = widget_definitions,
	})

	self._last_paused = nil
	self._last_title = nil
	self._last_subtitle = nil
	self._was_visible = nil

	self._title_chars = nil
	self._title_for = nil
	self._title_scroll = 0
	self._title_tick = 0

	self._wave_widgets = {}
	self._wave_timer = 0

	for i = 1, WAVE_COUNT do
		self._wave_widgets[i] = self._widgets_by_name["wave_" .. i]
	end
end

local function set_visible(self, visible)
	if self._was_visible == visible then
		return
	end

	for name, widget in pairs(self._widgets_by_name) do
		widget.content.visible = visible
		widget.dirty = true
	end

	self._was_visible = visible
end

TidePlayerHud.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	TidePlayerHud.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local playlist = mod.playlist()
	local song = mod.current_song()
	local status = mod.status()
	local enabled = mod:get("hud_enabled") ~= false
	local playing = status == "playing" or status == "paused"

	local visible = enabled and playlist ~= nil and song ~= nil and playing

	if not visible then
		set_visible(self, false)

		return
	end

	set_visible(self, true)

	-- 跟着任务目标列表走：挂在最后一条下面，加一个用户可调的额外下移。
	-- 没有目标任务时顶替任务目标 HUD 的位置，连目标 HUD 都没有时退回 50。
	--
	-- 注意：HudElementBase 的 draw 只在 _update_scenegraph 为真时才重算
	-- scenegraph 的 world position。光改 position 不动这个标志，画面上会
	-- 一直停在初始化时的位置。
	local container = self._ui_scenegraph and self._ui_scenegraph.hud

	if container and container.position then
		local extra = tonumber(mod:get("hud_extra_offset")) or 8
		local anchor, has_objectives = objective_anchor()
		local target_y = (anchor or 50) + (has_objectives and extra or 0)

		if container.position[2] ~= target_y then
			container.position[2] = target_y
			self._update_scenegraph = true
		end
	end

	local paused = status == "paused"
	local song_name = song and song.name or "?"

	if self._title_for ~= song_name then
		self._title_for = song_name
		self._title_chars, self._title_widths = build_chars(song_name)
		self._title_scroll = 0
		self._title_tick = 0

		local total = 0

		for i = 1, #self._title_widths do
			total = total + self._title_widths[i]
		end

		self._title_width = total
	end

	local title

	if self._title_width and self._title_width > TITLE_UNITS then
		local interval = tonumber(mod:get("hud_scroll_speed")) or SCROLL_INTERVAL

		if interval <= 0 then
			interval = SCROLL_INTERVAL
		end

		self._title_tick = self._title_tick + (dt or 0)

		if self._title_tick >= interval then
			self._title_tick = 0
			self._title_scroll = (self._title_scroll + 1) % (#self._title_chars + SCROLL_GAP)
		end

		title = scroll_text(self._title_chars, self._title_widths, self._title_scroll)
	else
		title = song_name
	end

	if paused ~= self._last_paused then
		self._last_paused = paused

		local icon = self._widgets_by_name.icon
		local color = paused and COLOR_ICON_PAUSED or COLOR_TEXT

		icon.style.icon.color = table.clone(color)
		icon.dirty = true
	end

	if title ~= self._last_title then
		self._last_title = title
		self._widgets_by_name.title.content.title = title
	end

	-- 进度遮罩：按播放比例从左铺满，颜色固定
	local ratio = mod.progress()
	local mask = self._widgets_by_name.progress_mask

	if mask then
		mask.style.mask.scale[1] = math.max(0, math.min(1, ratio or 0))
		mask.dirty = true
	end

	-- 频谱：每 40ms 取一次 24 个频段，底部对齐向上长
	self._wave_timer = (self._wave_timer or 0) + (dt or 0)

	if self._wave_timer >= 0.04 then
		self._wave_timer = 0

		local spectrum = mod.spectrum()

		if spectrum then
			for i = 1, WAVE_COUNT do
				local widget = self._wave_widgets[i]

				if widget then
					local value = tonumber(spectrum[i - 1]) or 0
					local height = 2 + math.floor(value * 0.026)

					widget.offset[2] = WAVE_BASE - height
					widget.style.rect.size[2] = height
					widget.dirty = true
				end
			end
		end
	end
end

return TidePlayerHud
