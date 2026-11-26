-- TidePlayer.lua
-- 暗潮点歌台：把网易云歌单搬进游戏里，按 F9 开面板，点一首就放。
--
-- 播放流程：选中歌 → 用隐藏窗口的 curl 把 mp3 下到 cache（第一次）→
-- tide_audio.dll 解码 + waveOut 播放。不依赖 Audio Plugin / ffplay。

local mod = get_mod("TidePlayer")

local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")
local Audio = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_audio")
local Net = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_net")
local Playlist = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_playlist")
local Playlists = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_playlists")

local VIEW_NAME = "tide_player_view"
local MUSIC_VOLUME_PARAMETER = "options_music_slider"
local DEFAULT_MUSIC_VOLUME = 100
local DUCK_SPEED = 1.2 -- 每秒推进量，1.0 约等于一秒压完
local STATUS_POLL_INTERVAL = 0.25
local MIN_MP3_BYTES = 100 * 1024

-- ############################## 状态 ##############################

local _playlist = nil
local _index = 0 -- 0 = 还没选歌
local _status = "idle" -- idle / loading / playing / paused / error
local _error = nil
local _volume = 70
local _loop_mode = "order" -- order / single / shuffle
local _duck = 0
local _duck_target = 0
local _game_backup = nil
local _applied_game = nil
local _poll_timer = 0
local _last_mode = nil
local _load_token = 0
local _pending_index = nil -- 正在下载/准备的那一首
local _start_song = nil
local _volume_toast_until = 0

-- 歌词：当前曲目的行，按 id 缓存
local _lyric = {}
local _lyric_song_id = nil
local _lyric_cache = {}

local function load_lyric(song)
	if not song then
		return
	end

	if _lyric_song_id == song.id then
		return
	end

	_lyric_song_id = song.id
	_lyric = _lyric_cache[song.id] or {}

	if _lyric_cache[song.id] then
		return
	end

	Playlist.fetch_lyric(song.id, function (lines)
		if _lyric_song_id ~= song.id then
			return
		end

		_lyric = lines or {}
		_lyric_cache[song.id] = _lyric
	end)
end

local function now()
	local time_manager = Managers and Managers.time

	return time_manager and time_manager:time("main") or os.clock()
end

local function clamp(value, min_value, max_value)
	if value < min_value then
		return min_value
	elseif value > max_value then
		return max_value
	end

	return value
end

local LOAD_ERROR_KEYS = {
	empty = "error_link_nourl",
	no_url = "error_link_nourl",
	unsupported_url = "error_link_unsupported",
	short_no_id = "error_load_short",
}

local function load_error_text(err)
	local code = tostring(err or "unknown")
	local key = LOAD_ERROR_KEYS[code]

	if not key then
		if string.find(code, "fetch_failed", 1, true) or string.find(code, "short_failed", 1, true) then
			key = "error_load_fetch"
		elseif string.find(code, "bad_json", 1, true) then
			key = "error_load_json"
		elseif code == "no_result" or code == "empty_tracks" then
			key = "error_load_empty"
		else
			key = "error_load_unknown"
		end
	end

	return mod:localize(key)
end

-- ############################## 文件缓存 ##############################

local function song_cache_path(song)
	return Util.cache_dir() .. "song_" .. tostring(song.id) .. ".mp3"
end

-- 上次用的歌单链接存在文件里：强杀进程时 DMF 的内存设置可能来不及落盘，
-- 而读文件不受这个影响。
local function load_last_url()
	local text = Util.read_file(Util.cache_dir() .. "last_url.txt")

	return Util.trim(text or "")
end

local function save_last_url(text)
	Util.write_file(Util.cache_dir() .. "last_url.txt", text or "")
end

-- 小于 100KB 或者头不是 ID3 / mp3 帧同步的，都当坏缓存删掉重下
-- （网易云对无版权的歌会回一个 200 的 404 HTML 页面）
local function cache_file_ok(path)
	local size = Util.file_size(path)

	if not size or size < MIN_MP3_BYTES then
		return false
	end

	local head = Util.read_head(path, 3)

	if not head or #head < 3 then
		return false
	end

	local first = string.byte(head, 1)

	return head == "ID3" or first == 0xFF
end

-- ############################## 游戏音乐压低 ##############################

local function game_music_volume()
	local value = Application.user_setting("sound_settings", MUSIC_VOLUME_PARAMETER)

	return tonumber(value) or DEFAULT_MUSIC_VOLUME
end

local function apply_duck(force)
	if not _game_backup then
		return
	end

	local value = math.floor(_game_backup * (1 - _duck) + 0.5)

	if force or value ~= _applied_game then
		Wwise.set_parameter(MUSIC_VOLUME_PARAMETER, value)
		_applied_game = value
	end
end

local function begin_duck()
	if not mod:get("duck_game_music") then
		return
	end

	if not _game_backup then
		_game_backup = game_music_volume()
		_applied_game = _game_backup
	end

	_duck_target = 1
end

local function end_duck()
	_duck_target = 0
end

local function update_duck(dt)
	if _duck == _duck_target then
		return
	end

	local step = (dt or 0) * DUCK_SPEED

	if _duck < _duck_target then
		_duck = math.min(_duck_target, _duck + step)
	else
		_duck = math.max(_duck_target, _duck - step)
	end

	apply_duck(false)

	if _duck == 0 and _game_backup then
		Wwise.set_parameter(MUSIC_VOLUME_PARAMETER, _game_backup)

		_game_backup = nil
		_applied_game = nil
	end
end

-- ############################## 播放 ##############################

local function current_song()
	if not _playlist or _index < 1 then
		return nil
	end

	return _playlist.tracks[_index]
end

local function set_status(status, err)
	_status = status
	_error = err or nil
end

local function fail_current(index, tried)
	local count = _playlist and #_playlist.tracks or 0

	tried = tried or 0

	if count > 0 and tried < count - 1 then
		return _start_song(index % count + 1, tried + 1)
	end

	local song = _playlist and _playlist.tracks[index]

	set_status("error", mod:localize("error_play", tostring(song and song.name or "?")))

	return false
end

local function play_local_file(index, path, tried)
	if not _playlist then
		return false
	end

	local song = _playlist.tracks[index]
	local ok, err = Audio.play(path, math.floor(_volume * 10 + 0.5))

	if not ok then
		mod:warning("could not play '%s': %s", song.name, tostring(err))
		Util.delete_file(path)

		return fail_current(index, tried)
	end

	_index = index
	_pending_index = nil

	set_status("playing")
	_last_mode = "playing"

	load_lyric(song)

	begin_duck()

	return true
end

_start_song = function(index, tried)
	if not _playlist or #_playlist.tracks == 0 then
		return false
	end

	index = clamp(index, 1, #_playlist.tracks)

	local song = _playlist.tracks[index]
	local path = song_cache_path(song)

	if cache_file_ok(path) then
		return play_local_file(index, path, tried)
	end

	-- 先把当前这首停掉，避免旧歌继续放着
	Audio.stop()
	end_duck()

	_pending_index = index

	set_status("loading")

	Net.fetch(Playlist.song_url(song.id), path, function(result)
		if _pending_index ~= index then
			-- 用户又点了别的歌，这次下载作废
			return
		end

		if not result.ok or not cache_file_ok(path) then
			Util.delete_file(path)

			_pending_index = nil

			return fail_current(index, tried)
		end

		play_local_file(index, path, tried)
	end)

	return true
end

local function pick_next_index(from_index, forward)
	local count = _playlist and #_playlist.tracks or 0

	if count == 0 then
		return 0
	end

	if _loop_mode == "shuffle" then
		if count == 1 then
			return 1
		end

		local index = math.random(count)

		if index == from_index then
			index = index % count + 1
		end

		return index
	end

	local step = forward and 1 or -1
	local index = from_index + step

	if index > count then
		index = 1
	elseif index < 1 then
		index = count
	end

	return index
end

-- ############################## 对外状态 ##############################

mod.playlist = function()
	return _playlist
end

mod.current_index = function()
	return _index
end

mod.current_song = function()
	return current_song()
end

mod.buffering_song = function()
	if not _pending_index or not _playlist then
		return nil
	end

	return _playlist.tracks[_pending_index]
end

mod.status = function()
	return _status
end

mod.error_message = function()
	return _error
end

mod.volume = function()
	return _volume
end

mod.loop_mode = function()
	return _loop_mode
end

mod.progress = function()
	return Audio.progress()
end

mod.audio_state = function()
	return Audio.state()
end

mod.audio_level = function()
	return Audio.level()
end

mod.spectrum = function()
	return Audio.spectrum()
end

-- 当前歌词行和下一行
mod.current_lyric = function()
	local _, position = Audio.progress()

	if not position or #_lyric == 0 then
		return nil, nil
	end

	position = position + (tonumber(mod:get("lyric_offset")) or 0)

	local current = nil

	for i = 1, #_lyric do
		if _lyric[i].time <= position then
			current = _lyric[i]
		else
			return current, _lyric[i]
		end
	end

	return current, nil
end

-- 以当前行为中心的歌词窗口：返回 count 行，每行 { text, offset }
-- offset = 0 是当前行，-1 是上一行，+1 是下一行
mod.lyric_window = function(count)
	local _, position = Audio.progress()

	count = count or 5

	if not position or #_lyric == 0 then
		return {}
	end

	position = position + (tonumber(mod:get("lyric_offset")) or 0)

	local current_index = 0

	for i = 1, #_lyric do
		if _lyric[i].time <= position then
			current_index = i
		else
			break
		end
	end

	local result = {}
	local half = math.floor(count / 2)

	for i = current_index - half, current_index + half do
		local line = _lyric[i]

		result[#result + 1] = {
			text = line and line.text or "",
			offset = i - current_index,
		}
	end

	return result
end

mod.playlists = function()
	return Playlists.list()
end

mod.switch_playlist = function(url)
	if url and url ~= "" then
		return mod.load_playlist(url)
	end

	return false
end

mod.remove_playlist = function(id)
	Playlists.remove(id)
end

-- 缓存统计：先按目录扫；扫不到（FFI 不可用/目录读不了）时按当前歌单已知文件估算
mod.cache_stats = function()
	local stats = Util.cache_stats()

	if stats and stats.count and stats.count > 0 then
		return stats
	end

	stats = {
		count = 0,
		total = 0,
		songs = 0,
		song_bytes = 0,
	}

	local dir = Util.cache_dir()

	local function add(name, is_song)
		local size = Util.file_size(dir .. name)

		if size then
			stats.count = stats.count + 1
			stats.total = stats.total + size

			if is_song then
				stats.songs = stats.songs + 1
				stats.song_bytes = stats.song_bytes + size
			end
		end
	end

	add("playlists.lua")
	add("last_full.lua")
	add("last_playlist.json")

	if _playlist then
		for i = 1, #_playlist.tracks do
			local id = _playlist.tracks[i].id

			add("song_" .. tostring(id) .. ".mp3", true)
			add("lyric_" .. tostring(id) .. ".json")
		end

		add("playlist_" .. tostring(_playlist.id) .. ".json")
	end

	return stats
end

mod.clear_cache = function()
	local removed = Util.clear_cache()

	-- 歌词和当前歌单的缓存都没了，内存里的那份一起清掉
	_lyric = {}
	_lyric_cache = {}
	_lyric_song_id = nil

	return removed
end

mod.audio_available = function()
	return Audio.available(), Audio.init_error()
end

mod.is_loading = function()
	return _status == "loading"
end

mod.format_time = Util.format_time

mod.format_song = function(song)
	if not song then
		return ""
	end

	return Util.clip(song.name .. "  ·  " .. (song.artists or ""), 34)
end

mod.clipboard_text = function()
	return Util.clipboard_text()
end

mod.last_url = load_last_url

-- ############################## 对外操作 ##############################

mod.load_playlist = function(text, silent)
	local token = _load_token + 1

	_load_token = token

	if _status ~= "playing" and _status ~= "paused" then
		set_status("loading")
	end

	local started, start_err = Playlist.load(text, function(playlist, err)
		if _load_token ~= token then
			-- 又发起了一次加载，这次的结果丢掉
			return
		end

		if not playlist then
			local message = load_error_text(err)

			set_status("error", message)

			if not silent then
				mod:echo(message)
			end

			return
		end

		_playlist = playlist
		_index = 0
		_pending_index = nil

		if _status == "loading" then
			set_status("idle")
		end

		mod:set("last_playlist_url", text)
		save_last_url(text)
		Playlists.add(playlist, text)
		mod:info("loaded playlist '%s' with %d tracks", playlist.name, #playlist.tracks)

		if not silent then
			mod:echo(mod:localize("loaded_playlist", playlist.name, tostring(#playlist.tracks)))
		end
	end)

	if not started then
		local message = load_error_text(start_err)

		set_status("error", message)

		if not silent then
			mod:echo(message)
		end
	end

	return started
end

mod.play_index = function(index)
	if not _playlist then
		return false
	end

	return _start_song(index, 0)
end

mod.toggle_play = function()
	if not _playlist or #_playlist.tracks == 0 then
		return
	end

	local state = Audio.state()

	if state == "playing" then
		Audio.pause()

		set_status("paused")
		_last_mode = "paused"
	elseif state == "paused" then
		Audio.resume()

		set_status("playing")
		_last_mode = "playing"
		begin_duck()
	else
		-- 没有活动曲目（刚启动 / 放完 / 停掉）或者已经停了：从当前曲目或第一首开始
		_start_song(_index > 0 and _index or 1, 0)
	end
end

mod.next_track = function()
	if not _playlist or #_playlist.tracks == 0 then
		return
	end

	_start_song(pick_next_index(_index, true), 0)
end

mod.previous_track = function()
	if not _playlist or #_playlist.tracks == 0 then
		return
	end

	_start_song(pick_next_index(_index, false), 0)
end

mod.stop = function()
	Audio.stop()
	_pending_index = nil
	end_duck()
	set_status("idle")
	_last_mode = nil
end

mod.set_volume = function(value)
	_volume = clamp(math.floor(value + 0.5), 0, 100)

	mod:set("volume", _volume)
	Audio.set_volume(math.floor(_volume * 10 + 0.5))
end

mod.adjust_volume = function(delta)
	mod.set_volume(_volume + delta)

	_volume_toast_until = now() + 1.5
end

-- 快捷键调音量后，迷你 HUD 会临时亮 1.5 秒显示当前音量
mod.volume_toast = function()
	return _volume_toast_until > now()
end

mod.volume_up = function()
	mod.adjust_volume(5)
end

mod.volume_down = function()
	mod.adjust_volume(-5)
end

mod.cycle_loop_mode = function()
	if _loop_mode == "order" then
		_loop_mode = "single"
	elseif _loop_mode == "single" then
		_loop_mode = "shuffle"
	else
		_loop_mode = "order"
	end

	mod:set("loop_mode", _loop_mode)
end

-- ############################## 面板 ##############################

mod.open_view = function()
	if not mod:is_enabled() then
		return
	end

	local ui = Managers.ui

	if ui and not ui:view_instance(VIEW_NAME) then
		ui:open_view(VIEW_NAME, nil, nil, nil, nil, {})
	end
end

mod.close_view = function()
	local ui = Managers.ui

	if ui and ui:view_instance(VIEW_NAME) and not ui:is_view_closing(VIEW_NAME) then
		ui:close_view(VIEW_NAME)
	end
end

mod.toggle_view = function()
	local ui = Managers.ui

	if not ui then
		return
	end

	if ui:view_active(VIEW_NAME) then
		mod.close_view()
	else
		mod.open_view()
	end
end

-- ############################## 生命周期 ##############################

mod.on_all_mods_loaded = function()
	Playlists.load()
	_playlist = Playlist.load_cached()
	_index = 0

	local saved_volume = mod:get("volume")

	if type(saved_volume) == "number" then
		_volume = clamp(saved_volume, 0, 100)
	end

	local saved_loop = mod:get("loop_mode")

	if saved_loop == "order" or saved_loop == "single" or saved_loop == "shuffle" then
		_loop_mode = saved_loop
	end

	if _playlist then
		mod:info("restored cached playlist '%s' (%d tracks)", _playlist.name, #_playlist.tracks)

		-- 旧缓存只存了歌单 JSON 里带的前几首；有链接就静默重拉一次，补全列表
		if _playlist.partial then
			local saved_url = load_last_url()

			if saved_url ~= "" then
				mod.load_playlist(saved_url, true)
			end
		end
	end

	local audio_ok, audio_error = Audio.available(), Audio.init_error()

	mod:info(
		"TidePlayer ready: audio=%s (%s), curl=%s, playlist=%s",
		tostring(audio_ok),
		tostring(audio_error or "ok"),
		tostring(Net.curl()),
		_playlist and _playlist.name or "none"
	)

	if type(mod.register_hud_element) == "function" then
		mod:register_hud_element({
			class_name = "TidePlayerHud",
			filename = "TidePlayer/scripts/mods/TidePlayer/TidePlayer_hud",
			visibility_groups = { "alive", "dead" },
			use_hud_scale = false,
		})

		mod:info("mini HUD registered")
	end
end

mod.on_setting_changed = function(setting_id)
	if setting_id == "volume" then
		local value = mod:get("volume")

		if type(value) == "number" then
			mod.set_volume(value)
		end
	elseif setting_id == "duck_game_music" then
		if not mod:get("duck_game_music") and _game_backup then
			_duck_target = 0
		end
	end
end

mod.on_disabled = function()
	Audio.stop()
	Net.cancel_all()

	_pending_index = nil
	_duck_target = 0
	_duck = 0

	if _game_backup then
		Wwise.set_parameter(MUSIC_VOLUME_PARAMETER, _game_backup)

		_game_backup = nil
	end
end

mod.on_unload = function()
	mod.on_disabled()
end

-- ############################## update ##############################

mod.update = function(dt)
	Net.update()
	update_duck(dt)

	if not _playlist then
		return
	end

	_poll_timer = _poll_timer + (dt or 0)

	if _poll_timer < STATUS_POLL_INTERVAL then
		return
	end

	_poll_timer = 0

	local state = Audio.state()

	if not state then
		return
	end

	if state == "playing" then
		if _status ~= "playing" then
			set_status("playing")
		end

		_last_mode = "playing"
	elseif state == "stopped" and _last_mode == "playing" then
		-- 一首放完了（不是用户按的暂停）：按循环模式接下一首
		_last_mode = "stopped"

		if _loop_mode == "single" then
			_start_song(_index, 0)
		else
			_start_song(pick_next_index(_index, true), 0)
		end
	end
end

-- ############################## 注册 ##############################

mod:add_require_path("TidePlayer/scripts/mods/TidePlayer/tide_player_view/tide_player_view")
mod:add_require_path("TidePlayer/scripts/mods/TidePlayer/tide_player_view/tide_player_view_definitions")

mod:register_view({
	view_name = VIEW_NAME,
	view_settings = {
		init_view_function = function(ingame_ui_context)
			return true
		end,
		state_bound = false,
		package = "packages/ui/views/options_view/options_view",
		path = "TidePlayer/scripts/mods/TidePlayer/tide_player_view/tide_player_view",
		class = "TidePlayerView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = true,
		game_world_blur = 0,
		enter_sound_events = {
			"wwise/events/ui/play_ui_enter_short",
		},
		exit_sound_events = {
			"wwise/events/ui/play_ui_back_short",
		},
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
	},
})

mod:command("tideplayer", "Open the NetEase music player", function()
	mod.open_view()
end)

mod:command("tp", "Load a NetEase playlist by link or id", function(text)
	if text and text ~= "" then
		mod.load_playlist(text)
	else
		local saved = load_last_url()

		if saved ~= "" then
			mod.load_playlist(saved)
		else
			mod:echo(mod:localize("error_no_link"))
		end
	end
end)
