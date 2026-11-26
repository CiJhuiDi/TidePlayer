-- tide_player_view.lua
-- 收音机面板：左边读数（频率、刻度尺、歌名、进度），右边频道列表，底部方键。
-- 全部 rect + text；状态变化时整体重建（60 来个 widget，代价可忽略）。

local mod = get_mod("TidePlayer")

local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")
local Definitions = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/tide_player_view/tide_player_view_definitions")
local UIWidget = mod:original_require("scripts/managers/ui/ui_widget")
local UISoundEvents = mod:original_require("scripts/settings/ui/ui_sound_events")
local UIWorkspaceSettings = mod:original_require("scripts/settings/ui/ui_workspace_settings")

local LAYOUT = Definitions.layout
local STYLES = Definitions.styles

local ROWS_PER_PAGE = LAYOUT.list_rows
local REFRESH_INTERVAL = 0.2

local COLOR_PANEL = { 255, 14, 18, 13 }
local COLOR_STAGE = { 255, 10, 14, 9 }
local COLOR_LIST = { 255, 17, 22, 14 }
local COLOR_BUTTON = { 255, 36, 46, 32 }
local COLOR_BUTTON_HOVER = { 255, 52, 64, 44 }
local COLOR_ROW_ACTIVE = { 255, 32, 42, 26 }
local COLOR_ROW_HOVER = { 255, 30, 38, 24 }
local COLOR_LINE = { 255, 58, 70, 48 }
local COLOR_TICK = { 255, 60, 72, 50 }
local COLOR_TICK_MAJOR = { 255, 110, 124, 94 }
local COLOR_CURSOR = { 255, 158, 172, 142 }
local COLOR_TRACK_BG = { 255, 24, 30, 22 }
local COLOR_TRACK_FILL = { 255, 148, 164, 128 }

-- 面板按 900×540 的设计稿写坐标，这里统一放大，字号也跟着乘
local UI_SCALE = LAYOUT.scale or 1.2

local function scale_number(value)
	return math.floor((value or 0) * UI_SCALE + 0.5)
end

local function scale_offset(offset)
	return {
		scale_number(offset[1]),
		scale_number(offset[2]),
		offset[3] or 0,
	}
end

local function scale_size(size)
	if not size then
		return nil
	end

	return {
		scale_number(size[1]),
		scale_number(size[2]),
	}
end

local function scale_style(style)
	local copy = table.clone(style)

	if copy.font_size then
		copy.font_size = scale_number(copy.font_size)
	end

	if copy.offset then
		copy.offset = scale_offset(copy.offset)
	end

	if copy.size then
		copy.size = scale_size(copy.size)
	end

	return copy
end

-- 频谱方块：每段 10 个，亮/暗两色
local WAVE_CELLS = 10
local COLOR_WAVE_ON = { 255, 158, 172, 142 }
local COLOR_WAVE_OFF = { 255, 34, 38, 32 }

local TidePlayerView = class("TidePlayerView", "BaseView")

-- ############################## 构件 ##############################

local function button_passes(text_style)
	return {
		{
			content_id = "hotspot",
			pass_type = "hotspot",
		},
		{
			pass_type = "rect",
			style = {
				color = table.clone(COLOR_BUTTON),
			},
			change_function = function (content, style)
				local hotspot = content.hotspot
				local hover = 0

				if hotspot then
					hover = math.max(hotspot.anim_hover_progress or 0, hotspot.anim_input_progress or 0)
				end

				style.color[1] = math.floor(COLOR_BUTTON[1] + hover * (COLOR_BUTTON_HOVER[1] - COLOR_BUTTON[1]))
				style.color[2] = math.floor(COLOR_BUTTON[2] + hover * (COLOR_BUTTON_HOVER[2] - COLOR_BUTTON[2]))
				style.color[3] = math.floor(COLOR_BUTTON[3] + hover * (COLOR_BUTTON_HOVER[3] - COLOR_BUTTON[3]))
				style.color[4] = math.floor(COLOR_BUTTON[4] + hover * (COLOR_BUTTON_HOVER[4] - COLOR_BUTTON[4]))
			end,
		},
		{
			pass_type = "text",
			value_id = "text",
			style = text_style,
		},
	}
end

-- ############################## 生命周期 ##############################

TidePlayerView.init = function (self, settings)
	TidePlayerView.super.init(self, Definitions, settings)

	self._pass_input = true
	self._page = 1
	self._list_mode = "tracks"
	self._cache_open = false
	self._pending_switch = false
	self._close_timer = nil
	self._lyric_active = {}
	self._refresh_timer = 0
	self._built_playlist = nil
	self._built_status = nil
	self._built_index = nil
	self._built_page = nil
end

TidePlayerView.on_enter = function (self)
	-- 居中由 scenegraph 的 alignment 负责（panel 节点的 world_position 已经是居中坐标）
	self:_build_widgets()

	TidePlayerView.super.on_enter(self)
end

-- ############################## widget 基础 ##############################

TidePlayerView._add_widget = function (self, widget)
	self._widgets[#self._widgets + 1] = widget
	self._widgets_by_name[widget.name] = widget

	return widget
end

TidePlayerView._add_rect = function (self, name, offset, size, color, layer)
	local scaled_offset = scale_offset(offset)
	local scaled_size = scale_size(size)

	local definition = UIWidget.create_definition({
		{
			style_id = "rect",
			pass_type = "rect",
			style = {
				color = table.clone(color),
				offset = {
					0,
					0,
					0,
				},
				size = scaled_size,
			},
		},
	}, "panel", nil, scaled_size, nil, {
		offset = scaled_offset,
	})

	local widget = self:_add_widget(UIWidget.init(name, definition))

	widget.offset[3] = layer or 1

	return widget
end

TidePlayerView._add_text = function (self, name, text, offset, style, size, layer)
	local definition = UIWidget.create_definition({
		{
			style_id = "text",
			pass_type = "text",
			value_id = "text",
			style = scale_style(style),
		},
	}, "panel", {
		text = text or "",
	}, scale_size(size), nil, {
		offset = scale_offset(offset),
	})

	local widget = self:_add_widget(UIWidget.init(name, definition))

	widget.offset[3] = layer or 2

	return widget
end

TidePlayerView._add_button = function (self, name, text, offset, size, on_pressed, text_style, layer)
	local definition = UIWidget.create_definition(button_passes(scale_style(text_style or STYLES.button)), "panel", {
		text = text,
	}, scale_size(size), nil, {
		offset = scale_offset(offset),
	})

	local widget = self:_add_widget(UIWidget.init(name, definition))
	local hotspot = widget.content.hotspot

	hotspot.pressed_callback = function ()
		local ok, err = pcall(on_pressed)

		if not ok then
			mod:error("button '%s' failed: %s", name, tostring(err))
		end
	end
	hotspot.on_pressed_sound = UISoundEvents.default_click

	widget.offset[3] = layer or 3

	return widget
end

-- ############################## 构建 ##############################

TidePlayerView._page_count = function (self)
	local playlist = mod.playlist()

	if not playlist then
		return 1
	end

	return math.max(1, math.ceil(#playlist.tracks / ROWS_PER_PAGE))
end

TidePlayerView._build_widgets = function (self)
	local panel_width = LAYOUT.panel_width
	local panel_height = LAYOUT.panel_height
	local playlist = mod.playlist()
	local status = mod.status()
	local index = mod.current_index()

	self._widgets = {}
	self._widgets_by_name = {}
	self._row_widgets = {}
	self._cursor_widget = nil
	self._fill_widget = nil

	self._built_playlist = playlist
	self._built_status = status
	self._built_index = index
	self._built_page = self._page

	-- 缓存页整页替换，避免底层按钮继续接收点击
	if self._cache_open then
		self:_build_cache_page(panel_width, panel_height)

		return
	end

	-- 面板底
	self:_add_rect("panel_bg", { 0, 0, 0 }, { panel_width, panel_height }, COLOR_PANEL, 0)

	-- 顶栏
	self:_add_text("title", mod:localize("view_title"), { LAYOUT.stage_x, LAYOUT.header_y, 2 }, STYLES.title, { 480, LAYOUT.header_h })

	self:_add_button("import", mod:localize("button_import"), { 552, 12, 3 }, { 104, 30 }, function ()
		self:_import_from_clipboard()
	end, STYLES.button, 3)

	self:_add_button("reload", mod:localize("button_reload"), { 664, 12, 3 }, { 88, 30 }, function ()
		self:_reload()
	end, STYLES.button, 3)

	self:_add_button("cache", mod:localize("button_cache"), { 760, 12, 3 }, { 64, 30 }, function ()
		self._cache_open = not self._cache_open
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_button("close", mod:localize("button_close"), { 832, 12, 3 }, { 56, 30 }, function ()
		-- 推迟一帧再关：否则这一下点击的 release 会漏到面板后面的游戏 UI 上
		self._close_timer = 0.08
	end, STYLES.button, 3)

	-- 读数区
	self:_add_rect("stage_bg", { LAYOUT.stage_x, LAYOUT.stage_y, 1 }, { LAYOUT.stage_w, LAYOUT.stage_h }, COLOR_STAGE, 1)
	self:_add_rect("stage_top_line", { LAYOUT.stage_x, LAYOUT.stage_y, 2 }, { LAYOUT.stage_w, 1 }, COLOR_LINE, 2)

	-- 频谱：24 段，每段 6 个小方块，点到哪块亮到哪块（LED 柱）
	local ruler_x = LAYOUT.stage_x + 20
	local baseline = LAYOUT.wave_y

	self._wave_cells = {}
	self._wave_lit = {}
	self._wave_timer = 0

	for i = 1, LAYOUT.ruler_count do
		local cells = {}

		for j = 1, WAVE_CELLS do
			cells[j] = self:_add_rect(
				"wave_" .. i .. "_" .. j,
				{ ruler_x + (i - 1) * LAYOUT.ruler_step + 7, baseline - j * 7, 2 },
				{ 6, 5 },
				COLOR_WAVE_OFF,
				2
			)
		end

		self._wave_cells[i] = cells
		self._wave_lit[i] = 0
	end

	-- 歌名 / 歌手
	local stage_inner = LAYOUT.stage_w - 40

	self:_add_text("song", mod:localize("status_empty_song"), { LAYOUT.stage_x + 20, LAYOUT.song_y - 20, 2 }, STYLES.song, { stage_inner, LAYOUT.song_h })
	self:_add_text("artist", "", { LAYOUT.stage_x + 20, LAYOUT.artist_y - 20, 2 }, STYLES.artist, { stage_inner, 24 })

	-- 歌词区：5 行，中间一行是当前行
	for i = 1, 5 do
		local style = table.clone(i == 3 and STYLES.lyric or STYLES.lyric_next)

		self:_add_text("lyric_" .. i, "", { LAYOUT.stage_x + 20, 166 + (i - 1) * 22, 2 }, style, { stage_inner, 20 })
	end

	-- 时间 / 进度条
	self:_add_text("pos", "0:00", { LAYOUT.stage_x + 20, LAYOUT.progress_y - 22, 2 }, STYLES.time, { 100, 18 })
	self:_add_text("dur", "", { LAYOUT.stage_x + LAYOUT.stage_w - 120, LAYOUT.progress_y - 22, 2 }, STYLES.time, { 100, 18 })

	self:_add_rect("progress_bg", { LAYOUT.stage_x + 20, LAYOUT.progress_y, 2 }, { stage_inner, LAYOUT.progress_h }, COLOR_TRACK_BG, 2)
	self._fill_widget = self:_add_rect("progress_fill", { LAYOUT.stage_x + 20, LAYOUT.progress_y, 3 }, { 0, LAYOUT.progress_h }, COLOR_TRACK_FILL, 3)

	-- 频道列表
	-- 右栏：频道 / 歌单
	self:_add_rect("list_bg", { LAYOUT.list_x, LAYOUT.list_y, 1 }, { LAYOUT.list_w, LAYOUT.list_h }, COLOR_LIST, 1)
	self:_add_rect("list_left_line", { LAYOUT.list_x, LAYOUT.list_y, 2 }, { 1, LAYOUT.list_h }, COLOR_LINE, 2)

	local list_mode = self._list_mode or "tracks"

	self:_add_button("tab_tracks", mod:localize("tab_tracks"), { LAYOUT.list_x + 10, LAYOUT.list_y + 8, 3 }, { 74, 24 }, function ()
		self._list_mode = "tracks"
		self:_rebuild()
	end, list_mode == "tracks" and STYLES.button_active or STYLES.button, 3)

	self:_add_button("tab_playlists", mod:localize("tab_playlists"), { LAYOUT.list_x + 90, LAYOUT.list_y + 8, 3 }, { 74, 24 }, function ()
		self._list_mode = "playlists"
		self:_rebuild()
	end, list_mode == "playlists" and STYLES.button_active or STYLES.button, 3)

	self:_add_text("list_head", mod:localize(list_mode == "tracks" and "list_head_tracks" or "list_head_playlists"), { LAYOUT.list_x + 12, LAYOUT.list_y + 40, 2 }, STYLES.label, { 220, 16 })
	self:_add_text("list_count", "", { LAYOUT.list_x + LAYOUT.list_w - 80, LAYOUT.list_y + 40, 2 }, STYLES.label, { 68, 16 })

	if list_mode == "tracks" then
		local first = (self._page - 1) * ROWS_PER_PAGE + 1
		local last = playlist and math.min(first + ROWS_PER_PAGE - 1, #playlist.tracks) or 0

		for i = first, last do
			local song = playlist.tracks[i]
			local active = i == index
			local offset = {
				LAYOUT.list_x,
				LAYOUT.list_y + LAYOUT.list_row_y + (i - first) * LAYOUT.list_row_h,
				2,
			}
			local row_num_style = scale_style(table.clone(STYLES.row_num))
			row_num_style.offset = scale_offset({ 12, 0, 0 })
			row_num_style.size = scale_size({ 24, LAYOUT.list_row_h })

			local row_freq_style = scale_style(table.clone(STYLES.row_freq))
			row_freq_style.offset = scale_offset({ 40, 0, 0 })
			row_freq_style.size = scale_size({ 44, LAYOUT.list_row_h })

			local row_name_style = scale_style(table.clone(active and STYLES.row_active or STYLES.row))
			row_name_style.offset = scale_offset({ 92, 0, 0 })
			row_name_style.size = scale_size({ LAYOUT.list_w - 104, LAYOUT.list_row_h })

			local definition = UIWidget.create_definition({
				{
					content_id = "hotspot",
					pass_type = "hotspot",
				},
				{
					pass_type = "rect",
					style = {
						color = table.clone(active and COLOR_ROW_ACTIVE or { 0, 0, 0, 0 }),
					},
				},
				{
					style_id = "num",
					value_id = "num",
					pass_type = "text",
					style = row_num_style,
				},
				{
					style_id = "freq",
					value_id = "freq",
					pass_type = "text",
					style = row_freq_style,
				},
				{
					style_id = "name",
					value_id = "name",
					pass_type = "text",
					style = row_name_style,
				},
			}, "panel", {
				num = string.format("%02d", i),
				freq = string.format("%.1f", 87 + ((i - 1) * 1.37) % 21),
				name = Util.clip(song.name or "?", 26),
			}, scale_size({
				LAYOUT.list_w,
				LAYOUT.list_row_h,
			}), nil, {
				offset = scale_offset(offset),
			})

			local widget = self:_add_widget(UIWidget.init("row_" .. i, definition))

			widget.offset[3] = 2

			widget.content.hotspot.pressed_callback = function ()
				mod.play_index(i)
				self:_rebuild()
			end
			widget.content.hotspot.on_pressed_sound = UISoundEvents.default_click

			self._row_widgets[#self._row_widgets + 1] = widget
		end

		local page_y = LAYOUT.list_y + LAYOUT.list_row_y + ROWS_PER_PAGE * LAYOUT.list_row_h + 6

		self:_add_button("page_prev", "<", { LAYOUT.list_x + 8, page_y, 3 }, { 52, 32 }, function ()
			if self._page > 1 then
				self._page = self._page - 1
				self:_rebuild()
			end
		end, STYLES.button, 3)

		self:_add_button("page_next", ">", { LAYOUT.list_x + LAYOUT.list_w - 60, page_y, 3 }, { 52, 32 }, function ()
			if self._page < self:_page_count() then
				self._page = self._page + 1
				self:_rebuild()
			end
		end, STYLES.button, 3)

		self:_add_text("page_label", "", { LAYOUT.list_x + 60, page_y, 2 }, STYLES.label, { LAYOUT.list_w - 120, 32 })
		self._widgets_by_name.page_label.style.text.text_horizontal_alignment = "center"
	else
		local saved = mod.playlists() or {}
		local count = math.min(#saved, ROWS_PER_PAGE)

		if count == 0 then
			self:_add_text("pl_empty", mod:localize("playlists_empty"), { LAYOUT.list_x + 12, LAYOUT.list_y + LAYOUT.list_row_y, 2 }, STYLES.label, { LAYOUT.list_w - 24, 60 })
		end

		for i = 1, count do
			local entry = saved[i]
			local y = LAYOUT.list_y + LAYOUT.list_row_y + (i - 1) * LAYOUT.list_row_h

			self:_add_button("pl_" .. i, Util.clip(entry.name or "?", 16) .. "  " .. tostring(entry.count or 0), { LAYOUT.list_x + 8, y, 3 }, { LAYOUT.list_w - 56, LAYOUT.list_row_h - 2 }, function ()
				mod.switch_playlist(entry.url)

				-- 停在歌单页等加载，完成后 update 里再切回频道页
				self._pending_switch = true
				self:_rebuild()
			end, STYLES.row, 3)

			self:_add_button("pl_del_" .. i, "x", { LAYOUT.list_x + LAYOUT.list_w - 44, y, 3 }, { 36, LAYOUT.list_row_h - 2 }, function ()
				mod.remove_playlist(entry.id)
				self:_rebuild()
			end, STYLES.button, 3)
		end
	end

	-- 底部控制
	local y = LAYOUT.controls_y
	local h = LAYOUT.controls_h

	self:_add_button("ctrl_prev", mod:localize("button_prev"), { 16, y, 3 }, { 84, h }, function ()
		mod.previous_track()
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_button("ctrl_play", mod:localize("button_play"), { 108, y, 3 }, { 84, h }, function ()
		mod.toggle_play()
		self:_rebuild()
	end, STYLES.button_active, 3)

	self:_add_button("ctrl_next", mod:localize("button_next"), { 200, y, 3 }, { 84, h }, function ()
		mod.next_track()
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_button("ctrl_stop", mod:localize("button_stop"), { 292, y, 3 }, { 84, h }, function ()
		mod.stop()
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_text("vol", "", { 500, y, 2 }, STYLES.label, { 120, h })
	self._widgets_by_name.vol.style.text.text_horizontal_alignment = "right"

	self:_add_button("ctrl_vol_down", mod:localize("button_volume_down"), { 636, y, 3 }, { 76, h }, function ()
		mod.adjust_volume(-5)
		self:_refresh_dynamic()
	end, STYLES.button, 3)

	self:_add_button("ctrl_vol_up", mod:localize("button_volume_up"), { 720, y, 3 }, { 76, h }, function ()
		mod.adjust_volume(5)
		self:_refresh_dynamic()
	end, STYLES.button, 3)

	self:_add_button("ctrl_loop", mod:localize("loop_order"), { 804, y, 3 }, { 80, h }, function ()
		mod.cycle_loop_mode()
		self:_refresh_dynamic()
	end, STYLES.button, 3)

	-- 底部状态行
	self:_add_text("status", "", { 16, LAYOUT.controls_y + h + 8, 2 }, STYLES.status, { panel_width - 32, 20 })

	self:_add_border(panel_width, panel_height)

	self:_refresh_dynamic()
end

-- 缓存页：整页画，不叠在主界面上——叠覆盖层时底层按钮还会吃点击
TidePlayerView._build_cache_page = function (self, panel_width, panel_height)
	self:_add_rect("cache_bg", { 0, 0, 0 }, { panel_width, panel_height }, COLOR_PANEL, 0)
	self:_add_rect("cache_top_line", { 0, 0, 1 }, { panel_width, 1 }, COLOR_LINE, 1)

	self:_add_text("cache_title", mod:localize("cache_title"), { 24, 18, 2 }, STYLES.title, { 500, 30 })

	local stats = mod.cache_stats()
	local dir = Util.cache_dir()

	if stats.count > 0 then
		self:_add_text("cache_songs", mod:localize("cache_songs", tostring(stats.songs), Util.format_size(stats.song_bytes)), { 24, 82, 2 }, STYLES.artist, { panel_width - 48, 24 })
		self:_add_text("cache_files", mod:localize("cache_files", tostring(stats.count), Util.format_size(stats.total)), { 24, 112, 2 }, STYLES.lyric_next, { panel_width - 48, 22 })
	else
		self:_add_text("cache_songs", mod:localize("cache_empty"), { 24, 82, 2 }, STYLES.artist, { panel_width - 48, 24 })
	end

	self:_add_text("cache_path", dir, { 24, 156, 2 }, STYLES.lyric_next, { panel_width - 48, 20 })

	self:_add_button("cache_clear", mod:localize("button_clear_cache"), { 24, panel_height - 62, 3 }, { 150, 36 }, function ()
		mod.clear_cache()
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_button("cache_close", mod:localize("button_close"), { 190, panel_height - 62, 3 }, { 150, 36 }, function ()
		self._cache_open = false
		self:_rebuild()
	end, STYLES.button, 3)

	self:_add_border(panel_width, panel_height)
end

TidePlayerView._add_border = function (self, panel_width, panel_height)
	self:_add_rect("border_top", { 0, 0, 20 }, { panel_width, 1 }, COLOR_LINE, 20)
	self:_add_rect("border_bottom", { 0, panel_height - 1, 20 }, { panel_width, 1 }, COLOR_LINE, 20)
	self:_add_rect("border_left", { 0, 0, 20 }, { 1, panel_height }, COLOR_LINE, 20)
	self:_add_rect("border_right", { panel_width - 1, 0, 20 }, { 1, panel_height }, COLOR_LINE, 20)
end

TidePlayerView._rebuild = function (self)
	self:_build_widgets()
end

-- ############################## 刷新 ##############################

TidePlayerView._refresh_dynamic = function (self)
	local playlist = mod.playlist()
	local song = mod.current_song()
	local status = mod.status()
	local ratio, position, length = mod.progress()
	local page = self._page or 1
	local page_count = self:_page_count()

	-- 时间 / 进度条
	self:_set_text("pos", mod.format_time(position or 0))
	self:_set_text("dur", mod.format_time(length or (song and song.duration) or 0))

	local ruler_start = LAYOUT.stage_x + LAYOUT.ruler_x - 20
	local stage_inner = LAYOUT.stage_w - 40

	if self._fill_widget then
		self._fill_widget.style.rect.size[1] = math.floor(stage_inner * math.max(0, math.min(1, ratio or 0)))
		self._fill_widget.dirty = true
	end

	-- 歌名 / 歌手 / 歌词
	if song then
		self:_set_text("song", Util.clip(song.name or "?", 26))
		self:_set_text("artist", song.artists or "?")
	else
		self:_set_text("song", mod:localize("status_empty_song"))
		self:_set_text("artist", "")
	end

	local window = mod.lyric_window and mod.lyric_window(5) or {}

	for i = 1, 5 do
		local widget = self._widgets_by_name["lyric_" .. i]
		local line = window[i]

		if widget then
			local text = (line and line.text ~= "" and Util.clip_width(line.text, 29)) or ""

			if widget.content.text ~= text then
				widget.content.text = text
				widget.dirty = true
			end

			local active = line ~= nil and line.offset == 0

			if self._lyric_active[i] ~= active then
				self._lyric_active[i] = active
				widget.style.text.text_color = active and { 255, 226, 220, 198 } or { 255, 118, 128, 106 }
				widget.dirty = true
			end
		end
	end

	local status_text

	if status == "loading" then
		local buffering = mod.buffering_song()

		status_text = buffering and mod:localize("status_buffering", buffering.name) or mod:localize("status_loading")
	elseif status == "error" then
		status_text = mod:localize("status_error") .. "  " .. tostring(mod.error_message() or "")
	elseif status == "playing" and song then
		status_text = mod:localize("status_fm", song.name, tostring(mod.volume()))
	elseif status == "paused" and song then
		status_text = mod:localize("status_fm_paused", song.name, tostring(mod.volume()))
	else
		status_text = mod:localize("status_standby", tostring(mod.volume()))
	end

	self:_set_text("status", status_text)

	if (self._list_mode or "tracks") == "tracks" then
		self:_set_text("list_count", string.format("%02d / %02d", page, page_count))
		self:_set_text("page_label", mod:localize("page_label", tostring(page), tostring(page_count)))
	else
		self:_set_text("list_count", tostring(#(mod.playlists() or {})))
	end

	-- 播放按钮文案
	local play_widget = self._widgets_by_name.ctrl_play

	if play_widget then
		play_widget.content.text = (status == "playing") and mod:localize("button_pause") or mod:localize("button_play")
	end

	-- 循环按钮文案
	local loop_widget = self._widgets_by_name.ctrl_loop

	if loop_widget then
		local mode = mod.loop_mode()
		local key = "loop_order"

		if mode == "single" then
			key = "loop_single"
		elseif mode == "shuffle" then
			key = "loop_shuffle"
		end

		loop_widget.content.text = mod:localize(key)
	end

	-- 音量
	self:_set_text("vol", string.format("VOL %d", mod.volume()))
end

TidePlayerView._set_text = function (self, name, text)
	local widget = self._widgets_by_name and self._widgets_by_name[name]

	if widget and widget.content.text ~= text then
		widget.content.text = text or ""
		widget.dirty = true
	end
end

-- ############################## 动作 ##############################

TidePlayerView._import_from_clipboard = function (self)
	local text = mod.clipboard_text()

	if not text or text == "" then
		mod:echo(mod:localize("clipboard_empty"))

		return
	end

	if not mod.load_playlist(text) then
		mod:echo(mod:localize("error_no_link"))
	end

	self:_rebuild()
end

TidePlayerView._reload = function (self)
	local url = mod.last_url()

	if not url or url == "" then
		self:_import_from_clipboard()

		return
	end

	mod.load_playlist(url)
	self:_rebuild()
end

-- ############################## update ##############################

-- 频谱：每 40ms 取一次 24 个频段的能量，点亮对应数量的方块
TidePlayerView._update_wave = function (self, dt)
	if not self._wave_cells then
		return
	end

	self._wave_timer = (self._wave_timer or 0) + (dt or 0)

	if self._wave_timer < 0.04 then
		return
	end

	self._wave_timer = 0

	local spectrum = mod.spectrum()

	if not spectrum then
		return
	end

	for i = 1, LAYOUT.ruler_count do
		local value = tonumber(spectrum[i - 1]) or 0
		local lit = math.floor(value / 1000 * WAVE_CELLS)

		if self._wave_lit[i] ~= lit then
			self._wave_lit[i] = lit

			local cells = self._wave_cells[i]

			for j = 1, WAVE_CELLS do
				local cell = cells[j]

				if cell then
					cell.style.rect.color = table.clone(j <= lit and COLOR_WAVE_ON or COLOR_WAVE_OFF)
					cell.dirty = true
				end
			end
		end
	end
end

TidePlayerView.update = function (self, dt, t, input_service)
	self:_update_wave(dt)

	if self._close_timer then
		self._close_timer = self._close_timer - (dt or 0)

		if self._close_timer <= 0 then
			self._close_timer = nil
			mod.close_view()
		end
	end

	-- 点了歌单：等它加载完（playlist 换新）再自动回频道页
	if self._pending_switch then
		local playlist = mod.playlist()
		local status = mod.status()

		if playlist ~= self._built_playlist and status ~= "loading" then
			self._pending_switch = false
			self._list_mode = "tracks"
			self:_rebuild()

			return TidePlayerView.super.update(self, dt, t, input_service)
		elseif status == "error" then
			self._pending_switch = false
			self:_rebuild()

			return TidePlayerView.super.update(self, dt, t, input_service)
		end
	end

	self._refresh_timer = (self._refresh_timer or 0) + (dt or 0)

	if self._refresh_timer >= REFRESH_INTERVAL then
		self._refresh_timer = 0

		local playlist = mod.playlist()
		local status = mod.status()
		local index = mod.current_index()

		if playlist ~= self._built_playlist or status ~= self._built_status or index ~= self._built_index then
			self:_rebuild()
		else
			self:_refresh_dynamic()
		end
	end

	return TidePlayerView.super.update(self, dt, t, input_service)
end

return TidePlayerView
