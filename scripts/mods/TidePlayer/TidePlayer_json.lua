-- TidePlayer_json.lua
-- 一个够用的 JSON 解码器（Lua 5.1 / LuaJIT）。
--
-- 只做解码，因为网易云的接口只发 JSON 过来。对象 → table，数组 → table（1 起），
-- null → nil（键直接不写），字符串按 JSON 规则还原 \uXXXX（含代理对）。
-- 解码失败返回 nil + 出错位置，调用方自己决定要不要当错误处理。

local Json = {}

-- JSON null 与「没这个字段」在 Lua 里都是 nil，数组里的 null 会空洞化。
-- 解出来的 null 用这个哨兵值表示；调用方不需要时直接忽略即可。
Json.null = setmetatable({}, {
	__tostring = function()
		return "json.null"
	end,
})

local byte = string.byte
local sub = string.sub
local concat = table.concat

local ESCAPE_MAP = {
	['"'] = '"',
	["\\"] = "\\",
	["/"] = "/",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
}

-- 把码点编码成 UTF-8。>= 0x10000 的码点由调用方先拆成代理对。
local function utf8_char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(
			0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40,
			0x80 + cp % 0x40
		)
	else
		return string.char(
			0xF0 + math.floor(cp / 0x40000),
			0x80 + math.floor(cp / 0x1000) % 0x40,
			0x80 + math.floor(cp / 0x40) % 0x40,
			0x80 + cp % 0x40
		)
	end
end

local function skip_ws(str, i, n)
	while i <= n do
		local c = byte(str, i)

		if c == 32 or c == 9 or c == 10 or c == 13 then
			i = i + 1
		else
			break
		end
	end

	return i
end

-- 字符串：进入时 i 指向开头的引号
local function decode_string(str, i, n)
	local parts = {}
	i = i + 1
	local chunk_start = i

	while true do
		if i > n then
			return nil, nil, "unterminated string"
		end

		local c = byte(str, i)

		if c == 34 then -- '"'
			parts[#parts + 1] = sub(str, chunk_start, i - 1)

			return concat(parts), i + 1
		elseif c == 92 then -- '\'
			parts[#parts + 1] = sub(str, chunk_start, i - 1)

			local esc = sub(str, i + 1, i + 1)

			if esc == "u" then
				local hex = sub(str, i + 2, i + 5)
				local cp = tonumber(hex, 16)

				if not cp then
					return nil, nil, "bad \\u escape"
				end

				i = i + 6

				-- 代理对：高代理 + 后随的低代理合成一个码点
				if cp >= 0xD800 and cp <= 0xDBFF then
					local low_hex = sub(str, i + 2, i + 5)
					local low = tonumber(low_hex, 16)

					if string.sub(str, i, i + 1) == "\\u" and low and low >= 0xDC00 and low <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
						i = i + 6
					end
				end

				parts[#parts + 1] = utf8_char(cp)
			else
				local mapped = ESCAPE_MAP[esc]

				if not mapped then
					return nil, nil, "bad escape"
				end

				parts[#parts + 1] = mapped
				i = i + 2
			end

			chunk_start = i
		else
			i = i + 1
		end
	end
end

local function decode_value(str, i, n, depth)
	i = skip_ws(str, i, n)

	if i > n then
		return nil, nil, "unexpected end"
	end

	if depth > 64 then
		return nil, nil, "too deep"
	end

	local c = byte(str, i)

	if c == 123 then -- '{'
		local obj = {}
		i = skip_ws(str, i + 1, n)

		if byte(str, i) == 125 then
			return obj, i + 1
		end

		while true do
			i = skip_ws(str, i, n)

			if byte(str, i) ~= 34 then
				return nil, nil, "expected object key"
			end

			local key
			key, i = decode_string(str, i, n)

			if not key then
				return nil, nil, "bad object key"
			end

			i = skip_ws(str, i, n)

			if byte(str, i) ~= 58 then -- ':'
				return nil, nil, "expected ':'"
			end

			local value
			value, i = decode_value(str, i + 1, n, depth + 1)

			if i == nil then
				return nil, nil, "bad object value"
			end

			if value ~= Json.null then
				obj[key] = value
			end

			i = skip_ws(str, i, n)
			c = byte(str, i)

			if c == 125 then
				return obj, i + 1
			elseif c == 44 then
				i = i + 1
			else
				return nil, nil, "expected ',' or '}'"
			end
		end
	elseif c == 91 then -- '['
		local arr = {}
		i = skip_ws(str, i + 1, n)

		if byte(str, i) == 93 then
			return arr, i + 1
		end

		while true do
			local value, next_i = decode_value(str, i, n, depth + 1)

			if next_i == nil then
				return nil, nil, "bad array value"
			end

			arr[#arr + 1] = value
			i = skip_ws(str, next_i, n)
			c = byte(str, i)

			if c == 93 then
				return arr, i + 1
			elseif c == 44 then
				i = i + 1
			else
				return nil, nil, "expected ',' or ']'"
			end
		end
	elseif c == 34 then
		return decode_string(str, i, n)
	elseif c == 116 then -- t
		if sub(str, i, i + 3) == "true" then
			return true, i + 4
		end
	elseif c == 102 then -- f
		if sub(str, i, i + 4) == "false" then
			return false, i + 5
		end
	elseif c == 110 then -- n
		if sub(str, i, i + 3) == "null" then
			return Json.null, i + 4
		end
	elseif c == 45 or (c >= 48 and c <= 57) then
		local number_text = string.match(str, "^-?%d+%.?%d*[eE]?[+-]?%d*", i)
		local value = tonumber(number_text)

		if not value then
			return nil, nil, "bad number"
		end

		return value, i + #number_text
	end

	return nil, nil, "unexpected character"
end

function Json.decode(str)
	if type(str) ~= "string" or str == "" then
		return nil, "empty input"
	end

	local value, next_i, err = decode_value(str, 1, #str, 0)

	if next_i == nil then
		return nil, err or "parse error"
	end

	return value
end

return Json
