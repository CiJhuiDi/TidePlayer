-- TidePlayer_playlists.lua
-- 保存过的歌单：id / 名字 / 曲目数 / 原始链接 / 更新时间。
-- 存在 cache/playlists.lua（一个 `return { ... }` 的 Lua 表），读回用 DML 保存的 loadstring。

local mod = get_mod("TidePlayer")
local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")

mod._modules = mod._modules or {}

if mod._modules.playlists then
	return mod._modules.playlists
end

local Playlists = {}

mod._modules.playlists = Playlists

local _list = nil

local function file_path()
	return Util.cache_dir() .. "playlists.lua"
end

local function parse_file()
	local content = Util.read_file(file_path())

	if not content or content == "" then
		return {}
	end

	local loadstring = Mods and Mods.lua and Mods.lua.loadstring or loadstring
	local chunk = loadstring(content)

	if not chunk then
		return {}
	end

	local ok, data = pcall(chunk)

	if ok and type(data) == "table" then
		return data
	end

	return {}
end

local function save()
	local lines = {
		"return {",
	}

	for i = 1, #_list do
		local entry = _list[i]

		lines[#lines + 1] = string.format(
			"  { id = %d, name = %q, count = %d, url = %q, updated = %d },",
			tonumber(entry.id) or 0,
			entry.name or "",
			tonumber(entry.count) or 0,
			entry.url or "",
			tonumber(entry.updated) or 0
		)
	end

	lines[#lines + 1] = "}"

	Util.write_file(file_path(), table.concat(lines, "\n"))
end

Playlists.load = function()
	if not _list then
		_list = parse_file()
	end

	return _list
end

Playlists.list = function()
	return Playlists.load()
end

Playlists.get = function(id)
	local list = Playlists.load()

	for i = 1, #list do
		if list[i].id == id then
			return list[i]
		end
	end

	return nil
end

Playlists.add = function(playlist, url)
	if not playlist or not playlist.id or not url then
		return
	end

	local list = Playlists.load()

	-- 用链接去重：歌单和专辑的 id 是两套数字，可能撞
	for i = 1, #list do
		if list[i].url == url then
			list[i].id = playlist.id
			list[i].name = playlist.name
			list[i].count = #playlist.tracks
			list[i].updated = os.time()

			save()

			return
		end
	end

	table.insert(list, 1, {
		id = playlist.id,
		name = playlist.name,
		count = #playlist.tracks,
		url = url,
		updated = os.time(),
	})

	save()
end

Playlists.remove = function(id)
	local list = Playlists.load()

	for i = #list, 1, -1 do
		if list[i].id == id then
			table.remove(list, i)
		end
	end

	save()
end

return Playlists
