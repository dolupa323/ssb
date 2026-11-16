-- 한 판을 처음부터 끝까지: 봇이 조종하고(원본 메뉴 시연의 sim.bot) 고르는 창은 1번 글쇠로 넘긴다. 일곱 장소를 모두 지나 도착할 때까지
--  진짜 고리(App.frame) · HUD · 알림 · 고르는 창이 계속 돈다. 쓰러지지 않게 무적으로 둔다(시험이 길어지지 않게).
--  끝에는 도착 화면과, 서버가 그 기록을 받아 저장했는지를 본다(판의 시간이 실제 시간과 맞아야 받는다).
--   node tools/mock/run.mjs --project tools/ui/test.project.json --script tools/ui/scenarios/botwin.luau --shot-dir tools/ui/shots --timeout 900
local h = harness
local VW, VH = h.viewport()
local tag = VW .. "x" .. VH

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
local EndScreen = h.require(client.ui.EndScreen, "client")
local Input = h.require(client.Input, "client")
local Store = h.require(client.ui.Store, "client")
local Sim = h.require(game.ReplicatedStorage.shared.Sim, "client")

h.clickOn(Menu.E.diff[0])
h.keyTap(Enum.KeyCode.Return)
h.eq(App.mode, "play", "시작")
local S = App.sim.S
local E = Hud.elements()
-- 조종을 봇에게 맡긴다
Input.read = function()
	local b = App.sim.bot()
	if b.dash then
		App.sim.dash()
	end
	return b
end

local seenZones, names, labels, bossTexts, picks = {}, {}, {}, {}, 0
local frames = 0
local lastShotZone = -1
h.waitFor(function()
	frames += 1
	S.p.inv = 5
	if S.state == "levelup" then
		h.advance(0.4)
		h.keyTap(Enum.KeyCode.One)
		picks += 1
		return false
	end
	if not seenZones[S.zone] then
		seenZones[S.zone] = true
		print(string.format("  장소 %d %s — %s (레벨 %d · 처치 %d)", S.zone, Sim.ZONES[S.zone + 1].name, Sim.clockText(S.t), S.p.level, S.kills))
	end
	if frames % 30 == 0 then
		names[E.stn.Text] = true
		if E.stnLabel then
			labels[E.stnLabel.Text] = true
		end
		if E.bossbar.Visible then
			local t = E.bossName.Text
			local kind = if t:find("문 닫힘까지", 1, true) then "doors" elseif t:find("도착까지", 1, true) then "ride" elseif t:find("폭주 %d+단계") then "rage" else "boss"
			bossTexts[kind] = t
		end
		-- HUD의 값이 규칙과 맞는가
		if E.lv.Text ~= tostring(S.p.level) or E.clock.Text ~= Sim.clockText(S.t) then
			h.fail("HUD가 규칙과 어긋났다: 레벨 " .. E.lv.Text .. "/" .. S.p.level .. " 시계 " .. E.clock.Text .. "/" .. Sim.clockText(S.t))
		end
	end
	if S.zone ~= lastShotZone and S.zt > 6 then
		lastShotZone = S.zone
		h.shot("zone" .. S.zone .. "-" .. tag .. ".png")
	end
	return S.state == "won" or S.state == "over"
end, 1500, "판이 끝난다")

print(string.format("  끝: %s · %s · 레벨 %d · 처치 %d · 고른 횟수 %d", S.state, Sim.clockText(S.t), S.p.level, S.kills, picks))
h.eq(S.state, "won", "도착했다")
for z = 0, 6 do
	h.eq(seenZones[z], true, "장소 " .. z .. "을(를) 지났다")
end
for _, n in { "역삼역 앞", "개찰구", "역삼 승강장", "구디 승강장", "에스컬레이터", "회사 앞", "강남", "교대", "사당", "신림" } do
	h.eq(names[n], true, "전광판에 「" .. n .. "」이(가) 떴다")
end
if E.stnLabel then
	for _, n in { "지금 여기", "다음 역", "이번 역" } do
		h.eq(labels[n], true, "전광판의 작은 글 「" .. n .. "」")
	end
end
h.expect(bossTexts.boss ~= nil, "보스 줄: 진상 (" .. tostring(bossTexts.boss) .. ")")
h.expect(bossTexts.ride ~= nil, "보스 줄: 도착까지 (" .. tostring(bossTexts.ride) .. ")")
h.expect(bossTexts.doors ~= nil, "보스 줄: 정차 (" .. tostring(bossTexts.doors) .. ")")
h.step(90)
h.eq(EndScreen.isShown(), true, "결과 화면")
local late = S.t > Sim.GAME_LEN
h.eq(EndScreen.E.title.Text:gsub("\n", " "), Sim.clockText(S.t) .. (if late then " 지각 출근" else " 정시 출근"), "제목")
h.eq(EndScreen.E.stampText.Text:gsub("\n", " "), if late then "지각" else "정시 출근", "도장")
h.shot("botwin-end-" .. tag .. ".png")
local rec = Store.loadBest(0)
h.expect(rec ~= nil and rec.won == true and rec.t == S.t, "최고 기록")
h.advance(8)
local saved = h.datastore.get("SsbPlayer_v1", "u" .. h.player().UserId)
h.expect(saved ~= nil and saved.best["0"] ~= nil and saved.best["0"].won == true, "서버가 도착 기록을 받아 저장했다")
h.eq(#h.errors(), 0, "오류 없이 끝까지")
print("끝: botwin " .. tag)
