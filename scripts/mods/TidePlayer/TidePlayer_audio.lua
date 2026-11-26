-- TidePlayer_audio.lua
-- 音频后端：tide_audio.dll（同目录的 C 插件，minimp3 解码 + waveOut 输出）。
--
-- 为什么不用 MCI：暗潮进程里 MCI 的 mpegvideo 驱动初始化不起来
-- （MCIERR「初始化 MCI 时发生问题」，PowerShell/Python 单独进程里却正常，
-- 是进程级的 DirectShow 状态问题）。waveOut 在这个进程里是好的，
-- RimWorldAlerts 的提示音就靠它，所以换成自己解码 + waveOut。
--
-- 为什么不用 ffplay：那要用户另装 Audio Plugin + Darktide Local Server，
-- 而且一个播放器拖两个依赖不值。

local mod = get_mod("TidePlayer")
local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")

-- io_dofile 每次执行都会新建一份模块实例，而 DLL 只该被初始化一次，
-- 所以这里全 mod 共用一个实例。
mod._modules = mod._modules or {}

if mod._modules.audio then
	return mod._modules.audio
end

local Audio = {}

mod._modules.audio = Audio

local ffi = Mods and Mods.lua and Mods.lua.ffi

local library = nil
local init_error = nil
local ready = false
local current_source = nil

pcall(function()
	ffi.cdef([[
		typedef unsigned short TP_WCHAR;

		int TaInit(void);
		int TaPlayFile(const TP_WCHAR* path, int volume);
		int TaPause(void);
		int TaResume(void);
		int TaStop(void);
		int TaSetVolume(int volume);
		int TaState(void);
		int TaPosition(void);
		int TaLength(void);
		int TaLevel(void);
		void TaGetSpectrum(int* out, int count);
		const TP_WCHAR* TaLastError(void);
		void TaShutdown(void);
	]])
end)

local function dll_path()
	local game = Util.game_dir()

	if not game then
		return nil
	end

	return game .. "\\mods\\TidePlayer\\tide_audio.dll"
end

local function init()
	if ready then
		return true
	end

	if init_error then
		return false
	end

	if not ffi then
		init_error = "LuaJIT ffi unavailable"

		return false
	end

	local path = dll_path()

	if not path then
		init_error = "could not resolve game directory"

		return false
	end

	if not Util.file_exists(path) then
		init_error = "tide_audio.dll missing"

		return false
	end

	local ok, loaded = pcall(ffi.load, path)

	if not ok or not loaded then
		init_error = "tide_audio.dll failed to load: " .. tostring(loaded)

		return false
	end

	library = loaded

	local init_ok, result = pcall(library.TaInit)

	if not init_ok or tonumber(result) ~= 0 then
		init_error = "TaInit failed: " .. tostring(init_ok and result or init_ok)

		return false
	end

	ready = true

	return true
end

local function last_error()
	if not library then
		return "audio library not loaded"
	end

	local ok, text = pcall(library.TaLastError)

	if ok and text then
		return Util.from_wide(text, 512)
	end

	return "unknown audio error"
end

-- ############################## 对外接口 ##############################

Audio.available = function()
	return init()
end

Audio.init_error = function()
	if init() then
		return nil
	end

	return init_error
end

Audio.current_source = function()
	return current_source
end

-- 播放一个本地 mp3 文件。成功返回 true，失败返回 nil, err。
Audio.play = function(path, volume)
	if not path or path == "" then
		return nil, "empty path"
	end

	if not init() then
		return nil, init_error
	end

	local wide = Util.to_wide(path)

	if not wide then
		return nil, "could not encode path"
	end

	local ok, result = pcall(library.TaPlayFile, wide, math.floor(volume or 700))

	if not ok then
		current_source = nil

		return nil, tostring(result)
	end

	result = tonumber(result) or -1

	if result ~= 0 then
		current_source = nil

		return nil, last_error()
	end

	current_source = path

	return true
end

Audio.stop = function()
	if not init() then
		return
	end

	current_source = nil

	pcall(library.TaStop)
end

Audio.pause = function()
	if not init() then
		return false
	end

	local ok, result = pcall(library.TaPause)

	return ok and tonumber(result) == 0
end

Audio.resume = function()
	if not init() then
		return false
	end

	local ok, result = pcall(library.TaResume)

	return ok and tonumber(result) == 0
end

Audio.set_volume = function(volume)
	if not init() then
		return false
	end

	local ok, result = pcall(library.TaSetVolume, math.floor(volume))

	return ok and tonumber(result) == 0
end

-- "playing" / "paused" / "stopped" / nil（没有活动曲目）
Audio.state = function()
	if not init() then
		return nil
	end

	local ok, state = pcall(library.TaState)

	if not ok then
		return nil
	end

	state = tonumber(state)

	if state == 1 then
		return "playing"
	elseif state == 2 then
		return "paused"
	elseif state == 3 then
		return "stopped"
	end

	return nil
end

-- 返回 0..1 的进度，以及位置和时长的毫秒数
Audio.progress = function()
	if not init() then
		return nil
	end

	local ok_position, position = pcall(library.TaPosition)
	local ok_length, length = pcall(library.TaLength)

	if not ok_position or not ok_length then
		return nil
	end

	position = tonumber(position) or 0
	length = tonumber(length) or 0

	if length <= 0 then
		return nil
	end

	return position / length, position, length
end

-- 当前 PCM 峰值电平 0..1000；没有在播或老 DLL 没有这个导出时返回 0
Audio.level = function()
	if not init() then
		return 0
	end

	local ok, value = pcall(library.TaLevel)

	if ok then
		return tonumber(value) or 0
	end

	return 0
end

-- 24 个频段的能量（0..1000），返回 ffi 的 int[24]；没在播或老 DLL 没有导出时返回 nil
local spectrum_buffer = nil

Audio.spectrum = function()
	if not init() then
		return nil
	end

	if not spectrum_buffer then
		spectrum_buffer = ffi.new("int[24]")
	end

	local ok = pcall(library.TaGetSpectrum, spectrum_buffer, 24)

	if not ok then
		return nil
	end

	return spectrum_buffer
end

return Audio
