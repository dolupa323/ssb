--!strict
-- 이 플레이어의 저장되는 자료(원본의 localStorage): 설정 · 본 안내 · 고른 난이도 · 난이도별 최고 기록.
--  들어올 때 서버에서 한 번 읽고(Store.load), 바뀔 때마다 서버로 보낸다. 서버가 없거나 답이 없어도 기본값으로 돈다.
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Net"))

local Store = {}
Store.set = table.clone(Net.SET_DEFAULT) :: Net.Settings -- 원본 SET
Store.seen = {} :: { [string]: number } -- 원본 seen
Store.diff = Net.DIFF_DEFAULT -- 원본 diff
Store.best = {} :: { [string]: Net.Record } -- 원본 loadBest(d) — 열쇠는 "0".."3"
Store.loaded = false -- 서버에서 읽었다
Store.CONNECT_WAIT = 6 -- 서버의 길을 기다리는 한도(초)
Store.LOAD_WAIT = 12 -- 읽기를 기다리는 한도(초) — 서버 쪽 한도(9초)보다 길게
Store.SET_DELAY = 0.4 -- 설정은 이만큼 모았다가 보낸다(음량 막대를 끌 때)

local remotes: Net.Remotes? = nil
local setPending = false

local function send(kind: string, value: any)
	local r = remotes
	if r then
		pcall(function()
			r.save:FireServer(kind, value)
		end)
	end
end

-- 서버에서 읽는다. 기다린다(한도가 있다). 실패하면 기본값 그대로
function Store.load()
	local r = Net.connect(Store.CONNECT_WAIT)
	if not r then
		warn("[ssb] 서버의 저장 길을 찾지 못했다 — 기본값으로 시작한다")
		return
	end
	remotes = r
	local result: any = nil
	local finished = false
	task.spawn(function()
		local ok, res = pcall(function()
			return r.load:InvokeServer()
		end)
		if ok then
			result = res
		end
		finished = true
	end)
	local t0 = os.clock()
	while not finished and os.clock() - t0 < Store.LOAD_WAIT do
		task.wait(0.05)
	end
	if type(result) ~= "table" then
		return
	end
	Store.set = Net.mergeSettings(result.set)
	Store.seen = {}
	if type(result.seen) == "table" then
		for _, k in Net.HINT_KEYS do
			if result.seen[k] then
				Store.seen[k] = 1
			end
		end
	end
	if Net.isDiff(result.diff) then
		Store.diff = result.diff
	end
	Store.best = {}
	if type(result.best) == "table" then
		for d = 0, Net.DIFF_COUNT - 1 do
			local rec = Net.cleanRecord(result.best[tostring(d)])
			if rec then
				Store.best[tostring(d)] = rec
			end
		end
	end
	Store.loaded = result.ok == true
end

-- 설정이 바뀌었다(원본 applySet(true)의 저장)
function Store.saveSettings()
	if setPending then
		return
	end
	setPending = true
	task.delay(Store.SET_DELAY, function()
		setPending = false
		send("set", table.clone(Store.set))
	end)
end

function Store.markSeen(key: string)
	Store.seen[key] = 1
	send("seen", key)
end

function Store.resetSeen()
	Store.seen = {}
	send("seenReset", nil)
end

function Store.setDiff(d: number)
	Store.diff = d
	send("diff", d)
end

function Store.loadBest(d: number): Net.Record?
	return Store.best[tostring(d)]
end

-- 끝난 판. 원본처럼 「더 나은 기록」일 때만 남긴다(서버도 같은 규칙으로 다시 본다)
function Store.submitRun(d: number, cur: Net.Record)
	if Net.better(cur, Store.best[tostring(d)]) then
		Store.best[tostring(d)] = cur
		send("run", { diff = d, t = cur.t, kills = cur.kills, level = cur.level, won = cur.won, zone = cur.zone })
	end
end

return Store
