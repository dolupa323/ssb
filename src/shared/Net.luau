--!strict
-- 서버와 클라이언트가 주고받는 길 + 양쪽이 같이 쓰는 자료의 모양 · 검사.
--  원본은 localStorage에 넣던 것 넷: 설정(commute-set) · 본 안내(commute-tut) · 고른 난이도(commute-diff) · 난이도별 최고 기록(commute-best-v4-<d>).
--  서버(src/server)가 길을 만들고 DataStore에 저장한다. 클라이언트는 들어올 때 한 번 읽고, 바뀔 때마다 보낸다.
--   Load (RemoteFunction)  클라 → 서버: 내 자료를 달라 → { set, seen, diff, best, ok }
--   Save (RemoteEvent)     클라 → 서버: Save:FireServer(kind, value)
--        kind "set"   value = { music, sfx, fx, shake, hand, bloom }
--             "seen"  value = 안내 이름 하나("move" …)      "seenReset" (값 없음) = 안내를 처음부터
--             "diff"  value = 0..3
--             "run"   value = { diff, t, kills, level, won, zone } — 끝난 판. 서버가 「더 나은 기록」일 때만 받는다
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Sim = require(script.Parent.Sim) :: any

local Net = {}
Net.FOLDER = "SsbNet"

export type Settings = { music: number, sfx: number, fx: number, shake: number, hand: number, bloom: number }
export type Record = { t: number, kills: number, level: number, won: boolean, zone: number }
export type Data = { set: Settings, seen: { [string]: number }, diff: number, best: { [string]: Record } }

-- 설정: 원본 main.js의 SET
Net.SET_KEYS = { "music", "sfx", "fx", "shake", "hand", "bloom" }
Net.SET_DEFAULT = { music = 80, sfx = 80, fx = 2, shake = 1, hand = 0, bloom = 1 } :: Settings
Net.SET_MAX = { music = 100, sfx = 100, fx = 2, shake = 1, hand = 1, bloom = 1 } :: { [string]: number }
-- 안내 이름: 원본 main.js의 HINTS
Net.HINT_KEYS = { "move", "xp", "dash", "lane", "boss", "gates", "evo", "train", "doors", "esc" }
Net.DIFF_DEFAULT = 1
Net.DIFF_COUNT = #Sim.DIFFS

-- 기록의 한계(터무니없는 값을 거른다)
Net.MAX_T = 3 * 3600 -- 한 판의 시간(초)
Net.MAX_KILLS = 200000
Net.MAX_LEVEL = 999
Net.KILLS_PER_SEC = 60 -- 처치 수 ≤ 60 × 시간 + 300

local hintSet = {} :: { [string]: boolean }
for _, k in Net.HINT_KEYS do
	hintSet[k] = true
end

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v >= lo and v <= hi and v == math.floor(v)
end

-- 그 장소에 닿기까지 적어도 걸리는 시간: 앞 장소들의 「인파 버티기」 · 「열차 타기」 시간의 합 (규칙이 그보다 빨리 넘겨 주지 않는다)
local reach = {} :: { number } -- reach[zone + 1]
do
	local acc = 0
	for i, z in Sim.ZONES do
		reach[i] = acc
		local g = Sim.GATE[z.key]
		acc += (g.crowd or g.ride or 0)
	end
	reach[#Sim.ZONES + 1] = acc -- 도착(이김)
end
Net.REACH = reach

function Net.defaults(): Data
	return { set = table.clone(Net.SET_DEFAULT), seen = {}, diff = Net.DIFF_DEFAULT, best = {} }
end

function Net.isHint(k: any): boolean
	return type(k) == "string" and hintSet[k] == true
end

function Net.isDiff(v: any): boolean
	return isInt(v, 0, Net.DIFF_COUNT - 1)
end

-- 설정 표를 검사해 깨끗한 사본을 돌려준다(틀리면 nil). 모르는 칸은 버린다
function Net.cleanSettings(v: any): Settings?
	if type(v) ~= "table" then
		return nil
	end
	local out = {}
	for _, k in Net.SET_KEYS do
		local x = v[k]
		if not isInt(x, 0, Net.SET_MAX[k]) then
			return nil
		end
		out[k] = x
	end
	return out :: any
end

-- 저장돼 있던 설정을 읽을 때: 맞는 칸만 받고 나머지는 기본값(원본: typeof o[k] === 'number' 인 칸만 덮어쓴다)
function Net.mergeSettings(v: any): Settings
	local out = table.clone(Net.SET_DEFAULT) :: any
	if type(v) == "table" then
		for _, k in Net.SET_KEYS do
			if isInt(v[k], 0, Net.SET_MAX[k]) then
				out[k] = v[k]
			end
		end
	end
	return out
end

-- 기록 하나를 검사해 깨끗한 사본을 돌려준다(틀리면 nil, 까닭)
function Net.cleanRecord(v: any): (Record?, string?)
	if type(v) ~= "table" then
		return nil, "표가 아니다"
	end
	local t, kills, level, won, zone = v.t, v.kills, v.level, v.won, v.zone
	if type(t) ~= "number" or t ~= t or t < 0 or t > Net.MAX_T then
		return nil, "시간"
	end
	if not isInt(kills, 0, Net.MAX_KILLS) or kills > Net.KILLS_PER_SEC * t + 300 then
		return nil, "처치 수"
	end
	if not isInt(level, 1, Net.MAX_LEVEL) then
		return nil, "레벨"
	end
	if type(won) ~= "boolean" then
		return nil, "won"
	end
	if not isInt(zone, 0, #Sim.ZONES - 1) then
		return nil, "장소"
	end
	if won then
		if zone ~= #Sim.ZONES - 1 or t < reach[#Sim.ZONES + 1] then
			return nil, "도착하기에는 너무 이르다"
		end
	elseif t < reach[zone + 1] then
		return nil, "그 장소에 닿기에는 너무 이르다"
	end
	return { t = t, kills = kills, level = level, won = won, zone = zone }, nil
end

-- 원본 showEnd의 better: 새 기록 cur가 앞 기록 prev보다 나은가
function Net.better(cur: Record, prev: Record?): boolean
	if not prev then
		return true
	end
	if cur.won and not prev.won then
		return true
	end
	if cur.won and prev.won then
		return cur.t < prev.t
	end
	if not cur.won and not prev.won then
		local cz, pz = cur.zone or 0, prev.zone or 0
		return cz > pz or (cz == pz and cur.t > prev.t)
	end
	return false
end

export type Remotes = { load: RemoteFunction, save: RemoteEvent }

-- 서버: 길을 만든다(이미 있으면 그것)
function Net.serve(): Remotes
	assert(RunService:IsServer(), "Net.serve는 서버에서만")
	local folder = ReplicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
	end
	local load = folder:FindFirstChild("Load") :: RemoteFunction?
	if not load then
		local rf = Instance.new("RemoteFunction")
		rf.Name = "Load"
		rf.Parent = folder
		load = rf
	end
	local save = folder:FindFirstChild("Save") :: RemoteEvent?
	if not save then
		local re = Instance.new("RemoteEvent")
		re.Name = "Save"
		re.Parent = folder
		save = re
	end
	folder.Parent = ReplicatedStorage
	return { load = load :: RemoteFunction, save = save :: RemoteEvent }
end

-- 클라이언트: 길을 기다려 받는다. timeout초 안에 없으면 nil(서버 없이도 게임은 돈다)
function Net.connect(timeout: number): Remotes?
	local folder = ReplicatedStorage:WaitForChild(Net.FOLDER, timeout)
	if not folder then
		return nil
	end
	local load = folder:WaitForChild("Load", timeout)
	local save = folder:WaitForChild("Save", timeout)
	if not load or not save then
		return nil
	end
	return { load = load :: RemoteFunction, save = save :: RemoteEvent }
end

return Net
