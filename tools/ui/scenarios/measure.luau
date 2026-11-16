-- 본문 글의 폭을 처음에 잘못 쟀을 때(진짜 Roblox에서 일어난 일: 막 만든 꼬리표의 폭을 어림으로 재면 실제보다 좁게 나와 알림 상자가 글보다 좁았다)
--  → 그려진 뒤의 진짜 폭(TextBounds)을 보고 상자를 다시 놓는가. mock에서는 TextBounds가 늘 맞으므로, 일부러 「어림으로만 재고 그 어림이 20% 좁게」 만들어 본다.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --script tools/ui/scenarios/measure.luau --shot-dir tools/ui/shots
local h = harness
local VW, VH = h.viewport()

h.waitFor(function()
	return h.find("PlayerGui.Ssb.Ui.Menu") ~= nil and h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 20, "불러오기가 끝난다")
local client = h.player().PlayerScripts.client
local Theme = h.require(client.ui.Theme, "client")
Theme.FS = 1.2
local App = h.require(client.ui.App, "client")
local Menu = h.require(client.ui.Menu, "client")
local Hud = h.require(client.ui.Hud, "client")

print("== 시작할 때 맞춘 자 ==")
for _, w in { 400, 500, 600, 700 } do
	h.near(Theme.calib[w], 1, 0.06, "배율(굵기 " .. w .. ") — mock에서는 1쯤")
end
h.eq(Theme.syncBounds, true, "mock: 글을 바꾸면 바로 TextBounds가 바뀐다")
h.expect(h.find("PlayerGui.Ssb.Ui.TextProbe") ~= nil, "견본 꼬리표가 화면에 있다")
local px, py, pw, ph = h.rect(h.get("PlayerGui.Ssb.Ui.TextProbe"))
h.expect(pw <= 2 and ph <= 2, "견본은 2x2 안으로 잘려 보이지 않는다")

h.clickOn(Menu.E.diff[0])
h.clickOn(Menu.E.start)
h.eq(App.mode, "play", "시작")
App.sim.S.p.inv = 1e9
h.advance(9) -- (시작할 때의 알림 · 안내가 지나가게)

-- 진짜 Roblox처럼: 어림으로만 재고(syncBounds = false), 그 어림이 20% 좁다
local function sabotage()
	Theme.syncBounds = false
	for _, w in { 400, 500, 600, 700 } do
		Theme.calib[w] = 0.8
	end
end
-- 상자가 글을 담고 있는가: 글의 오른쪽 끝 + 원본의 오른쪽 여백 ≤ 상자의 오른쪽 끝
local function slack(box, label, pad)
	local bx, _, bw = h.rect(box)
	local lx = h.rect(label)
	return (bx + bw) - (lx + label.TextBounds.X + pad)
end

print("== 알림: 처음에는 좁게 재지만 그려진 뒤 고쳐진다 ==")
sabotage()
local n0 = Theme.relayouts()
App.host.banner("버스가 옵니다", "차도 밖으로 물러나세요. 인파는 치고 지나갑니다", "warn")
h.step(2)
local bn = h.get("PlayerGui.Ssb.Ui.Banner")
h.expect(slack(bn, bn.B2, 15) < -10, "(시험이 맞게 짜였나) 처음 놓은 상자는 글보다 좁다: " .. slack(bn, bn.B2, 15))
h.step(40)
bn = h.get("PlayerGui.Ssb.Ui.Banner")
h.expect(slack(bn, bn.B2, 15) >= -1.5, "다시 놓은 뒤: 설명 글 + 오른쪽 여백 15px이 상자 안에 든다 (" .. slack(bn, bn.B2, 15) .. ")")
h.eq(bn.B2.Text, "차도 밖으로 물러나세요. 인파는 치고 지나갑니다", "글은 그대로")
h.eq(bn.Visible, true, "알림은 계속 떠 있다")
h.expect(Theme.relayouts() > n0, "화면을 다시 놓았다")
h.expect(Theme.calib[600] > 0.95, "어림의 배율도 고쳐졌다 — 설명 글의 굵기 600 (" .. Theme.calib[600] .. ")")
h.shot("measure-banner-" .. VW .. "x" .. VH .. ".png")
-- 같은 글을 다시 띄우면 처음부터 맞게 놓인다(기억한 폭)
h.advance(4)
sabotage()
local n1 = Theme.relayouts()
App.host.banner("버스가 옵니다", "차도 밖으로 물러나세요. 인파는 치고 지나갑니다", "warn")
h.step(2)
bn = h.get("PlayerGui.Ssb.Ui.Banner")
h.expect(slack(bn, bn.B2, 15) >= -1.5, "두 번째: 처음부터 맞다 (" .. slack(bn, bn.B2, 15) .. ")")
h.step(30)
h.eq(Theme.relayouts(), n1, "다시 놓을 일이 없었다")
h.advance(4)

print("== 안내 상자도 같다 ==")
sabotage()
Hud.hint("둘러싸이면 Space 또는 대시 버튼. 터치라면 다른 손가락으로 화면을 톡 쳐도 됩니다")
h.step(45)
local E = Hud.elements()
local longest = 0
for _, line in string.split(E.hintTxt.Text, "\n") do
	longest = math.max(longest, #line)
end
h.expect(slack(E.hint, E.hintTxt, 14) >= -1.5, "안내 글 + 오른쪽 여백 14px이 상자 안에 든다 (" .. slack(E.hint, E.hintTxt, 14) .. ")")
h.shot("measure-hint-" .. VW .. "x" .. VH .. ".png")

print("== 다시 놓기는 한도 안에서 멈춘다 ==")
for i = 1, 12 do
	sabotage()
	App.host.banner("알림 " .. i, "설명 글 번호 " .. i .. " — 길이가 조금씩 다른 글입니다 " .. string.rep("가", i), "station")
	h.step(30)
end
h.expect(Theme.relayouts() <= Theme.RELAYOUT_MAX, "다시 놓은 횟수 " .. Theme.relayouts() .. " ≤ 한도 " .. Theme.RELAYOUT_MAX)
h.eq(#h.errors(), 0, "오류 없음")
print("끝: measure")
