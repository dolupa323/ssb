-- 손가락 기기: 세계를 끌면 그 자리에 뜨는 조이스틱(8px 안쪽은 무시 · 52px에서 끝까지), 다른 손가락으로 치면 대시, 대시 단추, 카드 · 단추 누르기.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --script tools/ui/scenarios/touch.luau --shot-dir tools/ui/shots --viewport 844x390 --touch
local h = harness
local VW, VH = h.viewport()
local tag = VW .. "x" .. VH

local function section(s)
	print("== " .. s .. " ==")
end
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
local function tap(inst)
	reveal(inst)
	local got = h.tapOn(inst)
	h.eq(got, inst, "누른 것을 그 단추가 받았다: " .. inst.Name)
end

h.waitFor(function()
	return h.find("PlayerGui.Ssb.Ui.Menu") ~= nil and h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 20, "불러오기가 끝난다")
local client = h.player().PlayerScripts.client
-- mock은 글자를 TextSize x 0.85 크기로 그린다(진짜 Roblox와 다르다). 본문 글씨가 원본과 같은 크기로 찍히게 mock 안에서만 배율을 1.2로 둔다
--  (Roblox에서 쓰는 값은 ui/Theme.luau의 BODY_FS — 이 시험과 상관없다). 화면을 다시 만들게 크기를 한 번 흔든다.
local Theme = h.require(client.ui.Theme, "client")
Theme.FS = 1.2
h.resize(VW + 2, VH)
h.resize(VW, VH)
h.step(2)
local App = h.require(client.ui.App, "client")
local Menu = h.require(client.ui.Menu, "client")
local Hud = h.require(client.ui.Hud, "client")
local Pause = h.require(client.ui.Pause, "client")
local LevelUp = h.require(client.ui.LevelUp, "client")
local Stage = h.require(client.Stage, "client")
local Input = h.require(client.Input, "client")
local Store = h.require(client.ui.Store, "client")
local Sound = h.require(client.Sound, "client")
local Sim = h.require(game.ReplicatedStorage.shared.Sim, "client")

section("기기")
h.eq(Stage.touchLike(), true, "손가락 기기로 본다")
h.eq(h.playerGui().ScreenOrientation, Enum.ScreenOrientation.LandscapeSensor, "가로 화면")
local sc = Stage.scale

section("메뉴: 굴려서 누른다")
-- 메뉴에서 세계를 눌러도 조이스틱은 생기지 않는다
h.touchBegin(9, VW - 20, VH / 2)
h.eq(Input.joy.active, false, "메뉴에서는 조이스틱이 없다")
h.touchEnd(9)
h.eq(Sound.inits > 0, true, "처음 누를 때 소리를 깨운다(Sound.init)")
tap(Menu.E.diff[2])
h.eq(Store.diff, 2, "혼잡을 눌렀다")
tap(Menu.E.start)
h.eq(App.mode, "play", "출근하기를 눌러 시작")
h.step(3)
local S = App.sim.S
local E = Hud.elements()
S.p.inv = 1e9
h.eq(E.hpTxt.Text, "멘탈 100 / 100", "혼잡의 멘탈")

section("조이스틱")
local ring = h.get("PlayerGui.Ssb.Ui.Joy.Ring")
local knob = h.get("PlayerGui.Ssb.Ui.Joy.Knob")
local ox, oy = math.floor(VW * 0.25), math.floor(VH * 0.62)
h.touchBegin(1, ox, oy)
h.eq(Input.joy.active, true, "세계를 누르면 조이스틱이 선다")
h.step(1)
h.eq(ring.Visible, true, "고리가 보인다")
h.near(ring.Position.X.Offset, ox / sc, 0.01, "고리는 누른 자리에(x)")
h.near(ring.Position.Y.Offset, oy / sc, 0.01, "고리는 누른 자리에(y)")
h.near(ring.Size.X.Offset + 2 * ring.UIStroke.Thickness, 2 * 52 + 3, 0.01, "고리의 바깥 지름 = 반지름 52 + 선 3")
h.eq(knob.Size.X.Offset, 42, "손잡이 지름 42")
local i = Input.read()
h.eq({ i.x, i.y }, { 0, 0 }, "움직이지 않으면 입력 없음")
h.touchMove(1, ox + 8 * sc, oy)
i = Input.read()
h.eq({ i.x, i.y }, { 0, 0 }, "8px까지는 무시")
h.touchMove(1, ox + 26 * sc, oy)
i = Input.read()
h.near(i.x, 0.5, 0.001, "26px = 반")
h.eq(i.y, 0, "y는 0")
h.touchMove(1, ox + 52 * sc, oy)
h.near(Input.read().x, 1, 0.001, "52px = 끝")
h.touchMove(1, ox + 140 * sc, oy)
h.near(Input.read().x, 1, 0.001, "더 끌어도 1")
h.step(1)
h.near(knob.Position.X.Offset, ox / sc + 52, 0.01, "손잡이는 52px에서 멈춘다")
local x0 = S.p.x
h.step(20)
h.expect(S.p.x - x0 > 20, "오른쪽으로 걷는다 (" .. (S.p.x - x0) .. ")")
h.touchMove(1, ox - 30 * sc, oy - 40 * sc)
i = Input.read()
h.near(i.x, -0.6 * (50 / 52), 0.001, "대각선 x")
h.near(i.y, -0.8 * (50 / 52), 0.001, "대각선 y")
h.step(2)
h.shot("touch-joystick-" .. tag .. ".png")

section("다른 손가락으로 대시")
local dashes = S.dashes
h.touchBegin(2, VW * 0.6, VH * 0.5)
h.eq(S.dashes, dashes + 1, "두 번째 손가락으로 치면 대시")
h.eq(Input.joy.active, true, "조이스틱은 그대로")
h.touchEnd(2)
h.eq(Input.joy.active, true, "두 번째 손가락을 떼도 조이스틱은 그대로")
h.near(Input.read().x, -0.6 * (50 / 52), 0.001, "방향도 그대로")
h.advance(3)
-- 끄는 동안 대시 단추
h.touchBegin(3, h.center(E.dash))
h.eq(S.dashes, dashes + 2, "대시 단추")
h.touchEnd(3)
h.eq(Input.joy.active, true, "대시 단추를 눌러도 조이스틱은 그대로")
h.touchEnd(1)
h.eq(Input.joy.active, false, "첫 손가락을 떼면 조이스틱이 사라진다")
h.step(1)
h.eq(ring.Visible, false, "고리도 숨는다")
h.step(40) -- (방금 한 대시가 끝나기를 기다린다)
local px, py = S.p.x, S.p.y
h.step(10)
h.near(S.p.x, px, 1, "멈춘다")
-- 한 손가락으로 톡 치기만 하면(끌지 않으면) 대시가 아니다
h.advance(3)
dashes = S.dashes
h.tap(VW * 0.5, VH * 0.5)
h.eq(S.dashes, dashes, "첫 손가락의 톡은 조이스틱일 뿐 대시가 아니다")
-- 단추 위에서 시작한 손가락은 조이스틱이 되지 않는다
h.touchBegin(4, h.center(E.btnPause))
h.eq(Input.joy.active, false, "단추를 누른 손가락은 조이스틱이 아니다")
h.touchEnd(4)
h.eq(App.paused, true, "일시정지 단추를 눌렀다")
tap(Pause.E.resume)
h.eq(App.paused, false, "계속")

section("카드 누르기")
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
h.touchBegin(1, ox, oy)
h.touchMove(1, ox + 60, oy)
h.waitFor(function()
	return S.state == "levelup"
end, 3, "레벨 업")
h.eq(Input.joy.active, false, "고르는 창이 뜨면 조이스틱을 놓는다")
h.touchEnd(1)
h.advance(0.4)
h.shot("touch-levelup-" .. tag .. ".png")
tap(LevelUp.cards[3])
h.eq(S.state, "run", "카드를 눌러 골랐다")

print("끝: touch " .. tag)
