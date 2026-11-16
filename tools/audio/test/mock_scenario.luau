-- src/client/Sound.luau를 공용 검사 도구(tools/mock) 위에서 돌린다 — 속성 이름 · 값의 종류를 로블록스 API 덤프로 걸러 준다.
--   node tools/mock/run.mjs --project tools/audio/test/mock.project.json --script tools/audio/test/mock_scenario.luau
-- (셈이 맞는지 — 구간 · 간격 · 갈래 — 는 tools/audio/test/run.mjs가 더 꼼꼼히 본다. tools/mock은 PlaybackRegion에 따른 재생 위치를 흉내 내지 않는다.)
local h = harness
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local sharedFolder = RS:WaitForChild("shared")
local module = h.player().PlayerScripts.client.Sound

local MAP = h.require(sharedFolder.SoundMap, "client")
local IDS = h.require(sharedFolder.SoundIds, "client")

local names = {}
for n in MAP.sfx do
	table.insert(names, n)
end
table.sort(names)
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
local function countSounds(): number
	return #h.findAllByClass("Sound", SoundService)
end
local STATES: { any } = {
	{ scene = "menu" },
	{ scene = "play", station = 0, boss = false, muffled = false, late = false, lowhp = false, crowd = 0 },
	{ scene = "play", station = 0, boss = true, muffled = false, late = true, lowhp = true, crowd = 300 },
	{ scene = "play", station = 1, boss = true, muffled = true, late = false, lowhp = true, crowd = 300 },
	{ scene = "play", station = 4, boss = false, muffled = false, late = false, lowhp = false, crowd = 50 },
	{ scene = "off" },
}
local function drive(Sound)
	local combos = 0
	for _, n in names do
		for key in MAP.sfx[n].sets do
			h.advance(0.5)
			h.asClient(Sound.sfx, n, 0.3, argFor(MAP.sfx[n], key))
			combos += 1
		end
	end
	for _, st in STATES do
		for _ = 1, 90 do
			h.asClient(Sound.music, st)
			h.step(1)
		end
	end
	return combos
end

-- ── 1. SoundIds.luau에 적힌 그대로 (지금은 비어 있다 → 조용해야 한다) ─────────────
local filled = 0
for _, id in IDS do
	if id ~= "" then
		filled += 1
	end
end
print("== 1. SoundIds 그대로 (번호가 적힌 파일 " .. filled .. "개) ==")
local Sound1 = h.require(module, "client")
h.asClient(Sound1.init)
h.asClient(Sound1.init)
h.asClient(Sound1.vol, 0.8, 0.8)
local c1 = countSounds()
local combos = drive(Sound1)
h.asClient(Sound1.sfx, "nope", 0, nil)
h.asClient(Sound1.sfx, "nope", 0, nil)
h.eq(countSounds(), c1, "쓰는 동안 Sound가 늘지 않는다")
if filled == 0 then
	h.eq(c1, 0, "번호가 없으면 Sound를 만들지 않는다")
	h.eq(#h.sounds(), 0, "번호가 없으면 소리를 내지 않는다")
end
h.eq(#h.errors(), 0, "오류 없음")
h.eq(#h.warnings(), 1, "모르는 이름 경고는 한 번")
print(string.format("   이름×갈래 %d가지 + 음악 상태 %d가지: Sound %d개 · Play %d번 · 오류 %d · 경고 %d", combos, #STATES, c1, #h.sounds(), #h.errors(), #h.warnings()))

-- ── 2. 가짜 번호 (모듈을 새로 베껴 처음 상태로) ──────────────────────────────────
print("== 2. 가짜 번호 ==")
local saved = table.clone(IDS)
for k in MAP.sheets do
	IDS[k] = "rbxassetid://" .. (1000 + #k)
end
IDS.sfx1, IDS.music1, IDS.music2, IDS.music3 = "rbxassetid://101", "rbxassetid://201", "rbxassetid://202", "rbxassetid://203"
local copy = module:Clone()
copy.Name = "Sound2"
copy.Parent = module.Parent
local Sound2 = h.require(copy, "client")
h.asClient(Sound2.init)
h.asClient(Sound2.vol, 0.8, 0.8)
local c2 = countSounds()
h.expect(c2 > 0, "가짜 번호로는 Sound를 만든다")
h.asClient(Sound2.init)
h.eq(countSounds(), c2, "init을 두 번 불러도 그대로")
local folder = SoundService:FindFirstChild("SsbSound")
h.expect(folder ~= nil, "SoundService.SsbSound")
h.near(folder.Music.Volume, 0.8 * Sound2.MASTER, 1e-6, "음악 묶음 음량")

-- 효과음: 부를 때마다 Play 한 번, 맞는 파일 · 구간
local before = #h.sounds()
local bad = 0
for _, n in names do
	local def = MAP.sfx[n]
	for key, set in def.sets do
		if def.kind ~= "pick" then
			h.advance(0.5)
			local b = #h.sounds()
			h.asClient(Sound2.sfx, n, 0.3, argFor(def, key))
			local log = h.sounds()
			local ok = #log == b + 1
			if ok then
				local e = log[#log]
				local s = folder:FindFirstChild(e.name)
				ok = false
				for _, r in set do
					if e.id == IDS[r.sheet] and s and s.PlaybackRegionsEnabled and math.abs(s.PlaybackRegion.Min - r.t0) < 1e-4 and math.abs(s.PlaybackRegion.Max - r.t1) < 1e-4 and math.abs(e.volume - r.vol) < 1e-6 then
						ok = true
					end
				end
			end
			if not ok then
				bad += 1
				h.fail(n .. "." .. key .. ": Play가 한 번이 아니거나 파일 · 구간이 표와 다르다")
			end
		end
	end
end
h.eq(bad, 0, "효과음마다 맞는 파일 · 구간")
print(string.format("   Sound %d개 · 효과음 Play %d번", c2, #h.sounds() - before))

-- 몰아치기: 인스턴스가 늘지 않는다
for f = 1, 300 do
	for i = 1, 30 do
		h.asClient(Sound2.sfx, names[(f * 7 + i * 13) % #names + 1], 0, nil)
	end
	h.step(1)
end
h.eq(countSounds(), c2, "몰아쳐도 Sound가 늘지 않는다")

-- 음악: 상태를 바꿔 가며 돌린다
before = #h.sounds()
for _, st in STATES do
	for _ = 1, 90 do
		h.asClient(Sound2.music, st)
		h.step(1)
	end
	if st.muffled then
		h.near(folder.Music.Muffle.HighGain, MAP.music.muffle.high, 0.5, "먹먹할 때 고음")
		h.expect(folder.Music.Muffle.Enabled, "먹먹할 때 이퀄라이저가 켜진다")
	end
end
h.expect(#h.sounds() - before >= 6, "음악 쪽 Play(메뉴 · 역 노래 3 · 심벌 · 보스 층 · 심장 박동 …)")
h.expect(not folder.Music.Muffle.Enabled, "끝나면 이퀄라이저가 꺼진다")
h.eq(countSounds(), c2, "음악을 트는 동안 Sound가 늘지 않는다")
h.eq(#h.errors(), 0, "오류 없음")
h.eq(#h.warnings(), 1, "새 경고 없음")
print(string.format("   음악 쪽 Play %d번 · 오류 %d", #h.sounds() - before, #h.errors()))

for k, v in saved do
	IDS[k] = v
end
