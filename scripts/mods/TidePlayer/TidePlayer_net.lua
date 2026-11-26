-- TidePlayer_net.lua
-- 后台下载：CreateProcessW 起一个隐藏窗口的 curl，写进 cache 目录，
-- update 里用 WaitForSingleObject 看它有没有退出，退出就算完成。
--
-- 为什么不用 io.popen / os.execute：那两个会从游戏进程里拉一个带控制台的
-- cmd.exe，全屏游戏里会闪一下黑框。CreateProcessW + CREATE_NO_WINDOW 不会。
--
-- curl.exe 是 Windows 10 1803 以后自带的，不需要用户另外装东西。

local mod = get_mod("TidePlayer")
local Util = mod:io_dofile("TidePlayer/scripts/mods/TidePlayer/TidePlayer_util")

-- io_dofile 每次执行都会新建一份模块实例，而下载任务是状态，必须全 mod 共用一份。
-- 同一进程里所有引用都从这里拿。
mod._modules = mod._modules or {}

if mod._modules.net then
	return mod._modules.net
end

local Net = {}

mod._modules.net = Net

local ffi = Mods and Mods.lua and Mods.lua.ffi

local CREATE_NO_WINDOW = 0x08000000
local WAIT_OBJECT_0 = 0
local WAIT_TIMEOUT = 258
local FETCH_TIMEOUT_MS = 35000

local kernel32
local curl_path
local jobs = {}
local job_counter = 0

pcall(function()
	ffi.cdef([[
		typedef unsigned short TP_WCHAR;
		typedef void* TP_HANDLE;
		typedef unsigned long TP_DWORD;
		typedef unsigned char TP_BYTE;

		typedef struct {
			TP_DWORD cb;
			char* lpReserved;
			char* lpDesktop;
			char* lpTitle;
			TP_DWORD dwX;
			TP_DWORD dwY;
			TP_DWORD dwXSize;
			TP_DWORD dwYSize;
			TP_DWORD dwXCountChars;
			TP_DWORD dwYCountChars;
			TP_DWORD dwFillAttribute;
			TP_DWORD dwFlags;
			unsigned short wShowWindow;
			unsigned short cbReserved2;
			TP_BYTE* lpReserved2;
			void* hStdInput;
			void* hStdOutput;
			void* hStdError;
		} TP_STARTUPINFOA;

		typedef struct {
			void* hProcess;
			void* hThread;
			TP_DWORD dwProcessId;
			TP_DWORD dwThreadId;
		} TP_PROCESS_INFO;

		int CreateProcessW(const TP_WCHAR* lpApplicationName, TP_WCHAR* lpCommandLine, void* lpProcessAttributes, void* lpThreadAttributes, int bInheritHandles, TP_DWORD dwCreationFlags, void* lpEnvironment, const TP_WCHAR* lpCurrentDirectory, TP_STARTUPINFOA* lpStartupInfo, TP_PROCESS_INFO* lpProcessInformation);
		TP_DWORD WaitForSingleObject(TP_HANDLE hHandle, TP_DWORD dwMilliseconds);
		int CloseHandle(TP_HANDLE hObject);
		TP_DWORD GetTickCount();
	]])
end)

local function init()
	if kernel32 then
		return true
	end

	if not ffi then
		return false
	end

	local ok, lib = pcall(ffi.load, "kernel32")

	if not ok then
		return false
	end

	kernel32 = lib

	return true
end

local function find_curl()
	if curl_path then
		return curl_path
	end

	local candidates = {
		"C:\\Windows\\System32\\curl.exe",
		"C:\\Windows\\SysWOW64\\curl.exe",
	}

	for i = 1, #candidates do
		if Util.file_exists(candidates[i]) then
			curl_path = candidates[i]

			return curl_path
		end
	end

	-- 交给 CreateProcessW 自己按 PATH 找
	curl_path = "curl.exe"

	return curl_path
end

-- ############################## 启动 ##############################

local function spawn(args)
	if not init() then
		return nil, "kernel32 unavailable"
	end

	local exe = find_curl()
	local command_line = '"' .. exe .. '" ' .. args
	local command_w = Util.to_wide(command_line)

	if not command_w then
		return nil, "could not encode command line"
	end

	local startup_info = ffi.new("TP_STARTUPINFOA")
	startup_info.cb = ffi.sizeof("TP_STARTUPINFOA")

	local process_info = ffi.new("TP_PROCESS_INFO")
	local application = Util.to_wide(exe)

	local ok, result = pcall(
		kernel32.CreateProcessW,
		application,
		command_w,
		nil,
		nil,
		0,
		CREATE_NO_WINDOW,
		nil,
		nil,
		startup_info,
		process_info
	)

	if not ok then
		return nil, tostring(result)
	end

	result = tonumber(result) or 0

	if result == 0 then
		return nil, "CreateProcessW failed (curl not found?)"
	end

	local process = process_info.hProcess
	local thread = process_info.hThread

	if thread ~= nil then
		kernel32.CloseHandle(thread)
	end

	return process, nil
end

-- ############################## 对外接口 ##############################

-- 下载 url 到 out_path；完成后在 update 里回调 on_done({ ok, path, error })
Net.fetch = function(url, out_path, on_done)
	if not url or url == "" then
		if on_done then
			on_done({ ok = false, error = "empty url" })
		end

		return nil
	end

	if not init() then
		if on_done then
			on_done({ ok = false, error = "net unavailable" })
		end

		return nil
	end

	Util.ensure_dir(Util.cache_dir())

	-- 上次残留的同名文件先删掉，免得 curl 失败时读到旧内容
	Util.delete_file(out_path)

	-- -g 关掉 curl 的 URL globbing：song/detail 的 ids=[1,2,3] 会被当成字符范围
	local args = string.format(
		'-g -s -L -f --connect-timeout 10 --max-time 25 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36" -H "Referer: https://music.163.com/" -o "%s" "%s"',
		out_path,
		url
	)

	local process, err = spawn(args)

	if not process then
		if on_done then
			on_done({ ok = false, error = err })
		end

		return nil
	end

	job_counter = job_counter + 1

	local job = {
		id = job_counter,
		url = url,
		path = out_path,
		process = process,
		started = tonumber(kernel32.GetTickCount()) or 0,
		on_done = on_done,
		done = false,
	}

	jobs[job_counter] = job

	return job.id
end

Net.update = function()
	if not init() then
		return
	end

	local now = tonumber(kernel32.GetTickCount()) or 0
	local finished = {}

	for id, job in pairs(jobs) do
		if job.done then
			finished[#finished + 1] = id
		else
			local state = tonumber(kernel32.WaitForSingleObject(job.process, 0))

			if state == WAIT_OBJECT_0 then
				job.done = true
				kernel32.CloseHandle(job.process)
				job.process = nil
				finished[#finished + 1] = id
			elseif now - job.started > FETCH_TIMEOUT_MS then
				job.done = true
				job.timed_out = true
				kernel32.CloseHandle(job.process)
				job.process = nil
				finished[#finished + 1] = id
			end
		end
	end

	-- 回调放到最后统一发，避免回调里又发起新的 fetch 把 jobs 改了
	for i = 1, #finished do
		local id = finished[i]
		local job = jobs[id]

		jobs[id] = nil

		if job then
			local result

			if job.timed_out then
				result = {
					ok = false,
					error = "timeout",
				}
			else
				local content = Util.read_file(job.path)

				if content and #content > 0 then
					result = {
						ok = true,
						path = job.path,
						body = content,
						url = job.url,
					}
				else
					result = {
						ok = false,
						error = "empty response",
					}
				end
			end

			if job.on_done then
				local callback_ok, callback_err = pcall(job.on_done, result)

				if not callback_ok then
					mod:error("fetch callback failed: %s", tostring(callback_err))
				end
			end
		end
	end
end

Net.cancel_all = function()
	if not init() then
		return
	end

	for id, job in pairs(jobs) do
		if job.process then
			pcall(kernel32.CloseHandle, job.process)
		end

		jobs[id] = nil
	end
end

-- 直接读一个已经存在的缓存文件（不发起下载）
Net.read_cached = function(path)
	return Util.read_file(path)
end

Net.curl = function()
	return find_curl()
end

return Net
