-- mock 런타임의 공용 판: 모듈들이 서로를 여기에 걸어 두고 부른다(require가 돌지 않게).
--  바깥(node의 run.mjs)과는 표준 출력의 줄로 말한다: "@@M<종류> <JSON>" 한 줄이 한 건.
local R = {}

R.opts = {} -- 실행 옵션(main이 채운다)
R.RUNTIME = {} -- 런타임 파일의 이름(오류 자리를 사용자 코드로 돌릴 때 쓴다)
R.TYPEOF = {} -- 메타테이블 → typeof 이름
R.nativePrint = print
R.counts = { errors = 0, warns = 0, fails = 0 }
R.errorList = {} -- 지금까지의 오류(하네스가 읽는다)
R.warnList = {}
R.unmodelled = {} -- 흉내 내지 않는데 불린 것(한 번씩만 알린다)

function R.mark()
	local src = debug.info(2, "s")
	R.RUNTIME[src] = true
end
R.mark()

-- 사용자 코드의 자리에서 난 것처럼 오류를 낸다(런타임 안쪽 줄 번호가 아니라 부른 줄을 가리키게)
function R.raise(msg: string): never
	local lvl = 2
	while true do
		local src = debug.info(lvl, "s")
		if src == nil then
			lvl = 2
			break
		end
		if src ~= "[C]" and not R.RUNTIME[src] then
			break
		end
		lvl += 1
	end
	error(msg, lvl)
end

-- 역추적에서 런타임 안쪽 줄을 덜어 낸다
function R.cleanTrace(tb: string): string
	local out = {}
	for line in string.gmatch(tb, "[^\n]+") do
		local keep = true
		for src in R.RUNTIME do
			if string.sub(line, 1, #src) == src then
				keep = false
				break
			end
		end
		if keep and line ~= "[C]" and not string.find(line, "^%[C%]") then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

function R.emit(kind: string, payload: any)
	R.nativePrint("@@M" .. kind .. " " .. R.Json.encode(payload))
end

-- 비슷한 이름 찾기(오타 귀띔)
local function distance(a: string, b: string): number
	local la, lb = #a, #b
	if math.abs(la - lb) > 3 then
		return 99
	end
	local prev = table.create(lb + 1, 0)
	for j = 0, lb do
		prev[j + 1] = j
	end
	for i = 1, la do
		local cur = table.create(lb + 1, 0)
		cur[1] = i
		local ca = string.byte(a, i)
		for j = 1, lb do
			local cost = if ca == string.byte(b, j) then 0 else 1
			cur[j + 1] = math.min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
		end
		prev = cur
	end
	return prev[lb + 1]
end

function R.nearest(name: string, candidates: { [string]: any }): string?
	if type(name) ~= "string" then
		return nil
	end
	local best, bestD = nil, 99
	local low = string.lower(name)
	for cand in candidates do
		if type(cand) == "string" then
			local d = distance(low, string.lower(cand))
			if d < bestD then
				best, bestD = cand, d
			end
		end
	end
	if best and bestD <= math.max(1, math.min(3, #name // 3)) then
		return best
	end
	return nil
end

function R.hint(name: string, candidates: { [string]: any }): string
	local n = R.nearest(name, candidates)
	return if n then ' — 혹시 "' .. n .. '"?' else ""
end

-- 흉내 내지 않는 것을 한 번만 알린다
function R.note(key: string, text: string)
	if R.unmodelled[key] then
		return
	end
	R.unmodelled[key] = text
	R.emit("note", { key = key, text = text })
end

return R
