-- UI 흐름 전체: 불러오기 → 메뉴(시연) → 난이도 → 설정 → 시작 → 글쇠로 움직이기 · 대시 → 안내 → 일시정지 → 고르기(누르기 · 글쇠 · 다시 뽑기)
--  → 보스 줄의 세 모습 → 쓰러짐(결과) → 다시 → 도착(결과) → 처음 화면.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --script tools/ui/scenarios/flow.luau --shot-dir tools/ui/shots [--viewport WxH]
local h = harness
local VW, VH = h.viewport()
local tag = VW .. "x" .. VH
local Players = game:GetService("Players")

local function section(s)
	print("== " .. s .. " ==")
end
-- 굴리는 틀 안의 것을 화면 안으로 굴려 놓는다
local function reveal(inst)
	local p = inst.Parent
	while p and not p:IsA("ScrollingFrame") do
		p = p.Parent
	end
	if p then
		local _, y, _, hh = h.rect(inst)
		local _, sy, _, sh = h.rect(p)
		if y < sy or y + hh > sy + sh then
			local maxY = math.max(0, p.CanvasSize.Y.Offset - sh)
			p.CanvasPosition = Vector2.new(0, math.clamp(p.CanvasPosition.Y + (y + hh / 2) - (sy + sh / 2), 0, maxY))
			h.step(1)
		end
	end
end
local function click(inst)
	reveal(inst)
	h.clickOn(inst)
end
local function shot(name)
	h.shot(name .. "-" .. tag .. ".png")
end
-- 조건이 될 때까지 게임을 돌린다. 그동안 고르는 창이 뜨면 첫 카드를 고른다(시험이 멈추지 않게)
local getApp
local function runUntil(cond, timeout, what)
	return h.waitFor(function()
		local v = cond()
		if v then
			return v
		end
		local app = getApp()
		if app.mode == "play" and app.sim.S.state == "levelup" then
			h.advance(0.4)
			h.keyTap(Enum.KeyCode.One)
		end
		return false
	end, timeout, what)
end

-- ---------- 불러오기 ----------
section("불러오기")
h.waitFor(function()
	return h.find("PlayerGui.Ssb.Top.Loading") ~= nil
end, 2, "불러오는 화면이 뜬다(글자 판을 만든 뒤)")
local gui = h.get("PlayerGui.Ssb")
h.eq(gui.IgnoreGuiInset, true, "ScreenGui.IgnoreGuiInset")
h.eq(gui.ResetOnSpawn, false, "ScreenGui.ResetOnSpawn")
h.eq(gui.ZIndexBehavior, Enum.ZIndexBehavior.Sibling, "ScreenGui.ZIndexBehavior")
h.expect(h.find("PlayerGui.Ssb.Top.Loading") ~= nil, "불러오는 화면이 떠 있다")
h.eq(h.get("PlayerGui.Ssb.Top.Loading.Text").Text, "불러오는 중…", "불러오는 화면의 글")
shot("loading")
h.waitFor(function()
	return h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 20, "불러오기가 끝난다")
h.eq(Players.CharacterAutoLoads, false, "서버: CharacterAutoLoads = false")

local client = h.player().PlayerScripts.client
-- mock은 글자를 TextSize x 0.85 크기로 그린다(진짜 Roblox와 다르다). 본문 글씨가 원본과 같은 크기로 찍히게 mock 안에서만 배율을 1.2로 둔다
--  (Roblox에서 쓰는 값은 ui/Theme.luau의 BODY_FS — 이 시험과 상관없다). 화면을 다시 만들게 크기를 한 번 흔든다.
local Theme = h.require(client.ui.Theme, "client")
Theme.FS = 1.2
h.resize(VW + 2, VH)
h.resize(VW, VH)
h.step(2)
local App = h.require(client.ui.App, "client")
getApp = function()
	return App
end
local Store = h.require(client.ui.Store, "client")
local Menu = h.require(client.ui.Menu, "client")
local Hud = h.require(client.ui.Hud, "client")
local Pause = h.require(client.ui.Pause, "client")
local LevelUp = h.require(client.ui.LevelUp, "client")
local EndScreen = h.require(client.ui.EndScreen, "client")
local Banner = h.require(client.ui.Banner, "client")
local Stage = h.require(client.Stage, "client")
local Input = h.require(client.Input, "client")
local Gfx = h.require(client.Gfx, "client")
local Sound = h.require(client.Sound, "client")
local Sim = h.require(game.ReplicatedStorage.shared.Sim, "client")
h.expect(Gfx.isStub and Sound.isStub, "시험용 Gfx · Sound 대역으로 돈다")
h.eq(Store.loaded, true, "서버에서 자료를 읽었다")

-- CoreGui: 2D 게임이 쓰지 않는 것을 껐다
do
	local off = {}
	for _, c in h.coreCalls() do
		if c.name == "SetCoreGuiEnabled" or c.method == "SetCoreGuiEnabled" then
			off[tostring(c.kind or c.args and c.args[1])] = c.enabled
		end
	end
	local sg = game:GetService("StarterGui")
	local ok = true
	h.asClient(function()
		for _, kind in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
			if sg:GetCoreGuiEnabled(kind) then
				ok = false
			end
		end
		h.eq(sg:GetCoreGuiEnabled(Enum.CoreGuiType.Chat), false, "채팅도 껐다(혼자 하는 게임)")
	end)
	h.eq(ok, true, "참가자 목록 · 가방 · 체력 · 이모트를 껐다")
	-- 제목 글꼴은 구운 글자(Do Hyeon)로 그려진다
	local Bitmap = h.require(client.ui.Bitmap, "client")
	h.eq(#Bitmap.failed, 0, "글자 판을 모두 만들었다")
	h.eq(game:GetService("GuiService").TouchControlsEnabled, false, "기본 터치 조종을 껐다")
end

-- ---------- 메뉴 ----------
section("메뉴 · 시연")
h.eq(App.mode, "menu", "mode = menu")
h.eq(Menu.isShown(), true, "메뉴가 보인다")
h.eq(Hud.isShown(), false, "HUD는 숨어 있다")
h.eq(Stage.scale, math.max(1, math.min(VW / 1920, VH / 1080)), "화면 틀의 배율")
h.eq(Stage.wide, VW / Stage.scale >= 980, "넓은 화면인가")
local t0 = App.sim.S.t
local r0 = Gfx.calls.render
h.step(60)
h.near(App.sim.S.t - t0, 1, 0.02, "시연이 1초에 1초씩 흐른다")
h.eq(Gfx.calls.render - r0, 60, "매 장면 Gfx.render")
h.eq(Gfx.last.mode, "menu", "render의 mode")
h.eq(Gfx.last.offX, if Stage.wide then -0.2 else 0, "넓은 화면에서는 시연을 오른쪽으로 민다(offX)")
h.eq(Gfx.last.running, true, "render의 running")
h.eq(Sound.state.scene, "menu", "메뉴 음악")
h.eq(#Sound.log, 0, "메뉴의 시연은 효과음을 내지 않는다")
h.eq(Menu.E.title.Text, "출근길 서바이벌", "제목")
h.expect(h.findByText("오늘의 출근 경로", true) ~= nil, "경로 머리")
h.eq(Menu.E.sign.Intro.Text:gsub("\n", " "), "역 앞에서 회사 자리에 앉기까지, 한 시간짜리 출근길입니다. 장소마다 버티고 선 진상을 밀어내야 다음으로 넘어가고, 9시를 넘기면 지각입니다.", "설명 글")
h.eq(Menu.E.blurb.Text, "도착은 할 만하지만 정시 출근은 빠듯합니다", "보통의 설명")
h.eq(Menu.E.best.Text:gsub("\n", " "), "보통 난이도 기록이 아직 없습니다", "기록 없음")
h.eq(Menu.E.diff[1]:GetAttribute("Pressed"), true, "보통이 눌려 있다")
-- 휴대폰 알림이 4.2초마다 바뀐다
local n0 = Menu.notiIndex()
h.eq(Menu.E.notiFrom.Text, Menu.NOTI[n0][2], "알림 보낸 사람")
h.advance(4.3)
h.eq(Menu.notiIndex(), n0 % #Menu.NOTI + 1, "4.2초 뒤 다음 알림")
h.eq(Menu.E.notiTxt.Text, Menu.NOTI[Menu.notiIndex()][3], "알림 내용")
h.step(30)
shot("menu")
-- 시연은 75초를 넘기면 다시 시작한다
do
	local S = App.sim.S
	S.t = 74.9
	local resets = Gfx.calls.reset
	h.step(12)
	h.expect(App.sim.S ~= S and App.sim.S.t < 19, "시연이 다시 시작됐다(S.t = 18부터)")
	h.eq(Gfx.calls.reset, resets + 1, "Gfx.reset")
	h.eq(App.sim.S.weapons.card, 3, "시연의 무기 차림")
end

section("난이도")
local names = { "여유", "보통", "혼잡", "지옥철" }
for i = 0, 3 do
	click(Menu.E.diff[i])
	h.eq(Store.diff, i, names[i + 1] .. ": Store.diff")
	h.eq(Menu.E.diff[i]:GetAttribute("Pressed"), true, names[i + 1] .. ": 눌린 모양")
	h.eq(Menu.E.blurb.Text, Sim.DIFFS[i + 1].blurb, names[i + 1] .. ": 설명")
	h.eq(Menu.E.best.Text:gsub("\n", " "), names[i + 1] .. " 난이도 기록이 아직 없습니다", names[i + 1] .. ": 기록 줄")
end
h.eq(Sound.count("click"), 4, "난이도 단추마다 click 소리")

section("조작법")
click(Menu.E.btnHow)
h.eq(Menu.howOpen(), true, "조작법이 열렸다")
h.eq(Menu.E.how.Tip1.Text:gsub("\n", " "), "공격은 자동입니다. 움직여서 피하고, 떨어진 것을 주워 레벨을 올리세요.", "조작법의 글")
h.eq(Menu.E.how.Dt4.Text, "일시정지", "조작법: 글쇠 표")
reveal(Menu.E.how)
shot("menu-how")
click(Menu.E.btnHow)
h.eq(Menu.howOpen(), false, "다시 누르면 닫힌다")

section("메뉴의 설정")
click(Menu.E.btnSet)
h.eq(Pause.isShown(), true, "설정 창")
h.eq(Pause.E.title.Text, "설정", "제목")
h.eq(Pause.E.sub.Text, "소리와 화면을 기기에 맞게 조절하세요", "작은 글")
h.eq(Pause.E.resume.Body.Face.T.Text, "닫기", "닫기 단추")
h.eq(Pause.E.quit, nil, "「처음 화면으로」는 없다")
shot("menu-settings")
-- Space · Enter는 설정이 열려 있으면 시작하지 않는다
h.keyTap(Enum.KeyCode.Space)
h.eq(App.mode, "menu", "설정 창이 열려 있을 때 Space는 시작하지 않는다")
-- 이펙트 · 흔들림 · 빛 번짐 · 대시 버튼
local function setBtn(key, i)
	return h.get("PlayerGui.Ssb.Ui.Pause.Scroll.Panel.Sets.Set_" .. key .. i)
end
click(setBtn("fx", 1))
h.eq(Store.set.fx, 0, "이펙트 적게")
h.eq(Gfx.calls.opts.fx, 0, "Gfx.opts fx")
click(setBtn("bloom", 2))
h.eq(Store.set.bloom, 0, "빛 번짐 끄기")
h.eq(Gfx.calls.opts.bloom, 0, "Gfx.opts bloom")
click(setBtn("shake", 2))
h.eq(Store.set.shake, 0, "흔들림 끄기")
local shakes = #Gfx.calls.shake
click(setBtn("shake", 1))
h.eq(Store.set.shake, 1, "흔들림 켜기")
h.eq(Gfx.calls.shake[#Gfx.calls.shake], 8, "켜면 한 번 흔든다(8)")
h.eq(#Gfx.calls.shake, shakes + 1, "한 번만")
click(setBtn("hand", 2))
h.eq(Store.set.hand, 1, "대시 버튼 왼쪽")
h.eq(setBtn("hand", 2).BackgroundColor3, Color3.fromRGB(27, 33, 36), "눌린 단추는 먹색")
-- 음량 막대: 끌어서 0으로, 다시 50쯤으로
local music = h.get("PlayerGui.Ssb.Ui.Pause.Scroll.Panel.Sets.Set_music")
reveal(music)
local mx, my, mw, mh = h.rect(music)
h.mouseDown(mx + mw * 0.8, my + mh / 2)
h.mouseMove(mx - 30, my + mh / 2)
h.mouseUp(mx - 30, my + mh / 2)
h.eq(Store.set.music, 0, "음악 막대를 왼쪽 끝으로")
h.eq(Sound.volume.music, 0, "Sound.vol(music)")
local sfx = h.get("PlayerGui.Ssb.Ui.Pause.Scroll.Panel.Sets.Set_sfx")
local sx, sy, sw, sh = h.rect(sfx)
local selects = Sound.count("select")
h.click(sx + 8 + (sw - 16) * 0.5, sy + sh / 2)
h.eq(Store.set.sfx, 50, "효과음 막대를 가운데로")
h.eq(Sound.volume.sfx, 0.5, "Sound.vol(sfx)")
h.eq(Sound.count("select"), selects + 1, "효과음 막대에서 손을 떼면 select 소리")
-- 안내 다시 보기
Store.seen.move = 1
click(Pause.E.tut)
h.eq(next(Store.seen), nil, "본 안내를 지웠다")
h.eq(Pause.E.tut.T.Text, "다음 판부터 다시 나옵니다", "단추의 글이 바뀐다")
click(Pause.E.resume)
h.eq(Pause.isShown(), false, "닫기")
-- 서버에 저장됐는가(모았다가 쓴다)
h.advance(8)
local saved = h.datastore.get("SsbPlayer_v1", "u" .. h.player().UserId)
h.expect(saved ~= nil, "DataStore에 썼다")
h.eq(saved.set, { music = 0, sfx = 50, fx = 0, shake = 1, hand = 1, bloom = 0 }, "저장된 설정")
h.eq(saved.diff, 3, "저장된 난이도")

-- ---------- 시작 ----------
section("시작(여유)")
click(Menu.E.diff[0])
Store.set.hand = 0
App.applySet(true)
Sound.log = {}
h.keyTap(Enum.KeyCode.Return)
h.eq(App.mode, "play", "Enter로 시작")
h.eq(Sound.inits > 0, true, "Sound.init")
h.eq(Sound.log[1].name, "start", "시작 소리")
h.eq(Menu.isShown(), false, "메뉴가 닫혔다")
h.eq(Hud.isShown(), true, "HUD가 보인다")
h.step(2)
local S = App.sim.S
local E = Hud.elements()
h.eq(S.diff, 0, "여유로 시작")
h.eq(E.hpTxt.Text, "멘탈 170 / 170", "멘탈")
h.eq(E.lv.Text, "1", "레벨")
h.eq(E.clock.Text, "08:00", "시계")
h.eq(E.stn.Text, "역삼역 앞", "지금 여기의 이름")
if E.stnLabel then
	h.eq(E.stnLabel.Text, "지금 여기", "전광판의 작은 글")
	h.eq(E.kills.Text, "0", "처치 수")
	h.eq(#E.mini:GetChildren(), 13, "경로 줄: 점 7 + 줄 6")
end
h.eq(E.bossbar.Visible, false, "보스 줄은 숨어 있다")
h.eq(Sound.state.scene, "play", "게임 음악")
h.eq(Sound.state.station, S.song, "음악: 역 번호")
h.eq(Gfx.last.mode, "play", "render의 mode")
h.eq(Gfx.last.offX, 0, "게임 중에는 밀지 않는다")
-- 칸: 교통카드 + 운동화
do
	local icons = 0
	for _, d in E.build:GetDescendants() do
		if d.Name == "icon" then
			icons += 1
		end
	end
	h.eq(icons, 2, "무기 칸에 교통카드, 장비 칸에 운동화")
	local slots = 0
	for _, d in E.build:GetChildren() do
		if d.Name == "slot" then
			slots += 1
		end
	end
	h.eq(slots, Sim.MAX_W + Sim.MAX_P, "칸 10개")
end

section("글쇠로 움직이기 · 대시")
local function move(key, frames)
	local x, y = S.p.x, S.p.y
	h.keyDown(key)
	h.step(frames)
	h.keyUp(key)
	return S.p.x - x, S.p.y - y
end
local dx, dy = move(Enum.KeyCode.D, 20)
h.expect(dx > 20 and math.abs(dy) < 1, "D = 오른쪽 (" .. dx .. ")")
dx = move(Enum.KeyCode.A, 20)
h.expect(dx < -20, "A = 왼쪽")
dx, dy = move(Enum.KeyCode.W, 20)
h.expect(dy < -20, "W = 위")
dx, dy = move(Enum.KeyCode.S, 20)
h.expect(dy > 20, "S = 아래")
dx = move(Enum.KeyCode.Right, 10)
h.expect(dx > 8, "→")
dx = move(Enum.KeyCode.Left, 10)
h.expect(dx < -8, "←")
dx, dy = move(Enum.KeyCode.Up, 10)
h.expect(dy < -8, "↑")
dx, dy = move(Enum.KeyCode.Down, 10)
h.expect(dy > 8, "↓")
h.step(5)
local px = S.p.x
h.step(10)
h.near(S.p.x, px, 0.5, "떼면 멈춘다")
-- 대시
local dashes = S.dashes
h.keyDown(Enum.KeyCode.D)
h.step(2)
h.keyTap(Enum.KeyCode.Space)
h.eq(S.dashes, dashes + 1, "Space = 대시")
h.expect(S.p.dashCd > 0, "대시 대기 시간이 돈다")
h.step(3)
local lit = 0
for _, s in E.segs do
	if s.BackgroundTransparency < 0.5 then
		lit += 1
	end
end
h.expect(lit < 10, "대시 단추 둘레가 비었다 (" .. lit .. "/60)")
h.near(Theme.alpha(E.dashTxt), 0.6, 1e-6, "대시 글이 흐리다(준비 안 됨)")
h.keyUp(Enum.KeyCode.D)
h.keyTap(Enum.KeyCode.LeftShift)
h.eq(S.dashes, dashes + 1, "대기 중에는 Shift를 눌러도 대시가 안 된다")
h.advance(3)
h.near(Theme.alpha(E.dashTxt), 1, 1e-6, "다 차면 글이 또렷해진다")
h.keyTap(Enum.KeyCode.RightShift)
h.eq(S.dashes, dashes + 2, "Shift = 대시")
-- 대시 단추를 누름
h.advance(3)
h.mouseDown(h.center(E.dash))
h.eq(S.dashes, dashes + 3, "대시 단추(누르는 순간)")
h.mouseUp()
h.eq(Input.joy.active, false, "대시 단추를 눌러도 조이스틱은 생기지 않는다")

section("안내(여유 전용)")
h.eq(Store.seen.move, 1, "「move」 안내를 봤다")
-- 마우스로 세계를 끌어도 조이스틱(원본의 pointer 이벤트는 마우스도 받는다)
do
	local cx, cy = VW * 0.5, VH * 0.6
	h.mouseDown(cx, cy)
	h.eq(Input.joy.active, true, "세계를 누르면 조이스틱")
	h.mouseMove(cx + 60, cy)
	h.step(2)
	local i = Input.read()
	h.near(i.x, 1, 0.001, "오른쪽으로 끝까지")
	local ring = h.get("PlayerGui.Ssb.Ui.Joy.Ring")
	h.eq(ring.Visible, true, "조이스틱 그림")
	h.mouseUp()
	h.eq(Input.joy.active, false, "떼면 사라진다")
	h.step(1)
	h.eq(ring.Visible, false, "그림도 숨는다")
end
-- 새 판의 안내 흐름을 처음부터 본다
Store.seen = {}
click(E.btnPause)
click(Pause.E.quit)
h.eq(App.mode, "menu", "처음 화면으로")
click(Menu.E.start)
S = App.sim.S
E = Hud.elements()
h.advance(1.0)
h.eq(Hud.hintShown(), false, "1.2초 전에는 안내가 없다")
h.advance(0.4)
h.eq(Hud.hintShown(), true, "1.2초에 「move」 안내")
h.eq(E.hintTxt.Text:gsub("\n", " "), "WASD나 방향키, 또는 화면을 끌어서 움직입니다. 교통카드는 알아서 날아갑니다", "안내 글")
h.eq(E.hint.Visible, true, "안내 틀이 보인다")
h.eq(Sound.log[#Sound.log].name == "hover" or Sound.count("hover") > 0, true, "안내 소리(hover)")
h.step(20)
shot("hud-hint")
h.advance(5.5)
h.eq(Hud.hintShown(), false, "5.5초 뒤 사라진다")
h.advance(0.5)
h.eq(E.hint.Visible, false, "틀도 숨는다")
h.advance(8)
h.eq(Store.seen.move, 1, "seen.move")
local savedSeen = h.datastore.get("SsbPlayer_v1", "u" .. h.player().UserId).seen
h.eq(savedSeen.move, 1, "본 안내가 서버에 저장됐다")

-- ---------- 일시정지 ----------
section("일시정지")
S.p.inv = 1e9 -- (시험 동안 쓰러지지 않게)
Sound.log = {}
local function expectPaused(why)
	h.eq(App.paused, true, why .. ": 멈췄다")
	h.eq(Pause.isShown(), true, why .. ": 창이 떴다")
	local t = S.t
	h.step(20)
	h.eq(S.t, t, why .. ": 시간이 흐르지 않는다")
	h.eq(Gfx.last.running, false, why .. ": render의 running = false")
	h.eq(Sound.state.muffled, true, why .. ": 음악이 먹먹하다")
end
h.keyTap(Enum.KeyCode.P)
expectPaused("P")
h.eq(Pause.E.title.Text, "일시정지", "제목")
h.eq(Pause.E.sub.Text, "열차가 잠시 정차 중입니다", "작은 글")
h.eq(Pause.E.resume.Body.Face.T.Text, "계속 출근하기", "계속 단추")
h.eq(Sound.count("pause"), 1, "pause 소리")
shot("pause")
-- 멈춘 동안 세계를 눌러도 조이스틱이 생기지 않는다(창이 가린다)
h.mouseDown(VW * 0.05, VH * 0.5)
h.eq(Input.joy.active, false, "창이 가려 조이스틱이 생기지 않는다")
h.mouseUp()
h.keyTap(Enum.KeyCode.P)
h.eq(App.paused, false, "P로 다시")
h.eq(Pause.isShown(), false, "창이 닫혔다")
h.eq(Sound.count("resume"), 1, "resume 소리")
h.keyTap(Enum.KeyCode.Escape)
expectPaused("Esc")
click(Pause.E.resume)
h.eq(App.paused, false, "「계속 출근하기」")
h.menu(true)
expectPaused("Roblox 메뉴")
h.menu(false)
h.eq(App.paused, true, "메뉴를 닫아도 멈춘 채")
click(Pause.E.resume)
h.keyDown(Enum.KeyCode.D)
h.windowFocus(false)
expectPaused("창이 뒤로")
h.eq(Input.read().x, 0, "눌려 있던 글쇠를 잊는다")
h.windowFocus(true)
h.keyUp(Enum.KeyCode.D)
click(Pause.E.resume)
click(E.btnPause)
expectPaused("일시정지 단추")
h.eq(Sound.count("click") > 0, true, "HUD 단추의 click 소리")
click(Pause.E.resume)
if E.btnSet then
	click(E.btnSet)
	expectPaused("설정 단추")
	h.eq(Pause.E.title.Text, "설정", "설정 단추로 열면 제목이 「설정」")
	h.expect(Pause.E.quit ~= nil, "「처음 화면으로」가 있다")
	click(Pause.E.resume)
end
h.eq(App.paused, false, "다시 달린다")

-- ---------- 알림 ----------
section("알림")
App.host.banner("테스트 역", "알림 설명입니다", "station")
h.step(20)
local bn = h.get("PlayerGui.Ssb.Ui.Banner")
h.eq(bn.Visible, true, "알림이 보인다")
h.eq(bn.TagT.Text, "안내", "꼬리표")
h.eq(bn.B1.Text, "테스트 역", "제목")
h.eq(bn.B2.Text, "알림 설명입니다", "설명")
h.near(bn.UIScale.Scale, 1, 0.001, "다 나타났다")
shot("banner")
h.advance(2.7)
h.eq(Banner.isOn(), false, "2.6초 뒤 사라진다")
h.advance(0.3)
h.eq(bn.Visible, false, "숨었다")
App.host.banner("진상 등장", "보스 설명", "boss")
h.step(20)
h.eq(bn.TagT.Text, "등장", "보스 꼬리표")
shot("banner-boss")
h.advance(2.7)
h.eq(Banner.isOn(), true, "보스 알림은 3.2초")
h.advance(0.6)
h.eq(Banner.isOn(), false, "3.2초 뒤 사라진다")
for kind, text in { warn = "주의", good = "보상", heal = "회복", pass = "통과" } do
	App.host.banner("가", "", kind)
	h.eq(bn.TagT.Text, text, "꼬리표 " .. kind)
	h.eq(bn:FindFirstChild("B2"), nil, "설명이 없으면 칸도 없다")
end
App.host.banner("멈추면 숨는다", "x", "station")
h.step(15)
h.keyTap(Enum.KeyCode.P)
h.step(15)
h.eq(bn.Visible, false, "창이 떠 있는 동안 알림은 숨는다(#app.modal)")
h.keyTap(Enum.KeyCode.P)
h.step(15)
h.eq(bn.Visible, true, "다시 달리면 보인다")
h.advance(3)

-- ---------- 고르기 ----------
section("레벨 업")
Sound.log = {}
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 } -- 원두 하나를 주워 레벨 업을 일으킨다
h.waitFor(function()
	return S.state == "levelup"
end, 3, "레벨 업")
h.eq(LevelUp.isShown(), true, "고르는 창")
h.eq(h.get("PlayerGui.Ssb.Ui.LevelUp.Scroll.Panel.Title").Text, "레벨 업", "제목")
h.eq(h.get("PlayerGui.Ssb.Ui.LevelUp.Scroll.Panel.Sub").Text, "하나를 골라 챙기세요", "작은 글")
h.eq(#LevelUp.cards, 3, "카드 3장")
h.eq(Sound.count("level"), 1, "level 소리")
for i, c in S.choices do
	local card = LevelUp.cards[i]
	h.eq(card.Body.CardName.Text:gsub("\n", " "), c.name, "카드 " .. i .. " 이름")
	h.eq(card.Body.Tag.T.Text, c.tag, "카드 " .. i .. " 갈래")
	h.eq(card.Body.Tag.KeyT.Text, tostring(i), "카드 " .. i .. " 글쇠 번호")
	h.eq(card.Body.Desc.Text:gsub("\n", " "), c.desc, "카드 " .. i .. " 설명")
	h.eq(card.Body.Hint.T.Text:gsub("\n", " "), c.hint or "", "카드 " .. i .. " 쪽지")
	local icon = card.Body.IconBack.Icon
	h.expect(icon.ImageRectSize.X > 0, "카드 " .. i .. " 그림")
end
h.eq(LevelUp.reroll.T.Text, "다시 뽑기 " .. S.rerolls .. "회 남음", "다시 뽑기 단추")
-- 잘못 누름 막기: 350ms 안에는 받지 않는다
local first = S.choices[1]
h.clickOn(LevelUp.cards[1])
h.eq(S.state, "levelup", "뜨자마자 누른 것은 받지 않는다(350ms)")
h.step(30)
shot("levelup")
-- 다시 뽑기: R 글쇠 · 단추
local rr = S.rerolls
h.keyTap(Enum.KeyCode.R)
h.eq(S.rerolls, rr - 1, "R = 다시 뽑기")
h.eq(LevelUp.reroll.T.Text, "다시 뽑기 " .. (rr - 1) .. "회 남음", "남은 횟수")
h.eq(Sound.count("reroll"), 1, "reroll 소리")
h.advance(0.4)
click(LevelUp.reroll)
h.eq(S.rerolls, rr - 2, "단추로 다시 뽑기")
-- 마우스를 올리면 hover 소리
local hovers = Sound.count("hover")
reveal(LevelUp.cards[2])
h.mouseMove(h.center(LevelUp.cards[2]))
h.eq(Sound.count("hover"), hovers + 1, "카드에 마우스를 올리면 hover 소리")
-- 누르기로 고르기
h.advance(0.4)
local ver = S.buildVer
local c2 = S.choices[2]
h.clickOn(LevelUp.cards[2])
h.eq(S.state, "run", "카드를 눌러 골랐다")
h.eq(LevelUp.isShown(), false, "창이 닫혔다")
h.expect(S.buildVer > ver or c2.kind == "heal", "고른 것이 적용됐다")
h.eq(Sound.count("select") + Sound.count("evo") >= 1, true, "select 소리")
h.step(3)
-- 글쇠로 고르기: 1 · 2 · 3 (숫자판도)
for _, key in { Enum.KeyCode.One, Enum.KeyCode.Three, Enum.KeyCode.KeypadTwo } do
	S.p.xp = Sim.xpNeed(S.p.level) + 1
	S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
	h.waitFor(function()
		return S.state == "levelup"
	end, 3, "레벨 업")
	h.keyTap(key)
	h.eq(S.state, "levelup", key.Name .. ": 350ms 안에는 글쇠도 받지 않는다")
	h.advance(0.4)
	local lv = S.p.level
	h.keyTap(key)
	h.eq(S.state, "run", key.Name .. "로 골랐다")
	h.eq(S.p.level, lv, "레벨은 그대로")
	h.step(2)
end
h.eq(E.lv.Text, tostring(S.p.level), "HUD의 레벨")
-- 다시 뽑기가 0이면 단추가 흐려지고 눌리지 않는다
S.rerolls = 0
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
h.waitFor(function()
	return S.state == "levelup"
end, 3, "레벨 업")
h.eq(LevelUp.reroll:GetAttribute("Disabled"), true, "다시 뽑기 0회: 꺼진 단추")
h.eq(LevelUp.reroll.T.Text, "다시 뽑기 0회 남음", "0회")
h.keyTap(Enum.KeyCode.R)
h.eq(S.rerolls, 0, "R을 눌러도 그대로")
h.advance(0.4)
h.keyTap(Enum.KeyCode.One)
-- 상자(환승 보너스)
S.pending += 1
S.pickMode = "chest"
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
h.waitFor(function()
	return S.state == "levelup"
end, 3, "상자")
h.eq(h.get("PlayerGui.Ssb.Ui.LevelUp.Scroll.Panel.Title").Text, "환승 보너스", "상자의 제목")
h.eq(h.get("PlayerGui.Ssb.Ui.LevelUp.Scroll.Panel.Sub").Text, "진상을 밀어낸 보상입니다. 하나를 더 챙기세요", "상자의 작은 글")
while S.state == "levelup" do
	h.advance(0.4)
	h.keyTap(Enum.KeyCode.One)
end
h.step(5)
shot("hud")

-- ---------- 보스 줄 ----------
section("보스 줄")
S.zt = 999 -- 인파 버티기를 건너뛰어 진상을 부른다
runUntil(function()
	return S.gate ~= nil and not S.gate.dead
end, 8, "진상 등장")
h.step(5)
h.eq(E.bossbar.Visible, true, "보스 줄이 떴다")
h.expect(E.bossName.Text:find(S.gate.def.name .. " · 폭주까지 ", 1, true) ~= nil, "이름 · 폭주까지 m:ss (" .. E.bossName.Text .. ")")
h.eq(E.bossName.TextColor3, Color3.new(1, 1, 1), "보통: 흰 글")
h.eq(Sound.state.boss, true, "음악: 보스")
h.step(60)
shot("hud-boss")
S.rage = 2
h.step(3)
h.expect(E.bossName.Text:find(" · 폭주 2단계", 1, true) ~= nil, "폭주 단계 (" .. E.bossName.Text .. ")")
h.eq(E.bossName.TextColor3, Color3.fromRGB(255, 208, 210), "폭주: 붉은 글")
h.eq(Sound.state.late, true, "음악: 폭주")
S.rage = 0
-- 열차 안
App.sim.dbg.enterZone(3)
h.step(5)
h.eq(S.zk, "train", "열차 안")
h.eq(E.stn.Text, "강남", "다음 역 이름")
if E.stnLabel then
	h.eq(E.stnLabel.Text, "다음 역", "전광판: 다음 역")
end
h.expect(E.bossName.Text:find("^구로디지털단지 도착까지 1:[23]%d$") ~= nil, "도착까지 (" .. E.bossName.Text .. ")")
h.eq(E.bossbar.Visible, true, "타는 동안 줄이 떠 있다")
h.step(30)
shot("hud-ride")
-- 역에 서서 문이 열린 동안
runUntil(function()
	return S.doorT > 0 and S.stopIdx > 0
end, 60, "첫 역에 선다")
h.step(3)
h.eq(E.stn.Text, "강남", "이번 역 이름")
if E.stnLabel then
	h.eq(E.stnLabel.Text, "이번 역", "전광판: 이번 역")
end
h.expect(E.bossName.Text:find("^강남역 정차 · 문 닫힘까지 0:0%d$") ~= nil, "정차 (" .. E.bossName.Text .. ")")
shot("hud-doors")
runUntil(function()
	return S.doorT <= 0
end, 20, "문이 닫힌다")
h.step(3)
h.eq(E.stn.Text, "교대", "다음 역이 바뀐다")
-- 9시를 넘기면 시계가 붉어진다
S.t = Sim.GAME_LEN + 1
h.step(3)
h.eq(E.clock.Text, "09:00", "9시")
h.eq(E.clock.TextColor3, Color3.fromRGB(255, 90, 95), "지각: 붉은 시계")

-- ---------- 쓰러짐 ----------
section("쓰러짐 → 결과")
App.sim.dbg.enterZone(1)
h.step(3)
S.t = 95
S.kills = 1234
S.p.inv = 0
S.p.hp = 0.01
Sound.log = {}
for i = 1, 12 do
	App.sim.dbg.spawn("pass", S.p.x + i, S.p.y)
end
runUntil(function()
	return S.state == "over"
end, 15, "멘탈 0")
h.step(2)
h.eq(EndScreen.isShown(), true, "결과 화면")
local EE = EndScreen.E
h.eq(EE.title.Text:gsub("\n", " "), "멘탈이 무너졌습니다", "제목")
h.eq(EE.small.Text:gsub("\n", " "), "개찰구에서 멈췄습니다. 오늘은 반차를 씁니다", "작은 글")
h.eq(EE.stampText.Text, "반차", "도장")
h.eq(EE.stampClock.Text, Sim.clockText(S.t), "도장의 시각")
h.eq(EE.chip.Text, "혼잡도 여유", "난이도 딱지")
h.eq(EE.route[1]:GetAttribute("State"), "done", "경로: 역 앞은 지남")
h.eq(EE.route[2]:GetAttribute("State"), "stop", "경로: 개찰구에서 멈춤")
h.eq(EE.route[3]:GetAttribute("State"), "", "경로: 그 뒤는 못 감")
h.eq(EE.stats[1].Text, Sim.clockText(S.t), "시각")
h.eq(EE.stats[2].Text, (S.kills >= 1000) and (math.floor(S.kills / 1000) .. "," .. string.format("%03d", S.kills % 1000)) or tostring(S.kills), "밀어낸 인파(천 단위 쉼표)")
h.eq(EE.stats[3].Text, tostring(S.p.level), "레벨")
h.eq(EE.stats[4].Text:gsub(",", ""), tostring(math.floor(S.taken + 0.5)), "받은 피해")
h.expect(#EE.dmg >= 1, "피해 막대")
h.eq(EE.dmg[1].pct, 100, "가장 큰 것이 100%")
for i = 2, #EE.dmg do
	h.expect(EE.dmg[i].pct <= EE.dmg[i - 1].pct, "큰 것부터")
end
h.eq(Sound.count("lose"), 1, "lose 소리")
h.eq(Sound.state.scene, "off", "음악을 끈다")
h.eq(Gfx.last.fx, true, "render의 fx(끝난 뒤 이펙트만)")
h.eq(Hud.isShown(), true, "HUD는 뒤에 그대로")
local rec = Store.loadBest(0)
h.expect(rec ~= nil and rec.won == false and rec.zone == 1 and rec.kills == S.kills, "최고 기록에 남았다")
h.advance(1)
shot("end-lose")
-- 끝난 뒤에는 P · 대시가 듣지 않는다
h.keyTap(Enum.KeyCode.P)
h.eq(Pause.isShown(), false, "끝난 뒤 P는 듣지 않는다")
h.advance(8)
local best0 = h.datastore.get("SsbPlayer_v1", "u" .. h.player().UserId).best["0"]
h.expect(best0 ~= nil and best0.zone == 1 and best0.won == false, "서버에 기록이 저장됐다")

section("다시 출근하기")
local oldS = S
click(EE.retry)
S = App.sim.S
E = Hud.elements()
h.expect(S ~= oldS and S.state == "run" and S.t < 0.1, "새 판")
h.eq(EndScreen.isShown(), false, "결과 화면이 닫혔다")
h.step(3)
h.eq(E.clock.Text, "08:00", "시계가 처음으로")
h.eq(E.hpTxt.Text, "멘탈 170 / 170", "멘탈이 처음으로")
h.eq(E.clock.TextColor3, Color3.fromRGB(255, 179, 0), "시계 색도 처음으로")

-- ---------- 도착 ----------
section("도착 → 결과")
S.p.inv = 1e9
App.sim.dbg.enterZone(6)
S.t = 500
S.zt = 999
runUntil(function()
	return S.gate ~= nil and not S.gate.dead and (S.gate.intro or 0) <= 0
end, 10, "김 팀장 등장")
h.eq(E.stn.Text, "회사 앞", "회사 앞")
Sound.log = {}
App.sim.dbg.kill(S.gate, "card")
local guard = 0
h.waitFor(function()
	if S.state == "levelup" then
		h.advance(0.4)
		h.keyTap(Enum.KeyCode.One)
	end
	guard += 1
	return S.state == "won"
end, 20, "도착")
h.step(2)
h.eq(EndScreen.isShown(), true, "결과 화면")
EE = EndScreen.E
h.eq(S.t <= Sim.GAME_LEN, true, "9시 전")
h.eq(EE.title.Text:gsub("\n", " "), Sim.clockText(S.t) .. " 정시 출근", "제목")
h.eq(EE.small.Text:gsub("\n", " "), "사원증을 찍었습니다. 이제 진짜 하루가 시작됩니다", "작은 글")
h.eq(EE.stampText.Text:gsub("\n", " "), "정시 출근", "도장")
for i = 1, 7 do
	h.eq(EE.route[i]:GetAttribute("State"), "done", "경로 " .. i .. " 지남")
end
h.eq(Gfx.calls.celebrate, 1, "Gfx.celebrate")
h.eq(Sound.count("win"), 1, "win 소리")
local win = Store.loadBest(0)
h.expect(win ~= nil and win.won == true, "이긴 기록이 진 기록을 덮는다")
h.advance(1)
shot("end-win")

section("처음 화면으로")
click(EE.home)
h.eq(App.mode, "menu", "메뉴")
h.eq(Menu.isShown(), true, "메뉴가 보인다")
h.eq(Hud.isShown(), false, "HUD가 숨었다")
h.eq(EndScreen.isShown(), false, "결과가 닫혔다")
h.eq(App.sim.S.t >= 18, true, "시연이 돈다")
h.eq(Menu.E.best.Text:gsub("\n", " "), "여유 최고 기록  " .. Sim.clockText(win.t) .. " 출근 · 레벨 " .. win.level .. " · " .. win.kills .. "명", "최고 기록 줄")
h.step(30)
shot("menu-best")
-- Space로도 시작한다
h.keyTap(Enum.KeyCode.Space)
h.eq(App.mode, "play", "Space로 시작")

h.eq(Theme.relayouts(), 0, "글의 폭을 처음부터 맞게 쟀다(다시 놓은 적 없음)")
print("끝: flow " .. tag)
