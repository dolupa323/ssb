-- DataStore를 읽지 못할 때: 게임은 기본값으로 그대로 시작하고, 이 접속 동안의 값은 기억에 남는다.
--  그 뒤 DataStore가 살아나 저장하게 되더라도 「이번에 바꾼 칸」만 쓰고, 읽지 못했던 나머지(설정 · 기록)는 지우지 않는다.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --no-start --script tools/ui/scenarios/server_fail.luau
local h = harness
local STORE, KEY = "SsbPlayer_v1", "u1001"

print("== 읽기가 세 번 모두 실패한다 ==")
h.datastore.set(STORE, KEY, {
	v = 1,
	set = { music = 35, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 },
	seen = { move = 1 },
	diff = 2,
	best = { ["2"] = { t = 120, kills = 300, level = 9, won = false, zone = 2 } },
	at = 0,
})
h.datastore.failNext(3)
h.start()
h.waitFor(function()
	return h.find("PlayerGui.Ssb.Ui.Menu") ~= nil and h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 30, "읽지 못해도 메뉴까지 간다")
h.expect(h.time() < 12, "오래 붙잡지 않는다 (" .. h.time() .. "초)")
local player = h.player()
local client = player.PlayerScripts.client
local App = h.require(client.ui.App, "client")
local Store = h.require(client.ui.Store, "client")
local Menu = h.require(client.ui.Menu, "client")
local Data = h.require(game.ServerScriptService.server.Data, "server")
local warned = false
for _, w in h.warnings() do
	if string.find(w.text, "자료를 읽지 못했다", 1, true) then
		warned = true
	end
end
h.eq(warned, true, "서버가 경고를 냈다")
h.eq(Store.loaded, false, "읽지 못했다고 안다")
h.eq(Store.set, { music = 80, sfx = 80, fx = 2, shake = 1, hand = 0, bloom = 1 }, "기본 설정")
h.eq(Store.diff, 1, "기본 난이도")
h.eq(next(Store.best), nil, "기록 없음")
h.eq(App.mode, "menu", "메뉴가 돈다")
local t0 = App.sim.S.t
h.step(30)
h.expect(App.sim.S.t > t0, "시연도 돈다")

print("== 이 접속 동안은 기억에 남는다 ==")
h.clickOn(Menu.E.diff[3])
h.eq(Store.diff, 3, "난이도를 바꿨다")
h.step(3)
h.eq(Data.sessions[player].data.diff, 3, "서버의 기억에도")
h.eq(Data.sessions[player].ok, false, "서버: 읽지 못한 접속")

print("== 나중에 저장될 때 읽지 못했던 것을 지우지 않는다 ==")
h.advance(8)
local saved = h.datastore.get(STORE, KEY)
h.eq(saved.diff, 3, "바꾼 난이도는 저장")
h.eq(saved.set, { music = 35, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 }, "읽지 못했던 설정은 그대로")
h.eq(saved.seen, { move = 1 }, "본 안내도 그대로")
h.eq(saved.best["2"].t, 120, "기록도 그대로")

print("== 저장 길(서버)이 아예 없어도 클라이언트는 돈다 ==")
-- (이 접속에서는 길이 있으니, Store가 실패를 삼키는지만 본다: 길을 지운 뒤 설정을 바꾼다)
game.ReplicatedStorage.SsbNet:Destroy()
h.clickOn(Menu.E.diff[0])
h.step(5)
h.eq(Store.diff, 0, "길이 사라져도 화면은 바뀐다")
h.eq(App.mode, "menu", "오류 없이 계속 돈다")

print("끝: server_fail")
