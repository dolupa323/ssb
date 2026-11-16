--!strict
-- 소리. 원본 js/audio.js의 AudioSys와 같은 모양(init · vol · sfx · music).
-- 원본은 소리를 그 자리에서 합성하지만 로블록스는 올린 파일만 틀 수 있다 →
-- 원본 소리를 구운 파일(assets/audio/*.wav) 안의 구간을 튼다. 구간 표 = shared/SoundMap, 에셋 번호 = shared/SoundIds.
-- 번호가 비어 있는 파일의 소리는 조용히 넘어간다. 자세한 것: tools/audio/AUDIO_NOTES.md
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local SoundMap = require(sharedFolder:WaitForChild("SoundMap")) :: any
local SoundIds = require(sharedFolder:WaitForChild("SoundIds")) :: { [string]: string }

type Region = { sheet: string, t0: number, t1: number, vol: number }
type SfxDef = { gap: number, kind: string, default: string?, sets: { [string]: { Region } } }
type Song = { sheet: string, t0: number, loop0: number, t1: number, vol: number, bpm: number, phrase: number, boss: Region?, name: string? }
type Voice = { sound: Sound, untilT: number }
-- 음악 쪽 Sound 하나와 그 음량의 흐름 (gain이 goal로 rate/초씩 움직인다 · 0에 닿으면 멈춘다)
type Fader = { sound: Sound, gain: number, goal: number, rate: number, base: number, active: boolean }
export type MusicState = {
	scene: string, -- "menu" | "play" | "off"
	station: number?, -- 노래 번호 0~4 (Sim의 S.song)
	boss: boolean?,
	muffled: boolean?, -- 멈춤 · 레벨 업 화면
	late: boolean?,
	lowhp: boolean?,
	crowd: number?, -- 화면의 적 수
}

local SFX = SoundMap.sfx :: { [string]: SfxDef }
local MUSIC = SoundMap.music
local MENU = MUSIC.menu :: Song
local SONGS = MUSIC.songs :: { [number]: Song }
local CRASH = MUSIC.crash :: Region
local HEART = MUSIC.heart :: Region
local AMB = MUSIC.amb :: Region
local HEART_EVERY = MUSIC.heartEvery :: number
local AMB_FULL = MUSIC.ambFull :: number
local AMB_TAU = MUSIC.ambTau :: number
local LATE_SPEED = MUSIC.lateSpeed :: number
local MUFFLE = MUSIC.muffle :: { low: number, mid: number, high: number, tau: number }

-- 전체 음량. 원본은 음악과 효과음을 한 리미터에 넣어 합이 넘치지 않게 하지만 로블록스는 그냥 더한다 →
-- 음악(최대 약 0.72)과 효과음(최대 약 0.72)이 겹쳐도 넘치지 않게 조금 낮춘다
local MASTER = 0.7
local VOICES = 24 -- 효과음을 동시에 낼 수 있는 수 (파일마다). 모자라면 가장 먼저 끝날 것을 빼앗는다
local FADE_OUT = 0.35 -- 노래가 바뀔 때 앞 노래를 내리는 시간(초)
local STEM_FADE = 0.25 -- 보스 층을 올리고 내리는 시간(초)
local STEM_RESYNC = true -- 보스 층이 노래와 어긋나면(0.12초 넘게) 다시 맞춘다
local STEM_SLACK = 0.12

local Sound = {}
Sound.MASTER = MASTER
Sound.VOICES = VOICES

local inited = false
local mv, sv = 1, 1
local musicGroup: SoundGroup? = nil
local sfxGroup: SoundGroup? = nil
local eq: EqualizerSoundEffect? = nil

-- 효과음
local pools: { [string]: { Voice } } = {} -- 파일 이름 → 목소리들 (번호가 빈 파일은 없다)
local last: { [string]: number } = {} -- 이름마다 마지막으로 낸 시각 (원본의 최소 간격)
local lastPick: { [any]: number } = {} -- 갈래마다 마지막으로 고른 것 (같은 것을 잇달아 내지 않게)
local warned: { [string]: boolean } = {}
local streak, lastPickT = 0, -9 -- 원두를 이어 주운 횟수

-- 음악
local tracks: { [string]: { Fader } } = {} -- 파일 이름 → Sound 두 개 (번갈아 쓴다)
local trackTurn: { [string]: number } = {}
local fading: { Fader } = {}
local curSong: Song? = nil
local curFader: Fader? = nil
local curSpeed = 1
local stem: Fader? = nil
local stemOn = false
local stemSong: Song? = nil
local nextSync = 0
local crashSound: Sound? = nil
local ambSound: Sound? = nil
local ambVol, ambWritten, ambPlaying = 0, 0, false
local muffleOn = false
local eqLow, eqMid, eqHigh, eqBusy = 0, 0, 0, false
local beatT = 0
local lastT = 0

local function idOf(sheet: string): string?
	local id = SoundIds[sheet]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function newSound(parent: Instance, name: string, id: string, group: SoundGroup?): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.SoundGroup = group
	s.PlaybackRegionsEnabled = true
	s.Volume = 0
	s.Parent = parent
	return s
end

-- 구간을 틀 준비: 구간 → 시작 위치 순으로 적는다
local function setRegion(s: Sound, t0: number, t1: number, loop0: number?)
	s.PlaybackRegion = NumberRange.new(t0, t1)
	if loop0 then
		s.LoopRegion = NumberRange.new(loop0, t1)
		s.Looped = true
	end
	s.TimePosition = t0
end

function Sound.init()
	if inited then
		return
	end
	inited = true

	local old = SoundService:FindFirstChild("SsbSound")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SsbSound"

	local mg = Instance.new("SoundGroup")
	mg.Name = "Music"
	mg.Volume = mv * MASTER
	mg.Parent = folder
	local sg = Instance.new("SoundGroup")
	sg.Name = "Sfx"
	sg.Volume = sv * MASTER
	sg.Parent = folder
	local e = Instance.new("EqualizerSoundEffect")
	e.Name = "Muffle"
	e.LowGain, e.MidGain, e.HighGain = 0, 0, 0
	e.Enabled = false
	e.Parent = mg
	musicGroup, sfxGroup, eq = mg, sg, e

	local preload: { Instance } = {}

	-- 효과음 목소리: 효과음이 담긴 파일마다 VOICES개
	local sheets: { [string]: boolean } = {}
	for _, def in SFX do
		for _, set in def.sets do
			for _, r in set do
				sheets[r.sheet] = true
			end
		end
	end
	sheets[HEART.sheet] = true
	for sheet in sheets do
		local id = idOf(sheet)
		if id then
			local pool: { Voice } = {}
			for i = 1, VOICES do
				pool[i] = { sound = newSound(folder, sheet .. "_" .. i, id, sg), untilT = 0 }
			end
			pools[sheet] = pool
			table.insert(preload, pool[1].sound)
		end
	end

	-- 음악: 노래가 담긴 파일마다 Sound 두 개 (앞 노래를 내리면서 새 노래를 올린다)
	local function addTrack(sheet: string)
		local id = idOf(sheet)
		if tracks[sheet] or not id then
			return
		end
		local pair: { Fader } = {}
		for i = 1, 2 do
			pair[i] = { sound = newSound(folder, sheet .. "_track" .. i, id, mg), gain = 0, goal = 0, rate = 1, base = 1, active = false }
		end
		tracks[sheet] = pair
		trackTurn[sheet] = 1
		table.insert(preload, pair[1].sound)
	end
	addTrack(MENU.sheet)
	local bossSheet: string? = nil
	for _, song in SONGS do
		addTrack(song.sheet)
		if song.boss then
			bossSheet = song.boss.sheet
		end
	end
	local bossId = if bossSheet then idOf(bossSheet) else nil
	if bossSheet and bossId then
		stem = { sound = newSound(folder, "bossLayer", bossId, mg), gain = 0, goal = 0, rate = 1, base = 1, active = false }
	end
	local crashId = idOf(CRASH.sheet)
	if crashId then
		crashSound = newSound(folder, "crash", crashId, mg)
	end
	local ambId = idOf(AMB.sheet)
	if ambId then
		local a = newSound(folder, "crowd", ambId, sg)
		setRegion(a, AMB.t0, AMB.t1, AMB.t0)
		ambSound = a
	end

	folder.Parent = SoundService

	-- 미리 받아 둔다 (첫 소리가 늦지 않게). 실패해도 게임은 계속된다
	if #preload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(preload)
			end)
		end)
	end
end

-- 음량 0~1. 음악이 0이면 노래를 멈추고, 다시 켜면 처음부터 튼다(원본과 같다)
function Sound.vol(music: number, sfx: number)
	mv = math.clamp(music, 0, 1)
	sv = math.clamp(sfx, 0, 1)
	if musicGroup then
		musicGroup.Volume = mv * MASTER
	end
	if sfxGroup then
		sfxGroup.Volume = sv * MASTER
	end
end

-- 구간 하나를 효과음 목소리로 낸다. 빈 목소리가 없으면 가장 먼저 끝날 것을 빼앗는다
local function playRegion(r: Region, mul: number)
	local pool = pools[r.sheet]
	if not pool then
		return -- 에셋 번호가 비어 있다
	end
	local now = os.clock()
	local v = pool[1]
	for i = 1, #pool do
		local c = pool[i]
		if c.untilT <= now then
			v = c
			break
		end
		if c.untilT < v.untilT then
			v = c
		end
	end
	local s = v.sound
	setRegion(s, r.t0, r.t1)
	s.Volume = r.vol * mul
	s:Play()
	v.untilT = now + (r.t1 - r.t0)
end

-- 효과음. pan은 쓰지 않는다(로블록스의 2D 소리에는 좌우 치우침이 없다). arg는 SoundMap의 kind대로 갈래를 고른다
function Sound.sfx(name: string, _pan: number?, arg: any)
	if not inited or sv <= 0 then
		return
	end
	local def = SFX[name]
	if not def then
		if not warned[name] then
			warned[name] = true
			warn("[Sound] 모르는 효과음 이름: " .. tostring(name))
		end
		return
	end
	-- 원본의 최소 간격 (hit은 무기마다 따로)
	local now = os.clock()
	local key = if name == "hit" then "hit" .. tostring(arg) else name
	local was = last[key]
	if was and now - was < def.gap then
		return
	end
	last[key] = now

	local kind = def.kind
	local setKey = "one"
	if kind == "flag" then
		setKey = if arg ~= nil and arg ~= false and arg ~= 0 then "on" else "off"
	elseif kind == "key" then
		setKey = if type(arg) == "string" and def.sets[arg] then arg else (def.default or "")
	elseif kind == "pick" then
		streak = if now - lastPickT < 0.4 then math.min(streak + 1, 12) else 0
		lastPickT = now
		setKey = (if type(arg) == "number" and arg >= 3 then "b" else "a") .. streak
	elseif kind == "tick" then
		local n = if type(arg) == "number" then math.clamp(math.floor(arg), 0, 10) else 0
		setKey = "n" .. n
	end
	local set = def.sets[setKey]
	if not set then
		return
	end
	local n = #set
	local idx = 1
	if n > 1 then
		idx = math.random(n)
		if idx == lastPick[set] then
			idx = idx % n + 1
		end
		lastPick[set] = idx
	end
	playRegion(set[idx], 1)
end

local function fadeTo(f: Fader, goal: number, seconds: number)
	f.goal = goal
	f.rate = 1 / math.max(seconds, 0.001)
	if not f.active then
		f.active = true
		table.insert(fading, f)
	end
end

local function stepFades(dt: number)
	for i = #fading, 1, -1 do
		local f = fading[i]
		local g = f.gain
		if g < f.goal then
			g = math.min(f.goal, g + f.rate * dt)
		else
			g = math.max(f.goal, g - f.rate * dt)
		end
		f.gain = g
		f.sound.Volume = f.base * g
		if g == f.goal then
			if g <= 0 then
				f.sound:Stop()
			end
			f.active = false
			fading[i] = fading[#fading]
			fading[#fading] = nil
		end
	end
end

-- 노래의 지금 위치가 64스텝(4마디) 안에서 어디인가(초)
local function phraseOffset(song: Song, f: Fader): number
	return math.max(0, f.sound.TimePosition - song.t0) % song.phrase
end

local function startStem(song: Song, offset: number)
	local f, b = stem, song.boss
	if not f or not b then
		return
	end
	local s = f.sound
	setRegion(s, b.t0, b.t1, b.t0)
	s.TimePosition = b.t0 + offset
	s.PlaybackSpeed = curSpeed
	f.base = b.vol
	s.Volume = f.base * f.gain
	s:Play()
	fadeTo(f, 1, STEM_FADE)
	nextSync = os.clock() + 2
end

local function switchSong(want: Song?)
	local first = curSong == nil
	local prev = curFader
	if prev then
		fadeTo(prev, 0, FADE_OUT)
	end
	curSong, curFader = want, nil
	if stemOn then
		stemOn, stemSong = false, nil
		if stem then
			fadeTo(stem, 0, STEM_FADE)
		end
	end
	if not want then
		return
	end
	local pair = tracks[want.sheet]
	if pair then
		local turn = trackTurn[want.sheet]
		local f = pair[turn]
		if f == prev then
			turn = 3 - turn
			f = pair[turn]
		end
		trackTurn[want.sheet] = 3 - turn
		local s = f.sound
		setRegion(s, want.t0, want.t1, want.loop0)
		s.PlaybackSpeed = curSpeed
		f.base, f.gain, f.goal = want.vol, 1, 1
		s.Volume = want.vol
		s:Play()
		curFader = f
	end
	-- 원본: 다른 노래에서 넘어올 때(처음이 아니고 메뉴 노래가 아닐 때) 심벌을 한 번 친다
	local c = crashSound
	if c and not first and want ~= MENU then
		setRegion(c, CRASH.t0, CRASH.t1)
		c.Volume = CRASH.vol
		c:Play()
	end
end

local function stepEq(dt: number)
	local e = eq
	if not e then
		eqBusy = false
		return
	end
	local k = 1 - math.exp(-dt / MUFFLE.tau)
	local gl = if muffleOn then MUFFLE.low else 0
	local gm = if muffleOn then MUFFLE.mid else 0
	local gh = if muffleOn then MUFFLE.high else 0
	eqLow += (gl - eqLow) * k
	eqMid += (gm - eqMid) * k
	eqHigh += (gh - eqHigh) * k
	if math.abs(gl - eqLow) < 0.2 and math.abs(gm - eqMid) < 0.2 and math.abs(gh - eqHigh) < 0.2 then
		eqLow, eqMid, eqHigh, eqBusy = gl, gm, gh, false
	end
	e.LowGain, e.MidGain, e.HighGain = eqLow, eqMid, eqHigh
	e.Enabled = muffleOn or eqBusy
end

local function stepAmb(goal: number, dt: number)
	ambVol += (goal - ambVol) * (1 - math.exp(-dt / AMB_TAU))
	local snapped = math.abs(goal - ambVol) < 0.004
	if snapped then
		ambVol = goal
	end
	local a = ambSound
	if not a then
		return
	end
	if ambVol > 0 and not ambPlaying then
		ambPlaying = true
		a.TimePosition = AMB.t0
		a:Play()
	end
	if snapped or math.abs(ambVol - ambWritten) > 0.01 then
		ambWritten = ambVol
		a.Volume = AMB.vol * ambVol
	end
	if ambVol <= 0 and ambPlaying then
		ambPlaying = false
		a:Stop()
	end
end

-- 프레임마다 부른다. 달라진 것만 손댄다
function Sound.music(st: MusicState)
	if not inited then
		return
	end
	local now = os.clock()
	local dt = math.clamp(now - lastT, 0, 0.25)
	lastT = now
	local play = st.scene == "play"
	local muffled = st.muffled == true

	-- 노래: 메뉴 · 역마다 한 곡 · 그 밖에는 없음
	local want: Song? = nil
	if mv > 0 then
		if st.scene == "menu" then
			want = MENU
		elseif play then
			want = SONGS[st.station or 0]
		end
	end
	if want ~= curSong then
		switchSong(want)
	end
	local song, cf = curSong, curFader

	-- 지각: 원본은 박자가 8% 빨라진다
	local speed = if play and st.late then LATE_SPEED else 1
	if speed ~= curSpeed then
		curSpeed = speed
		if cf then
			cf.sound.PlaybackSpeed = speed
		end
		if stem then
			stem.sound.PlaybackSpeed = speed
		end
	end

	-- 보스 층: 노래의 스텝에 맞춰 겹친다
	local bossWant = st.boss == true and song ~= nil and song.boss ~= nil
	if bossWant ~= stemOn or (bossWant and stemSong ~= song) then
		stemOn = bossWant
		stemSong = if bossWant then song else nil
		if bossWant and song then
			startStem(song, if cf then phraseOffset(song, cf) else 0)
		elseif stem then
			fadeTo(stem, 0, STEM_FADE)
		end
	elseif stemOn and STEM_RESYNC and now >= nextSync and song and cf and stem and song.boss then
		nextSync = now + 2
		local wantAt = phraseOffset(song, cf)
		local haveAt = stem.sound.TimePosition - song.boss.t0
		local d = (wantAt - haveAt + song.phrase * 0.5) % song.phrase - song.phrase * 0.5
		if math.abs(d) > STEM_SLACK then
			stem.sound.TimePosition = song.boss.t0 + wantAt
		end
	end

	-- 멈춤 화면: 음악만 먹먹하게
	if muffled ~= muffleOn then
		muffleOn = muffled
		eqBusy = true
	end
	if eqBusy then
		stepEq(dt)
	end

	-- 웅성거림: 적이 많을수록 크게 (400마리에서 최대)
	local ambGoal = if play and not muffled then math.min(1, (st.crowd or 0) / AMB_FULL) else 0
	if ambGoal ~= ambVol then
		stepAmb(ambGoal, dt)
	end

	-- 체력이 낮으면 심장 박동
	if play and st.lowhp and not muffled and sv > 0 and now > beatT then
		beatT = now + HEART_EVERY
		playRegion(HEART, 1)
	end

	if #fading > 0 then
		stepFades(dt)
	end
end

return Sound
