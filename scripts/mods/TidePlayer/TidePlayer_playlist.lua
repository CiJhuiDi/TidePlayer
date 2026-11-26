-- TidePlayer_playlist.lua
-- 网易云歌单：链接解析、歌单接口、曲目模型。
--
-- 用 /api/v6/playlist/detail：它给全量的 trackIds（旧接口对大歌单只回 10 首、
-- trackIds 还是空的）。tracks 里通常只带前 10 首详细信息，剩下的用
-- /api/song/detail?ids=[...] 批量补，一次最多 500 个 id。
--
-- 播放地址走 /song/media/outer/url?id=<id>.mp3，302 到 CDN，curl 下载。

local mod = get_mod("TidePlayer")
local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")
local Json = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_json")
local Net = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_net")

local Playlist = {}

local API_URL = "https://music.163.com/api/v6/playlist/detail?id=%d&n=1000&s=0"
local SONG_DETAIL_URL = "https://music.163.com/api/song/detail?ids=[%s]"
local ALBUM_URL = "https://music.163.com/api/v1/album/%d"
local LYRIC_URL = "https://music.163.com/api/song/lyric?id=%d&lv=1&kv=1&tv=-1"
local OUTER_URL = "https://music.163.com/song/media/outer/url?id=%d.mp3"
local SHORT_LINK = "163cn.tv"
local DETAIL_BATCH = 500

-- ############################## 链接解析 ##############################

local function extract_url(text)
	if not text then
		return nil
	end

	return string.match(text, "https?://[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]+")
end

-- 返回 kind, value：
--   "id"    → value 是歌单数字 id
--   "short" → value 是短链 URL，要再请求一次才知道 id
--   nil, err
Playlist.parse_url = function(text)
	local trimmed = Util.trim(text)

	if trimmed == "" then
		return nil, "empty"
	end

	-- 允许用户直接粘贴一串数字
	local bare_id = string.match(trimmed, "^(%d+)$")

	if bare_id then
		return "id", tonumber(bare_id)
	end

	local url = extract_url(trimmed)

	if not url then
		return nil, "no_url"
	end

	-- 只拒绝单曲和歌手页；专辑和歌单都收
	if string.find(url, "/song", 1, true) or string.find(url, "song?", 1, true)
		or string.find(url, "/artist", 1, true) or string.find(url, "artist?", 1, true) then
		return nil, "unsupported_url"
	end

	local playlist_id = string.match(url, "playlist[^%d]-id=(%d+)")
		or string.match(url, "playlist/(%d+)")

	if playlist_id then
		return "id", tonumber(playlist_id)
	end

	local album_id = string.match(url, "album[^%d]-id=(%d+)")
		or string.match(url, "album/(%d+)")

	if album_id then
		return "album", tonumber(album_id)
	end

	local generic_id = string.match(url, "[?&]id=(%d+)")

	if generic_id then
		return "id", tonumber(generic_id)
	end

	if string.find(url, SHORT_LINK, 1, true) then
		return "short", url
	end

	return nil, "unsupported_url"
end

-- 歌曲播放地址（curl 下载这个 URL，会 302 到 CDN）
Playlist.song_url = function(song_id)
	return string.format(OUTER_URL, song_id)
end

-- ############################## 数据 ##############################

local function artist_names(track)
	local artists = track.ar or track.artists or {}
	local names = {}

	for i = 1, #artists do
		local artist = artists[i]

		if type(artist) == "table" and artist.name then
			names[#names + 1] = artist.name
		end
	end

	if #names == 0 then
		return "未知歌手"
	end

	return table.concat(names, " / ")
end

local function album_name(track)
	local album = track.al or track.album

	if type(album) == "table" and album.name then
		return album.name
	end

	return ""
end

local function make_song(track, index)
	return {
		id = tonumber(track.id),
		name = track.name or "?",
		artists = artist_names(track),
		album = album_name(track),
		duration = tonumber(track.dt) or tonumber(track.duration) or 0,
		index = index,
	}
end

local function build_tracks(raw_tracks, limit)
	local tracks = {}

	if type(raw_tracks) ~= "table" then
		return tracks
	end

	local count = math.min(#raw_tracks, limit or #raw_tracks)

	for i = 1, count do
		local track = raw_tracks[i]

		if type(track) == "table" and track.id then
			tracks[#tracks + 1] = make_song(track, #tracks + 1)
		end
	end

	return tracks
end

-- v6 的 trackIds 元素可能是数字，也可能是 { id = ... }
local function extract_track_ids(result)
	local ids = {}
	local raw = result.trackIds

	if type(raw) ~= "table" then
		return ids
	end

	for i = 1, #raw do
		local item = raw[i]
		local id

		if type(item) == "table" then
			id = item.id
		elseif type(item) == "number" then
			id = item
		end

		if type(id) == "number" then
			ids[#ids + 1] = id
		end
	end

	return ids
end

local function build_tracks_by_ids(ids, song_map)
	local tracks = {}

	for i = 1, #ids do
		local song = song_map[ids[i]]

		if song then
			tracks[#tracks + 1] = make_song(song, #tracks + 1)
		end
	end

	return tracks
end

-- ############################## 缓存 ##############################

-- 完整曲目存成 Lua 表（写 `return {...}`），启动时能直接读回来。
-- 不能只存原始 JSON：v6 的 JSON 里 tracks 只有前 10 首。
local function save_full(playlist)
	local lines = {
		"return {",
		string.format("  id = %d,", playlist.id or 0),
		string.format("  name = %q,", playlist.name or ""),
		string.format("  cover = %q,", playlist.cover and playlist.cover or ""),
		"  tracks = {",
	}

	for i = 1, #playlist.tracks do
		local track = playlist.tracks[i]

		lines[#lines + 1] = string.format(
			"    { id = %d, name = %q, artists = %q, album = %q, duration = %d, index = %d },",
			track.id,
			track.name or "",
			track.artists or "",
			track.album or "",
			track.duration or 0,
			track.index or i
		)
	end

	lines[#lines + 1] = "  },"
	lines[#lines + 1] = "}"

	Util.write_file(Util.cache_dir() .. "last_full.lua", table.concat(lines, "\n"))
end

local function load_full()
	if not Util.file_exists(Util.cache_dir() .. "last_full.lua") then
		return nil
	end

	local ok, data = pcall(mod.io_dofile, mod, "TidePlayer/cache/last_full")

	if not ok or type(data) ~= "table" or type(data.tracks) ~= "table" or #data.tracks == 0 then
		return nil
	end

	return {
		id = tonumber(data.id) or 0,
		name = data.name or "未知歌单",
		cover = data.cover,
		track_count = #data.tracks,
		tracks = data.tracks,
	}
end

-- ############################## 网络 ##############################

-- 分批拉歌曲详情；全部返回后 on_done(map 或 nil, err)
local function fetch_song_details(ids, on_done)
	local song_map = {}
	local batch_index = 0
	local total_batches = math.ceil(#ids / DETAIL_BATCH)

	local function fetch_next()
		batch_index = batch_index + 1

		if batch_index > total_batches then
			on_done(song_map)

			return
		end

		local first = (batch_index - 1) * DETAIL_BATCH + 1
		local last = math.min(first + DETAIL_BATCH - 1, #ids)
		local parts = {}

		for i = first, last do
			parts[#parts + 1] = tostring(ids[i])
		end

		local url = string.format(SONG_DETAIL_URL, table.concat(parts, ","))
		local path = Util.cache_dir() .. "song_detail_" .. tostring(batch_index) .. ".json"

		Net.fetch(url, path, function(result)
			if not result.ok then
				on_done(nil, "detail_failed:" .. tostring(result.error))

				return
			end

			local raw = Json.decode(result.body)

			if not raw or type(raw.songs) ~= "table" then
				on_done(nil, "detail_bad_json")

				return
			end

			for i = 1, #raw.songs do
				local song = raw.songs[i]

				if type(song) == "table" and song.id then
					song_map[song.id] = song
				end
			end

			fetch_next()
		end)
	end

	fetch_next()
end

local function finalize(result, on_done)
	local name = result.name or "未知歌单"
	local cover = result.coverImgUrl
	local ids = extract_track_ids(result)
	local partial = build_tracks(result.tracks)

	if #ids > #partial then
		-- tracks 只带了前几首，按 trackIds 把整张歌单补齐
		fetch_song_details(ids, function(song_map, err)
			local tracks

			if song_map then
				tracks = build_tracks_by_ids(ids, song_map)
			else
				mod:warning("song detail failed (%s), falling back to %d tracks", tostring(err), #partial)

				tracks = partial
			end

			if #tracks == 0 then
				on_done(nil, "empty_tracks")

				return
			end

			local playlist = {
				id = tonumber(result.id) or 0,
				name = name,
				cover = cover,
				track_count = math.max(#ids, #tracks),
				tracks = tracks,
			}

			-- 只有拿到全量曲目才写完整性缓存；降级的那份下次启动会被当成不完整
			if song_map then
				save_full(playlist)
			else
				playlist.partial = true
			end

			on_done(playlist)
		end)
	else
		if #partial == 0 then
			on_done(nil, "empty_tracks")

			return
		end

		local playlist = {
			id = tonumber(result.id) or 0,
			name = name,
			cover = cover,
			track_count = #partial,
			tracks = partial,
		}

		save_full(playlist)
		on_done(playlist)
	end
end

local function fetch_api(playlist_id, on_done)
	local url = string.format(API_URL, playlist_id)
	local path = Util.cache_dir() .. "playlist_" .. tostring(playlist_id) .. ".json"

	Net.fetch(url, path, function(result)
		if not result.ok then
			on_done(nil, "fetch_failed:" .. tostring(result.error))

			return
		end

		local raw, json_err = Json.decode(result.body)

		if not raw then
			on_done(nil, "bad_json:" .. tostring(json_err))

			return
		end

		local playlist_result = raw.result or raw.playlist

		if type(playlist_result) ~= "table" then
			on_done(nil, "no_result")

			return
		end

		-- 最近一次的歌单原始数据存一份，下次启动直接读它（不用重新联网）
		Util.write_file(Util.cache_dir() .. "last_playlist.json", result.body)

		finalize(playlist_result, on_done)
	end)
end

local function fetch_album(album_id, on_done)
	local url = string.format(ALBUM_URL, album_id)
	local path = Util.cache_dir() .. "album_" .. tostring(album_id) .. ".json"

	Net.fetch(url, path, function(result)
		if not result.ok then
			on_done(nil, "fetch_failed:" .. tostring(result.error))

			return
		end

		local raw = Json.decode(result.body)

		if not raw then
			on_done(nil, "bad_json")

			return
		end

		local album = raw.album
		local songs = raw.songs

		if type(album) ~= "table" or type(songs) ~= "table" or #songs == 0 then
			on_done(nil, "empty_tracks")

			return
		end

		local tracks = build_tracks(songs)

		if #tracks == 0 then
			on_done(nil, "empty_tracks")

			return
		end

		local playlist = {
			id = tonumber(album.id) or album_id,
			name = album.name or "未知专辑",
			cover = album.picUrl,
			track_count = #tracks,
			tracks = tracks,
		}

		save_full(playlist)
		on_done(playlist)
	end)
end

local function resolve_short(short_url, on_done)
	local path = Util.cache_dir() .. "shortlink.html"

	Net.fetch(short_url, path, function(result)
		if not result.ok then
			on_done(nil, "short_failed:" .. tostring(result.error))

			return
		end

		local body = result.body
		local playlist_id = string.match(body, "playlist[^%d]-id=(%d+)")
			or string.match(body, "playlist/(%d+)")

		if not playlist_id then
			on_done(nil, "short_no_id")

			return
		end

		fetch_api(tonumber(playlist_id), on_done)
	end)
end

-- 异步加载；on_done(playlist, err)
Playlist.load = function(text, on_done)
	local kind, value = Playlist.parse_url(text)

	if not kind then
		on_done(nil, value)

		return false
	end

	if kind == "id" then
		fetch_api(value, on_done)
	elseif kind == "album" then
		fetch_album(value, on_done)
	else
		resolve_short(value, on_done)
	end

	return true
end

-- 启动时恢复上次的歌单（读完整缓存，不联网）
Playlist.load_cached = function()
	local full = load_full()

	if full then
		return full
	end

	-- 兼容旧缓存：只有原始 JSON 时只能恢复 tracks 里带的那几首
	local body = Util.read_file(Util.cache_dir() .. "last_playlist.json")

	if not body then
		return nil
	end

	local raw = Json.decode(body)

	if not raw then
		return nil
	end

	local result = raw.result or raw.playlist

	if type(result) ~= "table" then
		return nil
	end

	local tracks = build_tracks(result.tracks)

	if #tracks == 0 then
		return nil
	end

	return {
		id = tonumber(result.id) or 0,
		name = result.name or "未知歌单",
		cover = result.coverImgUrl,
		track_count = #tracks,
		tracks = tracks,
		partial = true,
	}
end

-- ############################## 歌词 ##############################

-- LRC 行：`[mm:ss.xx] 文本`；可能带一个 [offset:±ms] 全局标签
local function parse_lrc(text)
	local lines = {}

	if type(text) ~= "string" then
		return lines
	end

	local global_offset = tonumber(string.match(text, "%[offset:([%-%d]+)%]")) or 0

	for line in string.gmatch(text, "[^\r\n]+") do
		local minutes, seconds, fraction = string.match(line, "^%[(%d+):(%d+)%.(%d+)%]")

		if minutes then
			local content = string.match(line, "^%[%d+:%d+%.%d+%]%s*(.-)%s*$")

			if content and content ~= "" then
				-- 毫秒位可能是 1/2/3 位（[00:05.5] / [00:05.52] / [00:05.520]）
				local ms = tonumber(fraction) or 0
				local digits = #fraction

				if digits == 1 then
					ms = ms * 100
				elseif digits == 2 then
					ms = ms * 10
				end

				lines[#lines + 1] = {
					time = tonumber(minutes) * 60000 + tonumber(seconds) * 1000 + ms + global_offset,
					text = content,
				}
			end
		end
	end

	table.sort(lines, function (a, b)
		return a.time < b.time
	end)

	return lines
end

-- 拉某首歌的歌词；on_done(lines 或 nil, err)
Playlist.fetch_lyric = function(song_id, on_done)
	if not song_id then
		on_done(nil, "no_song")

		return
	end

	local url = string.format(LYRIC_URL, song_id)
	local path = Util.cache_dir() .. "lyric_" .. tostring(song_id) .. ".json"

	Net.fetch(url, path, function(result)
		if not result.ok then
			on_done(nil, "lyric_fetch_failed")

			return
		end

		local raw = Json.decode(result.body)
		local lyric_text = raw and raw.lrc and raw.lrc.lyric

		if type(lyric_text) ~= "string" or lyric_text == "" then
			on_done(nil, "no_lyric")

			return
		end

		local lines = parse_lrc(lyric_text)

		if #lines == 0 then
			on_done(nil, "no_lyric")

			return
		end

		on_done(lines)
	end)
end

return Playlist
