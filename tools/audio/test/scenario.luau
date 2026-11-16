-- 작은 가짜 로블록스(소리에 필요한 만큼) + src/client/Sound.luau 검사.
-- run.mjs가 이 앞에 MEMBERS · USED_NAMES · HIT_SRCS · mod_SoundMap · mod_SoundIds · mod_Sound를 붙인다.

local NOW = 100 -- 가짜 시계(초)
local WRITES = 0 -- 속성을 쓴 횟수
local created: { [string]: number } = {}
local all = {} -- 만든 인스턴스 전부
local plays = {} -- Play 기록
local stops = 0
local warns = {}
local preloaded = 0

local RAW = setmetatable({}, { __mode = "k" })

local function typeOk(kind: string, v: any): boolean
	if kind == "float" or kind == "double" or kind == "int" or kind == "int64" then
		return type(v) == "number" and v == v
	elseif kind == "bool" then
		return type(v) == "boolean"
	elseif kind == "string" or kind == "ContentId" or kind == "Content" then
		return type(v) == "string"
	elseif kind == "NumberRange" then
		return type(v) == "table" and type(v.Min) == "number" and type(v.Max) == "number"
	elseif kind == "fn" then
		return false -- 메서드에는 쓸 수 없다
	end
	return v == nil or RAW[v] ~= nil -- 인스턴스
end

local function posOf(p, st): number
	if not st.playing then
		return st.tp
	end
	local x = st.startPos + (NOW - st.startClock) * p.PlaybackSpeed
	local reg = if p.PlaybackRegionsEnabled then p.PlaybackRegion else nil
	if p.Looped then
		local lr = p.LoopRegion or reg
		if lr and lr.Max > lr.Min and x >= lr.Max then
			x = lr.Min + (x - lr.Max) % (lr.Max - lr.Min)
		end
	elseif reg and x >= reg.Max then
		x = reg.Max
	end
	return x
end

local function newInst(class: string)
	local mem = MEMBERS[class]
	if not mem then
		error("모르는 클래스: " .. tostring(class), 3)
	end
	created[class] = (created[class] or 0) + 1
	local p: any = { Name = class, ClassName = class, Volume = if class == "Sound" then 0.5 else 1, PlaybackSpeed = 1, Looped = false, Enabled = true, LowGain = 0, MidGain = 0, HighGain = 0, PlaybackRegionsEnabled = false, SoundId = "" }
	local st: any = { playing = false, startClock = 0, startPos = 0, tp = 0, children = {}, tpWrites = 0 }
	local self = {}
	local methods = {}
	function methods.Play(_s)
		local reg = if p.PlaybackRegionsEnabled then p.PlaybackRegion else nil
		st.startPos = if reg and st.tp < reg.Min then reg.Min else st.tp
		st.startClock = NOW
		st.playing = true
		table.insert(plays, { sound = self, id = p.SoundId, region = reg, loop = p.LoopRegion, looped = p.Looped, vol = p.Volume, at = st.startPos, time = NOW, group = p.SoundGroup, speed = p.PlaybackSpeed })
	end
	function methods.Stop(_s)
		st.playing = false
		st.tp = 0
		stops += 1
	end
	function methods.FindFirstChild(_s, name)
		for _, c in st.children do
			if c.Name == name then
				return c
			end
		end
		return nil
	end
	function methods.Destroy(_s)
		self.Parent = nil
	end
	setmetatable(self, {
		__index = function(_, k)
			if mem[k] == nil then
				error(class .. "에 없는 이름: " .. tostring(k), 2)
			end
			if mem[k] == "fn" then
				return methods[k] or error(class .. ":" .. k .. "는 가짜에 없다", 2)
			end
			if k == "TimePosition" then
				return posOf(p, st)
			end
			return p[k]
		end,
		__newindex = function(_, k, v)
			if mem[k] == nil then
				error(class .. "에 없는 속성: " .. tostring(k), 2)
			end
			if not typeOk(mem[k], v) then
				error(class .. "." .. k .. "에 맞지 않는 값: " .. tostring(v), 2)
			end
			WRITES += 1
			if k == "Parent" then
				local old = p.Parent
				if old then
					local ch = RAW[old].st.children
					local i = table.find(ch, self)
					if i then
						table.remove(ch, i)
					end
				end
				if v then
					table.insert(RAW[v].st.children, self)
				end
			elseif k == "TimePosition" then
				st.tp = v
				st.tpWrites += 1
				if st.playing then
					st.startPos, st.startClock = v, NOW
				end
				return
			elseif k == "PlaybackSpeed" and st.playing then
				st.startPos, st.startClock = posOf(p, st), NOW
			end
			p[k] = v
		end,
	})
	RAW[self] = { p = p, st = st }
	table.insert(all, self)
	return self
end

local SoundService = newInst("SoundService")
created = {}
local fakeGame = {
	GetService = function(_self, name: string)
		if name == "SoundService" then
			return SoundService
		elseif name == "ContentProvider" then
			return {
				PreloadAsync = function(_s, list)
					preloaded += #list
				end,
			}
		elseif name == "ReplicatedStorage" then
			return {
				WaitForChild = function(_s, _n)
					return {
						WaitForChild = function(_s2, n)
							return { __module = n }
						end,
					}
				end,
			}
		end
		error("가짜에 없는 서비스: " .. name)
	end,
}
local fakeInstance = { new = newInst }
local fakeNumberRange = {
	new = function(a: number, b: number)
		assert(type(a) == "number" and type(b) == "number" and a <= b, "NumberRange.new: 잘못된 값")
		return { Min = a, Max = b }
	end,
}
local fakeOs = {
	clock = function()
		return NOW
	end,
}
local fakeTask = {
	spawn = function(f, ...)
		f(...)
	end,
}
local function fakeWarn(...)
	table.insert(warns, table.concat({ ... }, " "))
end

local MAP = mod_SoundMap(fakeGame, fakeInstance, fakeNumberRange, fakeOs, fakeTask, fakeWarn, nil)
local REAL_IDS = mod_SoundIds(fakeGame, fakeInstance, fakeNumberRange, fakeOs, fakeTask, fakeWarn, nil)

local function load(ids)
	local old = SoundService:FindFirstChild("SsbSound")
	if old then
		old:Destroy()
	end
	created, plays, warns, stops, preloaded, all = {}, {}, {}, 0, 0, {}
	local mods = { SoundMap = MAP, SoundIds = ids }
	return mod_Sound(fakeGame, fakeInstance, fakeNumberRange, fakeOs, fakeTask, fakeWarn, function(tok)
		return mods[tok.__module]
	end)
end
local function byName(name: string)
	for _, i in all do
		if i.Name == name then
			return i
		end
	end
	error("인스턴스가 없다: " .. name)
end
local function total(): number
	local n = 0
	for _, c in created do
		n += c
	end
	return n
end

local passed, failed = 0, 0
local function check(ok: any, msg: string)
	if ok then
		passed += 1
	else
		failed += 1
		print("  ✗ " .. msg)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local sheetKeys = {}
for k in MAP.sheets do
	table.insert(sheetKeys, k)
end
table.sort(sheetKeys)
local names = {}
for k in MAP.sfx do
	table.insert(names, k)
end
table.sort(names)
-- 구간 시작 시각 → "이름.갈래" (어느 갈래가 났는지 알아보는 데 쓴다)
local whichSet = {}
for name, def in MAP.sfx do
	for key, set in def.sets do
		for _, r in set do
			whichSet[r.sheet .. "@" .. r.t0] = name .. "." .. key
		end
	end
end
local function lastSet(): string
	local p = plays[#plays]
	return whichSet[(function()
		for _, k in sheetKeys do
			if p.id == "rbxassetid://" .. k then
				return k
			end
		end
		return "?"
	end)() .. "@" .. p.region.Min] or "?"
end
local function argFor(def, key: string): any
	if def.kind == "flag" then
		return key == "on"
	elseif def.kind == "key" then
		return key
	elseif def.kind == "tick" then
		return tonumber(string.sub(key, 2))
	elseif def.kind == "pick" then
		return if string.sub(key, 1, 1) == "b" then 3 else 1
	end
	return nil
end

-- ── 0. 표끼리 맞는지 ───────────────────────────────────────────────────────────
print("0. SoundIds의 키 = SoundMap.sheets의 키")
for _, k in sheetKeys do
	check(type(REAL_IDS[k]) == "string", "SoundIds에 " .. k .. "가 없다")
end
for k in REAL_IDS do
	check(MAP.sheets[k] ~= nil, "SoundIds의 " .. k .. "는 구운 파일이 아니다")
end
for name, def in MAP.sfx do
	for key, set in def.sets do
		for _, r in set do
			check(MAP.sheets[r.sheet] ~= nil and r.t0 >= 0 and r.t1 > r.t0 and r.t1 <= MAP.sheets[r.sheet].length, name .. "." .. key .. ": 구간이 파일 밖이다")
		end
	end
end
print("1. 원본이 부르는 이름이 모두 표에 있다 (" .. #USED_NAMES .. "개)")
for _, n in USED_NAMES do
	check(MAP.sfx[n] ~= nil, "표에 없는 효과음: " .. n)
end

-- ── 2. 번호가 비어 있을 때: 아무 소리도 내지 않고 오류도 없다 ────────────────────────
print("2. 에셋 번호가 비어 있을 때")
do
	local empty = {}
	for _, k in sheetKeys do
		empty[k] = ""
	end
	local S = load(empty)
	S.init()
	S.init()
	check(created.Sound == nil, "번호가 없는데 Sound를 만들었다: " .. tostring(created.Sound))
	S.vol(0.8, 0.8)
	for _, n in names do
		for key in MAP.sfx[n].sets do
			NOW += 1
			S.sfx(n, 0.2, argFor(MAP.sfx[n], key))
		end
	end
	for _, st in { { scene = "menu" }, { scene = "play", station = 0, boss = true, muffled = false, late = true, lowhp = true, crowd = 300 }, { scene = "play", station = 3, muffled = true }, { scene = "off" } } :: { any } do
		for _ = 1, 120 do
			NOW += 1 / 60
			S.music(st)
		end
	end
	check(#plays == 0, "번호가 없는데 소리를 냈다: " .. #plays)
	check(#warns == 0, "경고가 났다: " .. tostring(warns[1]))
	print(string.format("   인스턴스 %d개(Folder · SoundGroup 2 · EqualizerSoundEffect) · Play 0번 · 경고 0번", total()))
end

-- ── 가짜 번호 ────────────────────────────────────────────────────────────────
local ids = {}
for _, k in sheetKeys do
	ids[k] = "rbxassetid://" .. k
end

print("3. 가짜 번호로: 효과음마다 맞는 파일 · 구간 · 음량")
do
	local S = load(ids)
	S.init()
	local n0, s0 = total(), created.Sound
	S.init()
	check(total() == n0, "init을 두 번 부르니 인스턴스가 늘었다")
	check(preloaded > 0, "미리 받기를 부르지 않았다")
	local combos, variants = 0, 0
	for _, n in names do
		local def = MAP.sfx[n]
		for key, set in def.sets do
			if def.kind ~= "pick" then
				NOW += 5
				local before = #plays
				S.sfx(n, 0.3, argFor(def, key))
				combos += 1
				check(#plays == before + 1, n .. "." .. key .. ": Play가 한 번이 아니다")
				local p = plays[#plays]
				local hit = false
				for _, r in set do
					if p.id == ids[r.sheet] and p.region and p.region.Min == r.t0 and p.region.Max == r.t1 and near(p.vol, r.vol) and p.at == r.t0 then
						hit = true
					end
				end
				check(hit, n .. "." .. key .. ": 파일 · 구간 · 음량이 표와 다르다")
				check(p.group and p.group.Name == "Sfx" and not p.looped, n .. ": 효과음 묶음이 아니거나 되풀이로 틀었다")
				-- 갈래가 여럿이면 30번 안에 다 나오고, 같은 것이 잇달아 나오지 않는다
				if #set > 1 then
					local seen, prev, rep = {}, nil, false
					for _ = 1, 30 do
						NOW += 5
						S.sfx(n, 0, argFor(def, key))
						local q = plays[#plays].region.Min
						seen[q] = true
						rep = rep or q == prev
						prev = q
					end
					local c = 0
					for _ in seen do
						c += 1
					end
					variants += #set
					check(c == #set, n .. "." .. key .. ": 갈래 " .. #set .. "개 중 " .. c .. "개만 나왔다")
					check(not rep, n .. "." .. key .. ": 같은 갈래가 잇달아 나왔다")
				end
			end
		end
	end
	print(string.format("   Sound %d개(만든 것 전부 %d개) · 이름×갈래 %d가지 확인 · 무작위 갈래 %d개 모두 나옴", s0, n0, combos, variants))

	print("4. 원본의 타격 출처 " .. #HIT_SRCS .. "가지 → hit")
	local fallback = 0
	for _, src in HIT_SRCS do
		NOW += 5
		S.sfx("hit", 0, src)
		local want = if MAP.sfx.hit.sets[src] then "hit." .. src else "hit.card"
		if want == "hit.card" and src ~= "card" then
			fallback += 1
		end
		check(lastSet() == want, "hit " .. src .. " → " .. lastSet() .. " (바란 것 " .. want .. ")")
	end
	NOW += 5
	S.sfx("voice", 0, "nobody")
	check(lastSet() == "voice.bagman", "모르는 보스의 목소리가 bagman이 아니다")
	print("   표에 없는 출처 " .. fallback .. "가지는 card 소리로 났다(원본과 같다)")

	print("5. 모르는 이름은 한 번만 경고")
	for _ = 1, 3 do
		S.sfx("nope", 0, nil)
	end
	check(#warns == 1, "경고 횟수 " .. #warns)

	print("6. 최소 간격")
	NOW += 5
	local b = #plays
	for _ = 1, 50 do
		S.sfx("kill", 0, nil)
	end
	check(#plays == b + 1, "kill 50번 → Play " .. (#plays - b) .. "번")
	NOW += 0.039
	S.sfx("kill", 0, nil)
	check(#plays == b + 1, "0.039초 뒤의 kill이 났다(간격 0.04초)")
	NOW += 0.002
	S.sfx("kill", 0, nil)
	check(#plays == b + 2, "0.041초 뒤의 kill이 나지 않았다")
	NOW += 5
	b = #plays
	for _ = 1, 10 do
		S.sfx("hit", 0, "card")
		S.sfx("hit", 0, "umbrella")
		S.sfx("hit", 0, "bulldozer")
	end
	check(#plays == b + 3, "hit은 무기마다 따로 재야 한다: " .. (#plays - b))

	print("7. 원두 줍기: 이어 주우면 음이 오른다")
	NOW += 5
	local got = {}
	for _ = 1, 15 do
		NOW += 0.1
		S.sfx("pick", 0, 1)
		table.insert(got, lastSet())
	end
	local okSeq = true
	for i = 1, 15 do
		okSeq = okSeq and got[i] == "pick.a" .. math.min(i - 1, 12)
	end
	check(okSeq, "차례: " .. table.concat(got, " "))
	NOW += 0.5
	S.sfx("pick", 0, 5)
	check(lastSet() == "pick.b0", "0.5초 쉬고 큰 원두 → " .. lastSet())
	NOW += 0.1
	S.sfx("pick", 0, 3)
	check(lastSet() == "pick.b1", "값 3 → " .. lastSet())

	print("8. 남은 초")
	for n = 10, 1, -1 do
		NOW += 1
		S.sfx("tick", nil, n)
		check(lastSet() == "tick.n" .. n, "tick " .. n .. " → " .. lastSet())
	end

	print("9. 몰아치기 (가) 전투: 600프레임 동안 프레임마다 hit 30번(무기 6종) · kill 10번 · pick 10번 · crit 5번")
	NOW += 5
	do
		local srcs = { "card", "umbrella", "backpack", "anc", "battery", "shoulder" }
		local c1, p1, maxF, busyMax, stolen = total(), #plays, 0, 0, 0
		local ends = {}
		for f = 1, 600 do
			NOW += 1 / 60
			local pf = #plays
			for i = 1, 30 do
				S.sfx("hit", 0, srcs[(f + i) % 6 + 1])
			end
			for _ = 1, 10 do
				S.sfx("kill", 0, nil)
				S.sfx("pick", 0, 1)
			end
			for _ = 1, 5 do
				S.sfx("crit", 0, nil)
			end
			for j = pf + 1, #plays do
				local was = ends[plays[j].sound]
				if was and was > NOW then
					stolen += 1
				end
				ends[plays[j].sound] = NOW + (plays[j].region.Max - plays[j].region.Min)
			end
			local nb = 0
			for _, e in ends do
				if e > NOW then
					nb += 1
				end
			end
			busyMax = math.max(busyMax, nb)
			maxF = math.max(maxF, #plays - pf)
		end
		check(total() == c1, "전투 중 인스턴스가 늘었다")
		check(maxF <= 9, "한 프레임에 너무 많이 났다: " .. maxF)
		print(string.format("   부른 것 %d번 → Play %d번(초당 %.0f번) · 한 프레임 최대 %d번 · 동시에 울리는 목소리 최대 %d개(풀 %d개) · 울리던 것을 끊은 횟수 %d · 인스턴스 %d개 그대로", 600 * 55, #plays - p1, (#plays - p1) / 10, maxF, busyMax, S.VOICES, stolen, total()))
	end

	print("9. 몰아치기 (나) 억지: 600프레임 동안 프레임마다 서로 다른 이름 40가지")
	NOW += 5
	local c0, p0, maxFrame = total(), #plays, 0
	local busy = {} -- Sound → 끝나는 시각
	local steals = 0
	for f = 1, 600 do
		NOW += 1 / 60
		local pf = #plays
		for i = 1, 40 do
			local n = names[(f * 7 + i * 13) % #names + 1]
			local def = MAP.sfx[n]
			local key = next(def.sets)
			S.sfx(n, 0, argFor(def, key))
		end
		for j = pf + 1, #plays do
			local p = plays[j]
			if busy[p.sound] and busy[p.sound] > NOW then
				steals += 1
			end
			busy[p.sound] = NOW + (p.region.Max - p.region.Min)
		end
		maxFrame = math.max(maxFrame, #plays - pf)
	end
	local distinct = 0
	for _ in busy do
		distinct += 1
	end
	check(total() == c0, "몰아치는 동안 인스턴스가 늘었다: " .. c0 .. " → " .. total())
	check(distinct <= S.VOICES, "쓴 Sound가 풀보다 많다")
	print(string.format("   부른 것 %d번 → Play %d번 · 한 프레임 최대 %d번 · 쓴 Sound %d개 · 울리던 것을 빼앗은 횟수 %d · 인스턴스 %d개 그대로", 600 * 40, #plays - p0, maxFrame, distinct, steals, total()))

	S.vol(0.5, 0)
	b = #plays
	NOW += 5
	S.sfx("kill", 0, nil)
	check(#plays == b, "효과음 음량 0인데 소리를 냈다")
end

print("10. 음악")
do
	local S = load(ids)
	S.init()
	S.vol(0.8, 0.6)
	local music, sfxg = byName("Music"), byName("Sfx")
	check(near(music.Volume, 0.8 * S.MASTER) and near(sfxg.Volume, 0.6 * S.MASTER), "묶음 음량")
	local c0 = total()
	local M = MAP.music
	local function run(st, seconds: number)
		for _ = 1, math.floor(seconds * 60 + 0.5) do
			NOW += 1 / 60
			S.music(st)
		end
	end
	local function isSong(p, song): boolean
		return p.id == ids[song.sheet] and p.region.Min == song.t0 and p.region.Max == song.t1 and p.loop.Min == song.loop0 and p.loop.Max == song.t1 and p.looped and p.at == song.t0 and near(p.vol, song.vol) and p.group == music
	end
	local function isRegion(p, r): boolean
		return p.id == ids[r.sheet] and p.region.Min == r.t0 and p.region.Max == r.t1
	end

	-- 메뉴
	local st: any = { scene = "menu" }
	run(st, 1 / 60)
	check(#plays == 1 and isSong(plays[1], M.menu), "메뉴 노래가 맞게 시작하지 않았다")
	local menuSound = plays[1].sound
	local w = WRITES
	run(st, 3)
	check(WRITES == w and #plays == 1, "달라진 것이 없는데 속성을 썼다: " .. (WRITES - w) .. "번")
	run(st, 60)
	check(menuSound.TimePosition >= M.menu.loop0 and menuSound.TimePosition < M.menu.t1, "메뉴 노래가 되풀이 구간에 있지 않다")

	-- 게임 시작: 역 0
	st = { scene = "play", station = 0, boss = false, muffled = false, late = false, lowhp = false, crowd = 0 }
	run(st, 1 / 60)
	check(#plays == 3 and isSong(plays[2], M.songs[0]) and isRegion(plays[3], M.crash) and plays[3].group == music, "역 0 노래 + 심벌")
	local song0 = plays[2].sound
	check(song0 ~= menuSound, "앞 노래와 같은 Sound를 썼다")
	run(st, 0.5)
	check(menuSound.Volume == 0 and not RAW[menuSound].st.playing, "메뉴 노래가 내려가 멈추지 않았다")
	w = WRITES
	run(st, 5)
	check(WRITES == w, "달라진 것이 없는데 속성을 썼다(플레이): " .. (WRITES - w) .. "번")
	run(st, 70)
	local s0 = M.songs[0]
	check(song0.TimePosition >= s0.loop0 and song0.TimePosition < s0.t1, "노래가 되풀이 구간에 있지 않다")

	-- 보스 층
	st.boss = true
	local np = #plays
	run(st, 1 / 60)
	local stemPlay = plays[np + 1]
	check(#plays == np + 1 and isRegion(stemPlay, s0.boss) and stemPlay.looped and stemPlay.group == music, "보스 층이 맞게 시작하지 않았다")
	local stem = stemPlay.sound
	local function syncErr(song): number
		local a = (song0.TimePosition - song.t0) % song.phrase
		local b = stem.TimePosition - song.boss.t0
		local d = (a - b + song.phrase / 2) % song.phrase - song.phrase / 2
		return math.abs(d)
	end
	-- 표의 시각은 100만분의 1초로 반올림되어 있어 한 바퀴에 그만큼씩 벌어질 수 있다 → 0.1ms까지 봐준다
	check(syncErr(s0) < 1e-4, "보스 층이 노래의 스텝과 어긋났다: " .. syncErr(s0))
	run(st, 0.4)
	check(near(stem.Volume, s0.boss.vol), "보스 층 음량이 다 올라오지 않았다")
	local tw = RAW[stem].st.tpWrites
	run(st, 40)
	check(syncErr(s0) < 1e-4 and RAW[stem].st.tpWrites == tw, "40초 뒤 어긋났거나 다시 맞추느라 자리를 옮겼다: " .. syncErr(s0))
	-- 지각
	st.late = true
	run(st, 1 / 60)
	check(near(song0.PlaybackSpeed, 1.08) and near(stem.PlaybackSpeed, 1.08), "지각인데 빠르기가 1.08이 아니다")
	run(st, 20)
	check(syncErr(s0) < 1e-4, "빠르기를 바꾼 뒤 어긋났다: " .. syncErr(s0))
	-- 일부러 어긋나게 해 보면(가짜 시계로 0.3초) 2초 안에 다시 맞춘다
	stem.TimePosition = stem.TimePosition + 0.3
	run(st, 2.1)
	check(syncErr(s0) < 1e-4, "어긋난 보스 층을 다시 맞추지 않았다: " .. syncErr(s0))
	st.late = false
	st.boss = false
	run(st, 0.5)
	check(near(song0.PlaybackSpeed, 1) and stem.Volume == 0 and not RAW[stem].st.playing, "보스 층이 내려가 멈추지 않았다")

	-- 먹먹함
	local eqi = byName("Muffle")
	check(eqi.Enabled == false, "처음부터 이퀄라이저가 켜져 있다")
	st.muffled = true
	run(st, 1.5)
	check(eqi.Enabled and near(eqi.LowGain, M.muffle.low, 0.01) and near(eqi.MidGain, M.muffle.mid, 0.01) and near(eqi.HighGain, M.muffle.high, 0.01), "먹먹함 값: " .. eqi.MidGain .. " " .. eqi.HighGain)
	w = WRITES
	run(st, 2)
	check(WRITES == w, "먹먹한 채로 속성을 계속 썼다")
	st.muffled = false
	run(st, 1.5)
	check(not eqi.Enabled and eqi.MidGain == 0 and eqi.HighGain == 0, "먹먹함이 풀리지 않았다")

	-- 웅성거림
	local amb = byName("crowd")
	st.crowd = 200
	run(st, 4)
	check(RAW[amb].st.playing and near(amb.Volume, 0.5 * M.amb.vol, 0.02) and amb.Looped and amb.PlaybackRegion.Min == M.amb.t0 and amb.LoopRegion.Max == M.amb.t1 and amb.SoundGroup == sfxg, "웅성거림 200마리: " .. amb.Volume)
	st.crowd = 1000
	run(st, 4)
	check(near(amb.Volume, M.amb.vol, 0.02), "웅성거림 1000마리: " .. amb.Volume)
	st.muffled = true
	run(st, 5)
	check(amb.Volume == 0 and not RAW[amb].st.playing, "멈춤 화면에서 웅성거림이 멈추지 않았다")
	st.muffled = false
	st.crowd = 0
	run(st, 1)

	-- 심장 박동
	st.lowhp = true
	np = #plays
	run(st, 5)
	local beats = #plays - np
	check((beats == 6 or beats == 7) and isRegion(plays[#plays], M.heart) and plays[#plays].group == sfxg, "5초 동안 심장 박동 " .. beats .. "번")
	st.lowhp = false

	-- 같은 파일 안의 다른 노래(역 1) · 다른 파일(역 4)
	np = #plays
	st.station = 1
	run(st, 1 / 60)
	check(#plays == np + 2 and isSong(plays[np + 1], M.songs[1]) and isRegion(plays[np + 2], M.crash) and plays[np + 1].sound ~= song0, "역 1로 넘어가기")
	run(st, 0.5)
	check(song0.Volume == 0 and not RAW[song0].st.playing, "역 0 노래가 멈추지 않았다")
	np = #plays
	st.station = 4
	st.boss = true
	run(st, 1 / 60)
	check(#plays == np + 3 and isSong(plays[np + 1], M.songs[4]) and isRegion(plays[np + 3], M.songs[4].boss) and plays[np + 3].at == M.songs[4].boss.t0, "역 4 + 보스 층(처음부터)")
	st.boss = false
	run(st, 1)

	-- 음악 끄기 → 켜기: 처음부터, 심벌 없이
	local cur = plays[np + 1].sound
	S.vol(0, 0.6)
	run(st, 0.5)
	check(cur.Volume == 0 and not RAW[cur].st.playing and music.Volume == 0, "음악 음량 0에서 멈추지 않았다")
	np = #plays
	S.vol(0.8, 0.6)
	run(st, 1 / 60)
	check(#plays == np + 1 and isSong(plays[np + 1], M.songs[4]), "음악을 다시 켜면 처음부터(심벌 없이)")
	cur = plays[np + 1].sound
	st.scene = "off"
	run(st, 0.5)
	check(cur.Volume == 0 and not RAW[cur].st.playing, "끝난 뒤 노래가 멈추지 않았다")
	check(total() == c0, "음악을 트는 동안 인스턴스가 늘었다")
	print(string.format("   Play %d번 · Stop %d번 · 인스턴스 %d개 그대로", #plays, stops, total()))
end

print(string.format("통과 %d · 실패 %d", passed, failed))
if failed > 0 then
	error("검사 실패")
end
