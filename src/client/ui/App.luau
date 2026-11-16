--!strict
-- 게임의 진행(원본 js/main.js): 규칙(Sim)에 붙는 host · 설정 · 안내 · 시작/끝 · 일시정지 · 고르기 · 입력 · 매 장면의 고리.
--  원본의 함수 이름을 그대로 두었다(startDemo · startGame · toMenu · setPaused · menuSettings · showLevelUp · pick · reroll · showBest · showEnd · tryDash · frame).
local RunService = game:GetService("RunService")
local Sim = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Sim")) :: any
local Client = script.Parent.Parent
local Stage = require(Client.Stage) :: any
local Input = require(Client.Input)
local Gfx = require(Client.Gfx) :: any
local Sound = require(Client.Sound) :: any
local T = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Store = require(script.Parent.Store)
local Menu = require(script.Parent.Menu)
local Hud = require(script.Parent.Hud)
local Banner = require(script.Parent.Banner)
local LevelUp = require(script.Parent.LevelUp)
local Pause = require(script.Parent.Pause)
local EndScreen = require(script.Parent.EndScreen)

local App = {}
App.sim = nil :: any
App.mode = "menu" -- "menu" | "play"
App.paused = false
App.PICK_DELAY = 0.35 -- 고르는 창이 뜬 뒤 이만큼은 눌러도 받지 않는다(잘못 누름 막기 — 원본 350ms)
App.DEMO_LEN = 75 -- 메뉴 뒤의 시연은 이만큼 돌고 다시 시작한다
App.NOTI_EVERY = 4.2

local bannerT = 0
local autoPausedAt = -10 -- 창이 뒤로 가거나 Roblox 메뉴가 열려 스스로 멈춘 때
local luOpenAt = 0
local setFromMenu = false
local hintT, hintGap = 0, 0
local notiT = 0
local started = false

-- ---------- host (규칙이 부르는 것) ----------
local showLevelUp, showEnd

local host = {}
function host.sfx(n: string, x: number?, arg: any)
	if App.mode ~= "play" then
		return
	end
	local pan = 0
	if x ~= nil and App.sim then
		pan = math.clamp((x - App.sim.S.p.x) / 480, -0.8, 0.8)
	end
	Sound.sfx(n, pan, arg)
end
function host.banner(a: string, b: string?, kind: string?)
	if App.mode ~= "play" then
		return
	end
	Banner.show(a, b, kind)
	bannerT = if kind == "boss" then 3.2 else 2.6
end
function host.shake(a: number)
	if App.mode == "play" then
		Gfx.shake(a)
	end
end
function host.levelUp(ch: { any }, pm: string)
	showLevelUp(ch, pm)
end
function host.finish(won: boolean)
	if App.mode == "play" then
		showEnd(won)
	end
end
App.host = host

-- ---------- 설정 ----------
local function applySet(save: boolean)
	local SET = Store.set
	Sound.vol(SET.music / 100, SET.sfx / 100)
	Gfx.opts({ fx = SET.fx, shake = SET.shake, bloom = SET.bloom })
	Pause.apply(SET :: any)
	if Hud.lefty ~= (SET.hand == 1) then
		Hud.lefty = SET.hand == 1
		Hud.build() -- 원본 #app.lefty: 폰 배치에서 대시 단추가 왼쪽으로
	end
	if save then
		Store.saveSettings()
	end
end
App.applySet = applySet

-- ---------- 처음 하는 사람을 위한 안내: 한 줄씩, 그 일이 일어나는 때에, 한 번만 ----------
local HINTS: { { any } } = {
	{ "move", function(S: any): boolean
		return S.t > 1.2
	end, "WASD나 방향키, 또는 화면을 끌어서 움직입니다. 교통카드는 알아서 날아갑니다" },
	{ "xp", function(S: any): boolean
		return S.t > 7 and #S.beans > 2
	end, "떨어진 조각을 주우면 경험치가 찹니다. 다 차면 무기나 장비를 고릅니다" },
	{ "dash", function(S: any): boolean
		return S.t > 14 and S.p.dashCd <= 0 and #S.enemies > 14
	end, "둘러싸이면 Space 또는 대시 버튼. 터치라면 다른 손가락으로 화면을 톡 쳐도 됩니다" },
	{ "lane", function(S: any): boolean
		return S.train ~= nil and not S.train.on
	end, "빨간 경고가 뜬 길에서 물러나세요. 지나가는 차는 인파도 쓸어 갑니다" },
	{ "boss", function(S: any): boolean
		return S.gate ~= nil and not S.gate.dead
	end, "이곳의 진상입니다. 밀어내야 다음 장소로 넘어가고, 오래 끌면 폭주합니다" },
	{ "gates", function(S: any): boolean
		return S.zk == "gates" and S.zt > 1.5
	end, "개찰구는 사이 틈으로만 지나갈 수 있습니다. 인파도 틈으로 몰립니다" },
	{ "evo", function(S: any): boolean
		for _, lv in S.weapons do
			if lv >= 4 and lv <= Sim.WMAX then
				return true
			end
		end
		return false
	end, "무기를 6레벨까지 올리고 짝 장비를 갖추면 진화합니다. 짝은 카드 아래에 적혀 있습니다" },
	{ "train", function(S: any): boolean
		return S.zk == "train" and S.zt > 1.5
	end, "열차 안에서는 도착할 때까지 버티면 됩니다. 좁은 통로라 앞뒤만 보면 됩니다" },
	{ "doors", function(S: any): boolean
		return S.zk == "train" and S.doorT > 0
	end, "문이 열렸습니다. 문 앞에 서 있으면 밀려납니다. 닫힐 때까지 통로 가운데서 버티세요" },
	{ "esc", function(S: any): boolean
		return S.zk == "esc" and S.zt > 1.5
	end, "에스컬레이터는 서 있기만 해도 떠밀립니다. 가운데 계단은 멈춰 있습니다" },
}
App.HINTS = HINTS

local function tutorial(dt: number)
	local S = App.sim.S
	if S.diff ~= 0 and hintT <= 0 then
		return
	end
	if hintT > 0 then
		hintT -= dt
		if hintT <= 0 then
			Hud.hint(nil)
			hintGap = 1.5
		end
		return
	end
	if hintGap > 0 then
		hintGap -= dt
		return
	end
	for _, h in HINTS do
		if not Store.seen[h[1]] and h[2](S) then
			Store.markSeen(h[1])
			Hud.hint(h[3])
			hintT = 5.5
			Sound.sfx("hover")
			break
		end
	end
end

-- ---------- 최고 기록 줄 ----------
local function showBest()
	local diff = Store.diff
	local D = Sim.DIFFS[diff + 1]
	local b = Store.loadBest(diff)
	local text: string
	if b then
		local what = if b.won
			then Sim.clockText(b.t) .. (if b.t > Sim.GAME_LEN then " 지각 출근" else " 출근")
			else Sim.ZONES[(b.zone or 0) + 1].name .. "까지 (" .. Sim.clockText(b.t) .. ")"
		text = D.name .. " 최고 기록  " .. what .. " · 레벨 " .. b.level .. " · " .. b.kills .. "명"
	else
		text = D.name .. " 난이도 기록이 아직 없습니다"
	end
	Menu.refresh(diff, D.blurb, text)
end
App.showBest = showBest

-- ---------- 시작 · 끝 ----------
local function startDemo()
	Gfx.reset()
	App.sim = Sim.create(host, {
		demo = true,
		diff = 1,
		build = { weapons = { card = 3, backpack = 2, battery = 2, coffee = 1 }, passives = {}, wOrder = { "card", "backpack", "battery", "coffee" } },
	})
	App.sim.S.t = 18
	App.sim.S.nextRow = 24
	App.mode = "menu"
end
App.startDemo = startDemo

local function startGame()
	Sound.init()
	Gfx.reset()
	Sound.sfx("start")
	App.sim = Sim.create(host, { diff = Store.diff })
	App.mode = "play"
	App.paused = false
	Hud.reset()
	Menu.show(false)
	EndScreen.hide()
	Pause.close()
	LevelUp.hide()
	Hud.show(true)
	Banner.hide()
	Hud.hint(nil)
	hintT, hintGap = 0, 0
	setFromMenu = false
	Input.clear()
end
App.startGame = startGame

local function toMenu()
	EndScreen.hide()
	Pause.close()
	LevelUp.hide()
	Hud.show(false)
	Menu.show(true)
	Banner.hide()
	setFromMenu = false
	showBest()
	startDemo()
end
App.toMenu = toMenu

local function setPaused(v: boolean, title: string?)
	local sim = App.sim
	if App.mode ~= "play" or sim.S.state == "over" or sim.S.state == "won" then
		return
	end
	if App.paused ~= v then
		Sound.sfx(if v then "pause" else "resume")
	end
	App.paused = v
	if sim.S.state == "levelup" then
		Pause.close()
		return
	end
	setFromMenu = false
	if v then
		Pause.open(title or "일시정지", "열차가 잠시 정차 중입니다", "계속 출근하기", true)
	else
		Pause.close()
	end
end
App.setPaused = setPaused

local function menuSettings(v: boolean)
	setFromMenu = v
	if v then
		Pause.open("설정", "소리와 화면을 기기에 맞게 조절하세요", "닫기", false)
	else
		Pause.close()
	end
end
App.menuSettings = menuSettings

-- ---------- 고르는 창 ----------
function showLevelUp(ch: { any }, pm: string)
	luOpenAt = os.clock()
	LevelUp.show(ch, pm, App.sim.S.rerolls)
	Pause.close()
	Input.clear()
end

local function pick(i: number)
	local sim = App.sim
	if App.mode ~= "play" or sim.S.state ~= "levelup" then
		return
	end
	if os.clock() - luOpenAt < App.PICK_DELAY then
		return
	end
	local c = sim.S.choices and sim.S.choices[i]
	Sound.sfx(if c and c.kind == "evo" then "evo" else "select")
	LevelUp.hide()
	sim.choose(i)
	local now: string = App.sim.S.state -- (고른 뒤의 상태: 밀린 것이 없으면 "run")
	if now == "run" and App.paused then
		Pause.open("일시정지", "열차가 잠시 정차 중입니다", "계속 출근하기", true)
	end
end
App.pick = pick

local function reroll()
	local sim = App.sim
	if App.mode == "play" and sim.S.state == "levelup" and sim.reroll() then
		Sound.sfx("reroll")
	end
end
App.reroll = reroll

-- ---------- 결과 ----------
function showEnd(won: boolean)
	local S = App.sim.S
	Sound.sfx(if won then "win" else "lose")
	if won then
		Gfx.celebrate()
	end
	EndScreen.show(EndScreen.info(S, won))
	Store.submitRun(S.diff, { t = S.t, kills = S.kills, level = S.p.level, won = won, zone = S.zone })
	LevelUp.hide()
	Pause.close()
end

-- ---------- 입력 ----------
local function tryDash()
	local sim = App.sim
	if App.mode == "play" and not App.paused and sim.S.state == "run" then
		sim.S.input = Input.read()
		sim.dash()
	end
end
App.tryDash = tryDash

local PICK_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}

-- 원본 keydown. 돌려주는 것: 이 글쇠를 여기서 썼는가(이동 글쇠로 넘기지 않는다)
local function onKey(code: Enum.KeyCode): boolean
	local sim = App.sim
	if not sim then
		return true
	end
	local mode = App.mode
	if mode == "play" and sim.S.state == "levelup" then
		local n = PICK_KEYS[code]
		if n then
			pick(n)
			return true
		end
		if code == Enum.KeyCode.R then
			reroll()
			return true
		end
	end
	if code == Enum.KeyCode.Space or code == Enum.KeyCode.LeftShift or code == Enum.KeyCode.RightShift then
		if mode == "play" then
			tryDash()
			return true
		end
		-- 원본: 메뉴에서 아무 단추에도 초점이 없을 때의 Space = 시작. Roblox에는 초점이 없어 「설정 창이 닫혀 있을 때」로 본다
		if mode == "menu" and code == Enum.KeyCode.Space and not setFromMenu then
			startGame()
			return true
		end
	end
	if code == Enum.KeyCode.P or code == Enum.KeyCode.Escape then
		if mode == "play" and sim.S.state == "run" then
			-- Esc는 Roblox 메뉴도 연다: 메뉴가 열려 방금 멈춘 것을 같은 Esc가 다시 풀지 않게 한다
			if code == Enum.KeyCode.P or os.clock() - autoPausedAt > 0.5 then
				setPaused(not App.paused)
			end
		end
		return true
	end
	if (code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter) and mode == "menu" and not setFromMenu then
		startGame()
		return true
	end
	return false
end
App.onKey = onKey

-- 창이 뒤로 갔거나 Roblox 메뉴가 열렸다 → 멈춘다(원본 visibilitychange)
local function autoPause()
	local sim = App.sim
	if sim and App.mode == "play" and sim.S.state == "run" and not App.paused then
		autoPausedAt = os.clock()
		setPaused(true)
	end
end

-- ---------- 매 장면 (원본 frame) ----------
local function frame(dtReal: number)
	local dt = math.min(0.1, dtReal)
	T.stepAnims(dtReal)
	local sim = App.sim
	if not sim then
		return
	end
	local mode = App.mode
	local running = mode == "menu" or (mode == "play" and not App.paused and sim.S.state == "run")
	local modal = mode == "play" and not running
	Banner.setModal(modal)
	Hud.setModal(modal)
	if running and not Gfx.frozen() then
		if bannerT > 0 then
			bannerT -= dt
			if bannerT <= 0 then
				Banner.hide()
			end
		end
		local n = math.max(1, math.ceil(dt / (1 / 60)))
		local h = dt / n
		local v = Gfx.view()
		if mode == "play" then
			tutorial(dt)
		end
		local i = 0
		while i < n and sim.S.state == "run" do
			if mode == "menu" then
				local b = sim.bot()
				sim.S.input = b
				if b.dash then
					sim.dash()
				end
			else
				sim.S.input = Input.read()
			end
			sim.update(h, v)
			i += 1
		end
		if mode == "menu" and sim.S.t > App.DEMO_LEN then
			startDemo()
		end
	end
	-- (규칙이 도는 동안 판이 바뀌었을 수 있다: 끝 · 시연 다시 시작)
	sim = App.sim
	mode = App.mode
	local S = sim.S
	local ended = S.state == "over" or S.state == "won"
	Gfx.render(S, {
		mode = mode,
		dt = dt,
		running = running,
		fx = mode == "play" and ended,
		offX = if mode == "menu" and Stage.wide then -0.2 else 0,
		offY = 0,
	})
	Input.draw(mode == "play")
	Hud.frame(dtReal)
	Banner.frame(dtReal)
	if mode == "play" then
		Hud.update(S)
		Sound.music({
			scene = if ended then "off" else "play",
			station = S.song,
			boss = S.boss ~= nil,
			muffled = not running,
			late = S.rage > 0,
			lowhp = S.p.hp / S.p.maxhp < 0.3,
			crowd = #S.enemies,
		})
	else
		Sound.music({ scene = "menu" })
	end
	-- 휴대폰 알림은 4.2초마다 바뀐다(원본 setInterval: 시계는 늘 돌고, 메뉴일 때만 바꾼다)
	notiT += dtReal
	if notiT >= App.NOTI_EVERY then
		notiT -= App.NOTI_EVERY
		if mode == "menu" then
			Menu.nextNoti()
		end
	end
end
App.frame = frame

-- ---------- 시작 (원본 boot + 단추에 거는 것들) ----------
function App.boot()
	if started then
		return
	end
	started = true
	local click = function()
		Sound.sfx("click")
	end
	W.click = click
	Hud.onClick = click

	Menu.onStart = startGame
	Menu.onDiff = function(i: number)
		Store.setDiff(i)
		Sound.sfx("click")
		showBest()
	end
	Menu.onSettings = function()
		menuSettings(true)
	end
	EndScreen.onRetry = startGame
	EndScreen.onHome = toMenu
	Pause.onQuit = toMenu
	Pause.onResume = function()
		if setFromMenu then
			menuSettings(false)
		else
			setPaused(false)
		end
	end
	Pause.onSet = function(key: string, value: number)
		(Store.set :: any)[key] = value
		applySet(true)
		if key ~= "music" and key ~= "sfx" then
			Sound.sfx("click")
			if key == "shake" and value == 1 then
				Gfx.shake(8)
			end
		end
	end
	Pause.onSfxRelease = function()
		Sound.sfx("select")
	end
	Pause.onTutorial = function()
		Store.resetSeen()
		Sound.sfx("click")
	end
	Hud.onPause = function()
		if App.sim.S.state == "run" then
			setPaused(not App.paused)
		end
	end
	Hud.onSettings = function()
		if App.sim.S.state == "run" then
			setPaused(true, "설정")
		end
	end
	Hud.onDash = tryDash
	LevelUp.onPick = pick
	LevelUp.onReroll = reroll
	LevelUp.onHover = function()
		Sound.sfx("hover")
	end

	-- 화면들을 만든다
	Hud.lefty = Store.set.hand == 1
	Menu.build()
	Hud.build()
	Banner.topShift = Hud.topShift
	Banner.build()
	local function rebuildAll()
		Menu.build()
		Hud.build()
		Banner.topShift = Hud.topShift
		Banner.build()
		LevelUp.build()
		Pause.build()
		EndScreen.build()
		if App.sim and App.mode == "play" then
			Hud.update(App.sim.S)
		end
	end
	Stage.onResize(rebuildAll)
	T.onRelayout = rebuildAll -- 그려진 글의 진짜 폭이 잰 것과 달랐을 때(Theme.luau 「본문 글의 폭 재기」)

	Input.init(Stage, {
		key = onKey,
		canJoy = function()
			return App.mode == "play"
		end,
		dash = tryDash,
		pause = function()
			if App.sim and App.mode == "play" and App.sim.S.state == "run" and os.clock() - autoPausedAt > 0.5 then
				setPaused(not App.paused)
			end
		end,
		blur = autoPause,
		menu = autoPause,
		-- 원본 wake: 처음 누를 때 소리를 깨운다
		wake = function()
			Sound.init()
			Sound.vol(Store.set.music / 100, Store.set.sfx / 100)
		end,
	})

	applySet(false)
	showBest()
	Menu.nextNoti()
	startDemo()
	RunService.RenderStepped:Connect(frame)
end

return App
