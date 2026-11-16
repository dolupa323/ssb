-- JSON 읽기 · 쓰기 (HttpService:JSONEncode/JSONDecode와 바깥으로 내보내는 줄에 쓴다)
local R = require("./rt")
R.mark()
local Json = {}
R.Json = Json

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function escChar(c: string): string
	return ESC[c] or string.format("\\u%04x", string.byte(c))
end

local function encodeString(s: string): string
	return '"' .. string.gsub(s, '[%c"\\\127]', escChar) .. '"'
end

local function encodeValue(v: any, out: { string }, seen: { [any]: boolean }, strict: boolean)
	local t = type(v)
	if t == "nil" then
		table.insert(out, "null")
	elseif t == "boolean" then
		table.insert(out, if v then "true" else "false")
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			table.insert(out, "null")
		elseif v % 1 == 0 and math.abs(v) < 1e15 then
			table.insert(out, string.format("%d", v))
		else
			table.insert(out, string.format("%.17g", v))
		end
	elseif t == "string" then
		table.insert(out, encodeString(v))
	elseif t == "table" then
		local mt = getmetatable(v)
		if mt and R.TYPEOF[mt] then
			table.insert(out, "null") -- Roblox 자료형 · 인스턴스는 null
			return
		end
		if seen[v] then
			if strict then
				error("tables cannot be cyclic", 0)
			end
			table.insert(out, "null")
			return
		end
		seen[v] = true
		local n = #v
		if n > 0 then
			table.insert(out, "[")
			for i = 1, n do
				if i > 1 then
					table.insert(out, ",")
				end
				encodeValue(v[i], out, seen, strict)
			end
			table.insert(out, "]")
		elseif next(v) == nil then
			table.insert(out, "[]")
		else
			table.insert(out, "{")
			local first = true
			-- 열쇠의 차례를 고르게(결과가 실행마다 같게)
			local keys = {}
			for k in v do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in keys do
				local kt = type(k)
				if kt == "string" or kt == "number" then
					if not first then
						table.insert(out, ",")
					end
					first = false
					table.insert(out, encodeString(tostring(k)))
					table.insert(out, ":")
					encodeValue(v[k], out, seen, strict)
				end
			end
			table.insert(out, "}")
		end
		seen[v] = nil
	else
		table.insert(out, "null")
	end
end

function Json.encode(v: any, strict: boolean?): string
	local out = {}
	encodeValue(v, out, {}, strict == true)
	return table.concat(out)
end

-- ---------- 읽기 ----------
local function fail(s: string, i: number, what: string): never
	error("Can't parse JSON: " .. what .. " (" .. tostring(i) .. "번째 글자)", 0)
end

local function skip(s: string, i: number): number
	local _, e = string.find(s, "^[ \t\r\n]*", i)
	return (e or i - 1) + 1
end

local decodeValue

local function decodeString(s: string, i: number): (string, number)
	-- i는 여는 따옴표 다음
	local parts = {}
	local j = i
	while true do
		local a = string.find(s, '["\\]', j)
		if not a then
			fail(s, i, "닫히지 않은 문자열")
		end
		if a > j then
			table.insert(parts, string.sub(s, j, a - 1))
		end
		local c = string.sub(s, a, a)
		if c == '"' then
			return table.concat(parts), a + 1
		end
		local e = string.sub(s, a + 1, a + 1)
		if e == "u" then
			local hex = string.sub(s, a + 2, a + 5)
			local code = tonumber(hex, 16)
			if not code then
				fail(s, a, "잘못된 \\u")
			end
			local nextAt = a + 6
			if code >= 0xD800 and code <= 0xDBFF and string.sub(s, nextAt, nextAt + 1) == "\\u" then
				local lo = tonumber(string.sub(s, nextAt + 2, nextAt + 5), 16)
				if lo and lo >= 0xDC00 and lo <= 0xDFFF then
					code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
					nextAt += 6
				end
			end
			table.insert(parts, utf8.char(code))
			j = nextAt
		else
			local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
			local r = map[e]
			if not r then
				fail(s, a, "잘못된 이스케이프")
			end
			table.insert(parts, r)
			j = a + 2
		end
	end
end

decodeValue = function(s: string, i: number): (any, number)
	i = skip(s, i)
	local c = string.sub(s, i, i)
	if c == "{" then
		local obj = {}
		i = skip(s, i + 1)
		if string.sub(s, i, i) == "}" then
			return obj, i + 1
		end
		while true do
			i = skip(s, i)
			if string.sub(s, i, i) ~= '"' then
				fail(s, i, "열쇠가 와야 한다")
			end
			local key
			key, i = decodeString(s, i + 1)
			i = skip(s, i)
			if string.sub(s, i, i) ~= ":" then
				fail(s, i, "':'가 와야 한다")
			end
			local val
			val, i = decodeValue(s, i + 1)
			obj[key] = val
			i = skip(s, i)
			local d = string.sub(s, i, i)
			if d == "," then
				i += 1
			elseif d == "}" then
				return obj, i + 1
			else
				fail(s, i, "',' 또는 '}'가 와야 한다")
			end
		end
	elseif c == "[" then
		local arr = {}
		i = skip(s, i + 1)
		if string.sub(s, i, i) == "]" then
			return arr, i + 1
		end
		local n = 0
		while true do
			local val
			val, i = decodeValue(s, i)
			n += 1
			arr[n] = val
			i = skip(s, i)
			local d = string.sub(s, i, i)
			if d == "," then
				i += 1
			elseif d == "]" then
				return arr, i + 1
			else
				fail(s, i, "',' 또는 ']'가 와야 한다")
			end
		end
	elseif c == '"' then
		return decodeString(s, i + 1)
	elseif string.sub(s, i, i + 3) == "true" then
		return true, i + 4
	elseif string.sub(s, i, i + 4) == "false" then
		return false, i + 5
	elseif string.sub(s, i, i + 3) == "null" then
		return nil, i + 4
	else
		local a, e = string.find(s, "^-?%d+%.?%d*[eE]?[+-]?%d*", i)
		if not a then
			fail(s, i, "알 수 없는 값")
		end
		local num = tonumber(string.sub(s, a, e))
		if not num then
			fail(s, i, "잘못된 수")
		end
		return num, (e :: number) + 1
	end
end

function Json.decode(s: string): any
	if type(s) ~= "string" then
		error("Can't parse JSON", 0)
	end
	local v, i = decodeValue(s, 1)
	i = skip(s, i)
	if i <= #s then
		fail(s, i, "값 뒤에 남은 글자")
	end
	return v
end

return Json
