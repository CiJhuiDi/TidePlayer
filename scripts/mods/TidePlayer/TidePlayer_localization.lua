return {
	mod_name = {
		en = "Tide Player",
		["zh-cn"] = "暗潮点歌台",
	},
	mod_description = {
		en = "Paste a NetEase Cloud Music playlist link and play it in game. Uses the Windows MCI audio backend, no extra plugin needed.",
		["zh-cn"] = "粘贴网易云歌单链接就在游戏里点歌。音频走 Windows MCI，不需要额外装 Audio Plugin。",
	},

	-- 设置项
	tide_player_group = {
		en = "Tide Player",
		["zh-cn"] = "点歌台",
	},
	open_player = {
		en = "Open the player",
		["zh-cn"] = "打开点歌台",
	},
	open_player_description = {
		en = "Open or close the player panel.",
		["zh-cn"] = "打开 / 关闭点歌台面板。",
	},
	toggle_play_key = {
		en = "Play / pause",
		["zh-cn"] = "播放 / 暂停",
	},
	toggle_play_key_description = {
		en = "Play or pause without opening the panel.",
		["zh-cn"] = "不开面板直接播放 / 暂停。",
	},
	next_track_key = {
		en = "Next track",
		["zh-cn"] = "下一首",
	},
	next_track_key_description = {
		en = "Skip to the next track.",
		["zh-cn"] = "切到下一首。",
	},
	prev_track_key = {
		en = "Previous track",
		["zh-cn"] = "上一首",
	},
	prev_track_key_description = {
		en = "Go back to the previous track.",
		["zh-cn"] = "回到上一首。",
	},
	volume_up_key = {
		en = "Volume +",
		["zh-cn"] = "音量 +",
	},
	volume_up_key_description = {
		en = "Raise the player volume by 5% without opening the panel.",
		["zh-cn"] = "不开面板，直接把播放器音量调高 5%。",
	},
	volume_down_key = {
		en = "Volume -",
		["zh-cn"] = "音量 -",
	},
	volume_down_key_description = {
		en = "Lower the player volume by 5% without opening the panel.",
		["zh-cn"] = "不开面板，直接把播放器音量调低 5%。",
	},
	duck_game_music = {
		en = "Lower game music while playing",
		["zh-cn"] = "播放时压低游戏音乐",
	},
	duck_game_music_description = {
		en = "Fade the game's own music down when a song plays, and restore it on pause or stop.",
		["zh-cn"] = "放歌时把游戏自带音乐淡出，暂停或停止后恢复。",
	},
	hud_enabled = {
		en = "Mini HUD while playing",
		["zh-cn"] = "播放时显示迷你 HUD",
	},
	hud_enabled_description = {
		en = "Show the current song, artist and progress in the bottom right corner while music is playing.",
		["zh-cn"] = "放歌时在屏幕右下角显示当前歌曲、歌手和进度。",
	},
	hud_extra_offset = {
		en = "Extra gap below objectives",
		["zh-cn"] = "任务目标下方额外间距",
	},
	hud_extra_offset_description = {
		en = "The mini HUD follows the last mission objective. This is the extra gap below it. With no objectives it takes the objective HUD's own spot.",
		["zh-cn"] = "迷你 HUD 会自动挂在最后一条任务目标下面，这里调额外间距。没有任务目标时它直接占任务目标 HUD 的位置。",
	},
	lyric_offset = {
		en = "Lyric offset (ms)",
		["zh-cn"] = "歌词偏移（毫秒）",
	},
	lyric_offset_description = {
		en = "Positive shows lyrics later, negative earlier. Use it when lyrics drift ahead of or behind the music.",
		["zh-cn"] = "正数让歌词晚一点，负数让歌词早一点。歌词比音乐快/慢时用这个微调。",
	},
	hud_scroll_speed = {
		en = "Long title scroll interval",
		["zh-cn"] = "长歌名滚动间隔",
	},
	hud_scroll_speed_description = {
		en = "Seconds per step when a long song title scrolls. Smaller is faster.",
		["zh-cn"] = "长歌名每滚一格用多少秒，越小越快。",
	},
	volume = {
		en = "Volume",
		["zh-cn"] = "音量",
	},
	volume_description = {
		en = "Volume for the player (independent of the game's music slider).",
		["zh-cn"] = "播放器的音量（和游戏自带的音乐音量分开）。",
	},

	-- 面板
	view_title = {
		en = "Tide Player",
		["zh-cn"] = "暗潮点歌台",
	},
	view_hint = {
		en = "Copy a NetEase playlist link, then click \"Paste playlist link\". Esc closes the panel.",
		["zh-cn"] = "复制网易云歌单链接，点「粘贴歌单链接」。Esc 关闭面板。",
	},
	subtitle_loaded = {
		en = "Playlist: %s  ·  %s tracks",
		["zh-cn"] = "歌单：%s  ·  %s 首",
	},
	subtitle_empty = {
		en = "No playlist loaded yet.",
		["zh-cn"] = "还没有加载歌单。",
	},
	empty_playlist = {
		en = "Copy a NetEase playlist link to your clipboard, then click \"Paste playlist link\" above.",
		["zh-cn"] = "把网易云歌单链接复制到剪贴板，点上面的「粘贴歌单链接」。",
	},
	button_import = {
		en = "Paste playlist link",
		["zh-cn"] = "粘贴歌单链接",
	},
	button_reload = {
		en = "Reload",
		["zh-cn"] = "重新加载",
	},
	button_stop = {
		en = "Stop",
		["zh-cn"] = "停止",
	},
	button_prev = {
		en = "Prev",
		["zh-cn"] = "上一首",
	},
	button_play = {
		en = "Play",
		["zh-cn"] = "播放",
	},
	button_pause = {
		en = "Pause",
		["zh-cn"] = "暂停",
	},
	button_resume = {
		en = "Resume",
		["zh-cn"] = "继续",
	},
	button_next = {
		en = "Next",
		["zh-cn"] = "下一首",
	},
	button_volume_down = {
		en = "Vol -",
		["zh-cn"] = "音量 -",
	},
	button_volume_up = {
		en = "Vol +",
		["zh-cn"] = "音量 +",
	},
	button_prev_page = {
		en = "< Prev",
		["zh-cn"] = "< 上一页",
	},
	button_next_page = {
		en = "Next >",
		["zh-cn"] = "下一页 >",
	},
	loop_order = {
		en = "Loop: in order",
		["zh-cn"] = "循环：顺序",
	},
	loop_single = {
		en = "Loop: one song",
		["zh-cn"] = "循环：单曲",
	},
	loop_shuffle = {
		en = "Loop: shuffle",
		["zh-cn"] = "循环：随机",
	},
	page_label = {
		en = "Page %d / %d",
		["zh-cn"] = "第 %d / %d 页",
	},
	status_idle = {
		en = "Not playing  ·  volume %s%%",
		["zh-cn"] = "未在播放  ·  音量 %s%%",
	},
	status_loading = {
		en = "Loading playlist...",
		["zh-cn"] = "正在加载歌单…",
	},
	status_buffering = {
		en = "Buffering: %s",
		["zh-cn"] = "正在缓存：%s",
	},
	status_playing = {
		en = "Playing: %s  ·  %s    %s / %s    volume %s%%",
		["zh-cn"] = "正在播放：%s  ·  %s    %s / %s    音量 %s%%",
	},
	status_paused = {
		en = "Paused: %s  ·  %s    volume %s%%",
		["zh-cn"] = "已暂停：%s  ·  %s    音量 %s%%",
	},
	button_close = {
		en = "Close",
		["zh-cn"] = "关闭",
	},
	button_cache = {
		en = "Cache",
		["zh-cn"] = "缓存",
	},
	cache_title = {
		en = "Cache",
		["zh-cn"] = "缓存",
	},
	cache_songs = {
		en = "%s songs · %s",
		["zh-cn"] = "%s 首歌 · %s",
	},
	cache_files = {
		en = "%s files in total, %s",
		["zh-cn"] = "共 %s 个文件，合计 %s",
	},
	button_clear_cache = {
		en = "Clear cache",
		["zh-cn"] = "清空缓存",
	},
	cache_empty = {
		en = "Cache is empty",
		["zh-cn"] = "缓存是空的",
	},
	status_empty_song = {
		en = "NO STATION SELECTED",
		["zh-cn"] = "未选频道",
	},
	status_fm = {
		en = "FM ON AIR · %s   VOL %s",
		["zh-cn"] = "FM 正在播出 · %s   音量 %s",
	},
	status_fm_paused = {
		en = "FM PAUSED · %s   VOL %s",
		["zh-cn"] = "FM 已暂停 · %s   音量 %s",
	},
	status_standby = {
		en = "FM STANDBY   VOL %s",
		["zh-cn"] = "FM 待机   音量 %s",
	},
	status_error = {
		en = "Error:",
		["zh-cn"] = "出错了：",
	},
	tab_tracks = {
		en = "Tracks",
		["zh-cn"] = "频道",
	},
	tab_playlists = {
		en = "Playlists",
		["zh-cn"] = "歌单",
	},
	list_head_tracks = {
		en = "PRESET CHANNELS",
		["zh-cn"] = "频道列表",
	},
	list_head_playlists = {
		en = "SAVED PLAYLISTS",
		["zh-cn"] = "已保存歌单",
	},
	playlists_empty = {
		en = "No saved playlists yet. Paste a link to add one.",
		["zh-cn"] = "还没有保存的歌单。粘贴一个链接就会存进来。",
	},

	-- 提示
	clipboard_empty = {
		en = "No link found in the clipboard.",
		["zh-cn"] = "剪贴板里没找到链接。",
	},
	loaded_playlist = {
		en = "Loaded playlist \"%s\" with %s tracks.",
		["zh-cn"] = "已加载歌单《%s》，共 %s 首。",
	},
	error_no_link = {
		en = "Copy a NetEase playlist link first, then click \"Paste playlist link\".",
		["zh-cn"] = "先复制一个网易云歌单链接，再点「粘贴歌单链接」。",
	},
	error_link_nourl = {
		en = "No link found. Copy the share link of a NetEase playlist and try again.",
		["zh-cn"] = "没找到链接。复制网易云歌单的分享链接再试。",
	},
	error_link_unsupported = {
		en = "That link is not a playlist. Use a music.163.com/playlist?id=... address.",
		["zh-cn"] = "这个链接不是歌单。支持 music.163.com/playlist?id=… 这样的地址。",
	},
	error_load_fetch = {
		en = "Could not download the playlist. Check your network.",
		["zh-cn"] = "歌单下载失败，检查一下网络。",
	},
	error_load_json = {
		en = "Could not parse the playlist data.",
		["zh-cn"] = "歌单数据解析失败。",
	},
	error_load_empty = {
		en = "This playlist returned no tracks (maybe it needs a login, or it is empty).",
		["zh-cn"] = "这个歌单拿不到曲目（可能要登录，或者歌单是空的）。",
	},
	error_load_short = {
		en = "Could not resolve the short link. Open it in a browser and copy the full address.",
		["zh-cn"] = "短链解析失败。在浏览器里打开后复制完整地址再试。",
	},
	error_load_unknown = {
		en = "Failed to load the playlist.",
		["zh-cn"] = "加载歌单失败。",
	},
	error_play = {
		en = "Could not play: %s",
		["zh-cn"] = "这首歌放不出来：%s",
	},
}
