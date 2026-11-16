-- 화면 크기가 바뀔 때(창 크기 · 가로세로): 배치가 원본의 기준(980px 이상 = 넓은 메뉴 · 640px 이하 = 폰 배치)에 맞춰 다시 놓이고, 떠 있던 화면과 값이 그대로다.
--  게임패드(왼쪽 막대는 mock이 흉내 내지 않는다 — A · Start만)도 여기서 본다.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --script tools/ui/scenarios/resize.luau --shot-dir tools/ui/shots
local h = harness

h.waitFor(function()
	return h.find("PlayerGui.Ssb.Ui.Menu") ~= nil and h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 20, "불러오기가 끝난다")
local client = h.player().PlayerScripts.client
h.require(client.ui.Theme, "client").FS = 1.2 -- (mock의 글자 크기 어림에 맞춘 값 — flow.luau의 설명 참고)
local App = h.require(client.ui.App, "client")
local Menu = h.require(client.ui.Menu, "client")
local Hud = h.require(client.ui.Hud, "client")
local Pause = h.require(client.ui.Pause, "client")
local LevelUp = h.require(client.ui.LevelUp, "client")
local EndScreen = h.require(client.ui.EndScreen, "client")
local Stage = h.require(client.Stage, "client")
local Gfx = h.require(client.Gfx, "client")
local Store = h.require(client.ui.Store, "client")
local Sim = h.require(game.ReplicatedStorage.shared.Sim, "client")

print("== 메뉴: 넓은 화면 ↔ 좁은 화면 ==")
local function signX()
	local x = h.rect(Menu.E.sign)
	return x
end
h.eq(Stage.wide, true, "1280: 넓다")
h.near(signX(), math.clamp(0.06 * 1280, 24, 96) + 3, 0.6, "넓은 화면: 판이 왼쪽(6vw)에 붙는다")
h.eq(Gfx.last.offX, -0.2, "시연을 오른쪽으로 민다")
h.resize(900, 700)
h.step(3)
h.eq({ Stage.w, Stage.h, Stage.wide, Stage.phone }, { 900, 700, false, false }, "900x700: 가운데 배치")
h.near(signX(), (900 - 560) / 2 + 3, 0.6, "판이 가운데")
h.eq(Gfx.last.offX, 0, "시연을 밀지 않는다")
h.eq(Menu.E.title.Text, "출근길 서바이벌", "다시 만든 뒤에도 글이 그대로")
h.resize(3840, 2160)
h.step(3)
h.eq(Stage.scale, 2, "4K: 2배로 키운다(1920x1080과 같은 배치)")
h.eq({ Stage.w, Stage.h }, { 1920, 1080 }, "화면 틀은 1920x1080")
h.shot("resize-menu-3840x2160.png")
h.resize(600, 400)
h.step(3)
h.eq({ Stage.phone, Stage.wide }, { true, false }, "600x400: 폰 배치")
h.near(signX(), (600 - 560) / 2 + 3, 0.6, "판(폭 560)이 가운데")
h.shot("resize-menu-600x400.png")

print("== 게임 중 ==")
h.resize(1280, 720)
h.step(3)
h.clickOn(Menu.E.diff[0])
h.clickOn(Menu.E.start)
local S = App.sim.S
S.p.inv = 1e9
h.advance(3)
local E = Hud.elements()
h.expect(E.btnSet ~= nil and E.kills ~= nil and E.mini ~= nil, "넓은 HUD: 설정 단추 · 처치 수 · 경로 줄이 있다")
local x0 = h.rect(E.dash)
h.resize(600, 400)
h.step(3)
E = Hud.elements()
h.eq(E.btnSet, nil, "폰 HUD: 설정 단추가 없다")
h.eq(E.kills, nil, "폰 HUD: 처치 수가 없다")
h.eq(E.mini, nil, "폰 HUD: 경로 줄이 없다")
h.eq(E.clock.Text, Sim.clockText(S.t), "시계가 이어진다")
h.eq(E.lv.Text, tostring(S.p.level), "레벨이 이어진다")
local dx, dy, dw, dh = h.rect(E.dash)
h.near(dw, 98, 0.5, "폰: 대시 단추 98px")
h.near(dx + dw, 600 - 14, 0.5, "폰: 오른쪽에서 14px")
h.near(dy + dh, 400 - 72, 0.5, "폰: 아래에서 72px")
h.shot("resize-hud-600x400.png")
-- 대시 버튼 왼쪽(폰 배치에서만 옮겨진다)
h.clickOn(E.btnPause)
h.eq(Pause.isShown(), true, "일시정지")
local hand2 = h.get("PlayerGui.Ssb.Ui.Pause.Scroll.Panel.Sets.Set_hand2")
local p = hand2.Parent.Parent.Parent
p.CanvasPosition = Vector2.new(0, 200)
h.step(1)
h.clickOn(hand2)
h.eq(Store.set.hand, 1, "대시 버튼 왼쪽")
E = Hud.elements()
dx = h.rect(E.dash)
h.near(dx, 14, 0.5, "폰: 왼쪽에서 14px")
h.shot("resize-pause-600x400.png")
-- 멈춘 채 크기를 바꿔도 창이 그대로
h.resize(1280, 720)
h.step(3)
h.eq(Pause.isShown(), true, "크기를 바꿔도 창이 떠 있다")
h.eq(Pause.E.title.Text, "일시정지", "제목 그대로")
E = Hud.elements()
dx, dy, dw = h.rect(E.dash)
h.near(dx + dw, 1280 - 18, 0.5, "넓은 화면에서는 왼손 설정이어도 오른쪽(원본 CSS가 그렇다)")
h.near(dx, x0, 0.5, "처음 자리와 같다")
h.clickOn(Pause.E.resume)

print("== 게임패드 ==")
h.setDevice({ gamepad = true })
local d = S.dashes
h.advance(3)
h.keyTap(Enum.KeyCode.ButtonA)
h.eq(S.dashes, d + 1, "A = 대시")
h.keyTap(Enum.KeyCode.ButtonStart)
h.eq(App.paused, true, "Start = 일시정지")
h.keyTap(Enum.KeyCode.ButtonStart)
h.eq(App.paused, false, "Start = 다시")

print("== 고르는 창 · 결과 ==")
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
h.waitFor(function()
	return S.state == "levelup"
end, 3, "레벨 업")
local names = {}
for i, c in S.choices do
	names[i] = c.name
end
h.resize(600, 400)
h.step(3)
h.eq(LevelUp.isShown(), true, "크기를 바꿔도 고르는 창이 떠 있다")
h.eq(#LevelUp.cards, 3, "카드 3장")
for i = 1, 3 do
	h.eq(LevelUp.cards[i].Body.CardName.Text:gsub("\n", " "), names[i], "카드 " .. i .. " 그대로")
end
local _, y1 = h.rect(LevelUp.cards[1])
local _, y2 = h.rect(LevelUp.cards[2])
h.expect(y2 > y1 + 50, "폰: 카드가 세로로 쌓인다")
h.shot("resize-levelup-600x400.png")
h.advance(0.4)
h.keyTap(Enum.KeyCode.One)
h.eq(S.state, "run", "골랐다")
S.p.inv = 0
S.p.hp = 0.01
for i = 1, 12 do
	App.sim.dbg.spawn("pass", S.p.x + i, S.p.y)
end
h.waitFor(function()
	if S.state == "levelup" then
		h.advance(0.4)
		h.keyTap(Enum.KeyCode.One)
	end
	return S.state == "over"
end, 15, "멘탈 0")
h.advance(1)
h.shot("resize-end-600x400.png")
h.resize(1280, 720)
h.step(3)
h.eq(EndScreen.isShown(), true, "크기를 바꿔도 결과가 떠 있다")
h.eq(EndScreen.E.stampText.Text, "반차", "도장 그대로")
h.eq(#h.errors(), 0, "오류 없음")
print("끝: resize")
