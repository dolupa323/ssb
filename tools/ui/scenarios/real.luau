-- 진짜 모듈(src/client/Gfx.luau · Sound.luau)로 돌린다 — default.project.json 그대로. 대역(tools/ui/stubs)에만 있는 것은 보지 않는다.
--  불러오기 → 메뉴 → 시작 → 움직이기 → 고르기 → 일시정지 → 진상 → 쓰러짐 → 다시 → 도착 → 처음 화면. 화면마다 찍는다(real-*.png).
--   node tools/mock/run.mjs --script tools/ui/scenarios/real.luau --shot-dir tools/ui/shots [--viewport WxH] [--touch]
local h = harness
local VW, VH = h.viewport()
local tag = VW .. "x" .. VH

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
local touch = game:GetService("UserInputService").TouchEnabled
local function press(inst)
	reveal(inst)
	if touch then
		h.tapOn(inst)
	else
		h.clickOn(inst)
	end
end
local function shot(name)
	h.shot("real-" .. name .. "-" .. tag .. ".png")
end

h.waitFor(function()
	return h.find("PlayerGui.Ssb.Top.Loading") ~= nil
end, 2, "불러오는 화면이 뜬다(글자 판을 만든 뒤)")
h.expect(h.find("PlayerGui.Ssb.Top.Loading") ~= nil, "불러오는 화면")
h.waitFor(function()
	return h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 30, "불러오기가 끝난다")
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
local EndScreen = h.require(client.ui.EndScreen, "client")
local Gfx = h.require(client.Gfx, "client")
local Sim = h.require(game.ReplicatedStorage.shared.Sim, "client")
h.eq(Gfx.isStub, nil, "진짜 Gfx")
local function runUntil(cond, timeout, what)
	return h.waitFor(function()
		local v = cond()
		if v then
			return v
		end
		if App.mode == "play" and App.sim.S.state == "levelup" then
			h.advance(0.4)
			press(LevelUp.cards[1])
		end
		return false
	end, timeout, what)
end

print("== 메뉴 ==")
h.eq(App.mode, "menu", "메뉴")
local t0 = App.sim.S.t
h.step(90)
h.near(App.sim.S.t - t0, 1.5, 0.05, "시연이 돈다")
shot("menu")
press(Menu.E.btnSet)
h.eq(Pause.isShown(), true, "설정")
shot("menu-settings")
press(Pause.E.resume)
press(Menu.E.diff[0])

print("== 시작 ==")
press(Menu.E.start)
h.eq(App.mode, "play", "시작")
local S = App.sim.S
local E = Hud.elements()
h.step(150)
h.eq(E.hpTxt.Text, "멘탈 " .. math.ceil(S.p.hp) .. " / " .. S.p.maxhp, "멘탈")
shot("hud-hint")
if not touch then
	local x = S.p.x
	h.keyDown(Enum.KeyCode.D)
	h.step(30)
	h.keyUp(Enum.KeyCode.D)
	h.expect(S.p.x - x > 30, "D로 걷는다")
	local d = S.dashes
	h.keyTap(Enum.KeyCode.Space)
	h.eq(S.dashes, d + 1, "Space로 대시")
else
	local ox, oy = VW * 0.25, VH * 0.6
	local x = S.p.x
	h.touchBegin(1, ox, oy)
	h.touchMove(1, ox + 80, oy)
	h.step(30)
	h.expect(S.p.x - x > 30, "끌어서 걷는다")
	local d = S.dashes
	h.touchBegin(2, VW * 0.7, VH * 0.4)
	h.touchEnd(2)
	h.eq(S.dashes, d + 1, "다른 손가락으로 대시")
	shot("joystick")
	h.touchEnd(1)
end
S.p.inv = 1e9

print("== 고르기 ==")
S.p.xp = Sim.xpNeed(S.p.level) + 1
S.beans[#S.beans + 1] = { x = S.p.x, y = S.p.y, v = 1, att = true, sp = 0, ph = 0 }
h.waitFor(function()
	return S.state == "levelup"
end, 3, "레벨 업")
h.eq(#LevelUp.cards, 3, "카드 3장")
h.advance(0.5)
shot("levelup")
press(LevelUp.cards[2])
h.eq(S.state, "run", "골랐다")

print("== 일시정지 ==")
press(E.btnPause)
h.eq(App.paused, true, "멈춤")
h.step(10)
shot("pause")
press(Pause.E.resume)
h.eq(App.paused, false, "계속")

print("== 진상 ==")
S.zt = 999
runUntil(function()
	return S.gate ~= nil and not S.gate.dead and (S.gate.intro or 0) <= 0
end, 10, "진상 등장")
h.step(60)
h.eq(E.bossbar.Visible, true, "보스 줄")
shot("hud-boss")
App.sim.dbg.enterZone(3)
h.step(120)
h.expect(E.bossName.Text:find("도착까지", 1, true) ~= nil, "열차: 도착까지")
shot("hud-ride")

print("== 쓰러짐 ==")
S.p.inv = 0
S.p.hp = 0.01
for i = 1, 12 do
	App.sim.dbg.spawn("pass", S.p.x + i, S.p.y)
end
runUntil(function()
	return S.state == "over"
end, 15, "멘탈 0")
h.eq(EndScreen.isShown(), true, "결과")
h.eq(EndScreen.E.stampText.Text, "반차", "도장")
h.advance(1.5)
shot("end-lose")

print("== 다시 → 도착 ==")
press(EndScreen.E.retry)
S = App.sim.S
h.eq(S.state, "run", "새 판")
S.p.inv = 1e9
App.sim.dbg.enterZone(6)
S.t = 500
S.zt = 999
runUntil(function()
	return S.gate ~= nil and not S.gate.dead and (S.gate.intro or 0) <= 0
end, 10, "김 팀장")
App.sim.dbg.kill(S.gate, "card")
runUntil(function()
	return S.state == "won"
end, 20, "도착")
h.eq(EndScreen.isShown(), true, "결과")
h.advance(1.5)
shot("end-win")
press(EndScreen.E.home)
h.eq(App.mode, "menu", "처음 화면")
h.step(30)
h.eq(#h.errors(), 0, "오류 없음")
print("끝: real " .. tag)
