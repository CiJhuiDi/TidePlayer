-- TidePlayer_util.lua
-- 编码转换、路径和几个到处要用的小工具。
--
-- ffi 的类型声明是全 VM 共享的，这里和 audio / net 用的是同一批 TP_ 前缀类型；
-- 任何模块先加载都能工作（重复 cdef 用 pcall 包住）。

local Util = {}

local ffi = Mods and Mods.lua and Mods.lua.ffi
local lua_io = Mods and Mods.lua and Mods.lua.io

pcall(function()
	ffi.cdef([[
		typedef unsigned short TP_WCHAR;
		typedef void* TP_HANDLE;
		typedef unsigned long TP_DWORD;

		TP_DWORD GetCurrentDirectoryW(TP_DWORD nBufferLength, TP_WCHAR* lpBuffer);
		int CreateDirectoryW(const TP_WCHAR* lpPathName, void* lpSecurityAttributes);

		typedef struct {
			unsigned long dwFileAttributes;
			unsigned long ftCreationLow;
			unsigned long ftCreationHigh;
			unsigned long ftLastAccessLow;
			unsigned long ftLastAccessHigh;
			unsigned long ftLastWriteLow;
			unsigned long ftLastWriteHigh;
			unsigned long nFileSizeHigh;
			unsigned long nFileSizeLow;
			unsigned long dwReserved0;
			unsigned long dwReserved1;
			unsigned short cFileName[260];
			unsigned short cAlternateFileName[14];
		} TP_FIND_DATAW;

		void* FindFirstFileW(const TP_WCHAR* lpFileName, TP_FIND_DATAW* lpFindFileData);
		int FindNextFileW(void* hFindFile, TP_FIND_DATAW* lpFindFileData);
		int FindClose(void* hFindFile);
		int DeleteFileW(const TP_WCHAR* lpFileName);

		int OpenClipboard(void* hWndNewOwner);
		void* GetClipboardData(unsigned int uFormat);
		void* GlobalLock(TP_HANDLE hMem);
		int GlobalUnlock(TP_HANDLE hMem);
		int CloseClipboard();
	]])
end)

-- ############################## 编码 ##############################

local function utf8_to_utf16(str)
	local out = {}
	local i = 1
	local n = #str

	while i <= n do
		local c = string.byte(str, i)
		local cp

		if c < 0x80 then
			cp = c
			i = i + 1
		elseif c < 0xE0 then
			cp = (c - 0xC0) * 0x40 + (string.byte(str, i + 1) - 0x80)
			i = i + 2
		elseif c < 0xF0 then
			cp = (c - 0xE0) * 0x1000 + (string.byte(str, i + 1) - 0x80) * 0x40 + (string.byte(str, i + 2) - 0x80)
			i = i + 3
		else
			cp = (c - 0xF0) * 0x40000 + (string.byte(str, i + 1) - 0x80) * 0x1000
				+ (string.byte(str, i + 2) - 0x80) * 0x40 + (string.byte(str, i + 3) - 0x80)
			i = i + 4
		end

		if cp >= 0x10000 then
			cp = cp - 0x10000
			out[#out + 1] = 0xD800 + math.floor(cp / 0x400)
			out[#out + 1] = 0xDC00 + (cp % 0x400)
		else
			out[#out + 1] = cp
		end
	end

	return out
end

local function wide_to_utf8(buffer, length)
	local parts = {}
	local i = 0
	local limit = length or 4096

	while i < limit do
		local code = tonumber(buffer[i])

		if not code or code == 0 then
			break
		end

		if code < 0x80 then
			parts[#parts + 1] = string.char(code)
		elseif code < 0x800 then
			parts[#parts + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
		elseif code < 0x10000 then
			parts[#parts + 1] = string.char(
				0xE0 + math.floor(code / 0x1000),
				0x80 + math.floor(code / 0x40) % 0x40,
				0x80 + code % 0x40
			)
		end

		i = i + 1
	end

	return table.concat(parts)
end

-- 字符串 → LuaJIT 可写的 wchar_t 缓冲区（调用方负责保持引用直到调用结束）
function Util.to_wide(str)
	if not ffi then
		return nil
	end

	local cps = utf8_to_utf16(str or "")
	local buffer = ffi.new("TP_WCHAR[?]", #cps + 1)

	for i = 1, #cps do
		buffer[i - 1] = cps[i]
	end

	buffer[#cps] = 0

	return buffer
end

function Util.from_wide(buffer, length)
	if not ffi then
		return ""
	end

	return wide_to_utf8(buffer, length)
end

-- ############################## 路径 ##############################

-- 游戏进程的工作目录是 <game>/binaries，mods 在上一级。
function Util.game_dir()
	if not ffi then
		return nil
	end

	local ok, kernel32 = pcall(ffi.load, "kernel32")

	if not ok then
		return nil
	end

	local buffer = ffi.new("TP_WCHAR[?]", 1024)
	local length = kernel32.GetCurrentDirectoryW(1024, buffer)

	if not length or length == 0 then
		return nil
	end

	local cwd = wide_to_utf8(buffer, 1024)

	-- cwd 是 ...\binaries，去掉最后一段
	cwd = string.gsub(cwd, "\\+$", "")

	return string.match(cwd, "^(.*)\\[^\\]+$") or cwd
end

function Util.cache_dir()
	local game = Util.game_dir()

	if not game then
		return "..\\mods\\TidePlayer\\cache\\"
	end

	return game .. "\\mods\\TidePlayer\\cache\\"
end

function Util.ensure_dir(path)
	if not ffi or not path or path == "" then
		return false
	end

	local ok, kernel32 = pcall(ffi.load, "kernel32")

	if not ok then
		return false
	end

	local wide = Util.to_wide(path)
	local created = kernel32.CreateDirectoryW(wide, nil)

	return created ~= 0
end

function Util.file_exists(path)
	if not lua_io or not path then
		return false
	end

	local ok, file = pcall(lua_io.open, path, "rb")

	if ok and file then
		pcall(file.close, file)

		return true
	end

	return false
end

function Util.file_size(path)
	if not lua_io or not path then
		return nil
	end

	local ok, file = pcall(lua_io.open, path, "rb")

	if not ok or not file then
		return nil
	end

	local seek_ok, size = pcall(file.seek, file, "end")

	pcall(file.close, file)

	if seek_ok and type(size) == "number" then
		return size
	end

	return nil
end

function Util.read_file(path)
	if not lua_io or not path then
		return nil
	end

	local ok, file = pcall(lua_io.open, path, "rb")

	if not ok or not file then
		return nil
	end

	local read_ok, content = pcall(file.read, file, "*all")

	pcall(file.close, file)

	if read_ok and type(content) == "string" then
		return content
	end

	return nil
end

function Util.read_head(path, count)
	if not lua_io or not path then
		return nil
	end

	local ok, file = pcall(lua_io.open, path, "rb")

	if not ok or not file then
		return nil
	end

	local read_ok, content = pcall(file.read, file, count)

	pcall(file.close, file)

	if read_ok and type(content) == "string" then
		return content
	end

	return nil
end

function Util.write_file(path, content)
	if not lua_io or not path then
		return false
	end

	local ok, file = pcall(lua_io.open, path, "wb")

	if not ok or not file then
		return false
	end

	local write_ok = pcall(file.write, file, content)

	pcall(file.close, file)

	return write_ok
end

function Util.delete_file(path)
	if not lua_io or not path then
		return false
	end

	local ok = pcall(lua_io.remove, path)

	return ok
end

-- ############################## 文本 ##############################

function Util.trim(str)
	if not str then
		return ""
	end

	return (string.gsub(str, "^%s*(.-)%s*$", "%1"))
end

-- 按字符截断（UTF-8 安全），给列表行用
function Util.clip(str, max_chars)
	str = str or ""

	local count = 0
	local i = 1
	local n = #str

	while i <= n and count < max_chars do
		local c = string.byte(str, i)

		if c < 0x80 then
			i = i + 1
		elseif c < 0xE0 then
			i = i + 2
		elseif c < 0xF0 then
			i = i + 3
		else
			i = i + 4
		end

		count = count + 1
	end

	if i <= n then
		return string.sub(str, 1, i - 1) .. "…"
	end

	return str
end

-- 读剪贴板里的 Unicode 文本。用户复制的网易云分享文案里就带着链接。
function Util.clipboard_text()
	if not ffi then
		return nil
	end

	local ok_user, user32 = pcall(ffi.load, "user32")
	local ok_kernel, kernel32 = pcall(ffi.load, "kernel32")

	if not ok_user or not ok_kernel then
		return nil
	end

	if user32.OpenClipboard(nil) == 0 then
		return nil
	end

	local handle = user32.GetClipboardData(13) -- CF_UNICODETEXT
	local text = nil

	if handle ~= nil and ffi.cast("intptr_t", handle) ~= 0 then
		local pointer = kernel32.GlobalLock(handle)

		if pointer ~= nil then
			text = wide_to_utf8(ffi.cast("TP_WCHAR*", pointer), 32768)

			kernel32.GlobalUnlock(handle)
		end
	end

	user32.CloseClipboard()

	if text and #text > 0 then
		return text
	end

	return nil
end

-- 缓存目录里的文件清单（只列文件，不递归子目录）
local function list_cache_files()
	if not ffi then
		return {}
	end

	local ok, kernel32 = pcall(ffi.load, "kernel32")

	if not ok then
		return {}
	end

	local dir = Util.cache_dir()
	local data = ffi.new("TP_FIND_DATAW")
	local handle = kernel32.FindFirstFileW(Util.to_wide(dir .. "*"), data)
	local files = {}

	if handle == nil or ffi.cast("intptr_t", handle) == -1 then
		return files
	end

	repeat
		local name = wide_to_utf8(data.cFileName, 260)

		if name ~= "." and name ~= ".." and name ~= "" then
			local attributes = tonumber(data.dwFileAttributes) or 0
			local is_directory = bit.band(attributes, 0x10) ~= 0

			if not is_directory then
				files[#files + 1] = {
					name = name,
					size = (tonumber(data.nFileSizeHigh) or 0) * 4294967296 + (tonumber(data.nFileSizeLow) or 0),
				}
			end
		end
	until kernel32.FindNextFileW(handle, data) == 0

	kernel32.FindClose(handle)

	return files
end

function Util.cache_stats()
	local files = list_cache_files()
	local stats = {
		count = 0,
		total = 0,
		songs = 0,
		song_bytes = 0,
	}

	for i = 1, #files do
		local file = files[i]

		stats.count = stats.count + 1
		stats.total = stats.total + file.size

		if string.match(file.name, "%.mp3$") then
			stats.songs = stats.songs + 1
			stats.song_bytes = stats.song_bytes + file.size
		end
	end

	return stats
end

-- 歌单索引和上次的链接不算缓存，清缓存时保留
local CACHE_KEEP = {
	["playlists.lua"] = true,
	["last_url.txt"] = true,
}

function Util.clear_cache()
	if not ffi then
		return 0
	end

	local ok, kernel32 = pcall(ffi.load, "kernel32")

	if not ok then
		return 0
	end

	local dir = Util.cache_dir()
	local files = list_cache_files()
	local removed = 0

	for i = 1, #files do
		local name = files[i].name

		if not CACHE_KEEP[name] then
			if kernel32.DeleteFileW(Util.to_wide(dir .. name)) ~= 0 then
				removed = removed + 1
			end
		end
	end

	return removed
end

function Util.format_size(bytes)
	bytes = tonumber(bytes) or 0

	if bytes >= 1024 * 1024 * 1024 then
		return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
	elseif bytes >= 1024 * 1024 then
		return string.format("%.1f MB", bytes / (1024 * 1024))
	elseif bytes >= 1024 then
		return string.format("%.0f KB", bytes / 1024)
	end

	return string.format("%d B", bytes)
end

-- 按视觉宽度截断：全角字算 1，半角算 0.5（16 号字下 1 单位约 16px）
function Util.clip_width(str, max_units)
	str = str or ""

	local units = 0
	local i = 1
	local n = #str

	while i <= n do
		local b = string.byte(str, i)
		local length

		if b < 0x80 then
			length = 1
		elseif b < 0xE0 then
			length = 2
		elseif b < 0xF0 then
			length = 3
		else
			length = 4
		end

		local width = (length >= 3) and 1 or 0.5

		if units + width > max_units then
			return string.sub(str, 1, i - 1) .. "…"
		end

		units = units + width
		i = i + length
	end

	return str
end

function Util.format_time(ms)
	ms = math.max(0, math.floor(ms or 0))

	local total_seconds = math.floor(ms / 1000)
	local minutes = math.floor(total_seconds / 60)
	local seconds = total_seconds % 60

	return string.format("%d:%02d", minutes, seconds)
end

return Util
