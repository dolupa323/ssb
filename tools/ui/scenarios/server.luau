-- 서버: 들어올 때 읽기(다시 시도) → 화면에 반영 → 틀린 쓰기 거르기 → 저장 → 저장 실패 뒤 다시 → 나갔다 다시 들어오기.
--   node tools/mock/run.mjs --project tools/ui/test.project.json --no-start --script tools/ui/scenarios/server.luau
local h = harness
local Players = game:GetService("Players")
local STORE, KEY = "SsbPlayer_v1", "u1001"

local function section(s)
	print("== " .. s .. " ==")
end

section("미리 저장된 자료로 들어온다(첫 읽기는 실패 → 다시 시도)")
h.datastore.set(STORE, KEY, {
	v = 1,
	set = { music = 35, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0, junk = 9 },
	seen = { move = 1, xp = 1, bogus = 1 },
	diff = 2,
	best = {
		["0"] = { t = 400, kills = 2000, level = 30, won = true, zone = 6 },
		["1"] = { t = -5, kills = 1, level = 1, won = false, zone = 0 }, -- 틀린 기록: 버려야 한다
		["2"] = { t = 120, kills = 300, level = 9, won = false, zone = 2 },
	},
	at = 0,
})
h.datastore.failNext(1)
h.start()
h.waitFor(function()
	return h.find("PlayerGui.Ssb.Ui.Menu") ~= nil and h.find("PlayerGui.Ssb.Top.Loading") == nil
end, 30, "불러오기가 끝난다")
local player = h.player()
h.eq(player.UserId, 1001, "UserId")
local client = player.PlayerScripts.client
local Store = h.require(client.ui.Store, "client")
local Menu = h.require(client.ui.Menu, "client")
local Gfx = h.require(client.Gfx, "client")
local Sound = h.require(client.Sound, "client")
local Data = h.require(game.ServerScriptService.server.Data, "server")
local Net = h.require(game.ReplicatedStorage.shared.Net, "server")
local calls = h.datastore.calls()
h.eq(calls[1].op, "GetAsync", "첫 DataStore 호출은 읽기")
h.eq(calls[2].op, "GetAsync", "실패해서 한 번 더 읽었다")
h.eq(Store.loaded, true, "클라이언트가 자료를 받았다")
h.eq(Store.set, { music = 35, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 }, "설정(모르는 칸은 버린다)")
h.eq(Store.seen, { move = 1, xp = 1 }, "본 안내(모르는 이름은 버린다)")
h.eq(Store.diff, 2, "고른 난이도")
h.eq(Store.best["0"], { t = 400, kills = 2000, level = 30, won = true, zone = 6 }, "여유의 기록")
h.eq(Store.best["1"], nil, "틀린 기록은 버린다")
h.eq(Store.best["2"].zone, 2, "혼잡의 기록")
-- 화면 · 소리 · 그림 설정에 반영됐다
h.eq(Menu.E.diff[2]:GetAttribute("Pressed"), true, "메뉴: 혼잡이 눌려 있다")
h.eq(Menu.E.best.Text:gsub("\n", " "), "혼잡 최고 기록  역삼역 승강장까지 (08:13) · 레벨 9 · 300명", "메뉴: 최고 기록 줄")
h.eq(Sound.volume, { music = 0.35, sfx = 0.6 }, "Sound.vol")
h.eq({ Gfx.calls.opts.fx, Gfx.calls.opts.shake, Gfx.calls.opts.bloom }, { 1, 0, 0 }, "Gfx.opts")
h.clickOn(Menu.E.diff[0])
h.eq(Menu.E.best.Text:gsub("\n", " "), "여유 최고 기록  08:44 출근 · 레벨 30 · 2000명", "메뉴: 이긴 기록 줄")

section("틀린 쓰기는 버린다")
local save = game.ReplicatedStorage.SsbNet.Save
local s = Data.sessions[player]
h.expect(s ~= nil and s.loaded and s.ok, "서버의 접속 자료")
h.advance(8) -- (위에서 바꾼 난이도가 저장되기를 기다린다)
local function send(kind, value)
	h.asClient(function()
		save:FireServer(kind, value)
	end)
	h.step(20) -- (요청 수 제한에 걸리지 않게 띄엄띄엄)
end
local function rejected(kind, value, why)
	local before = s.rejected
	local snap = { set = table.clone(s.data.set), diff = s.data.diff, seenN = 0, best = table.clone(s.data.best) }
	for _ in s.data.seen do
		snap.seenN += 1
	end
	send(kind, value)
	local n = 0
	for _ in s.data.seen do
		n += 1
	end
	h.eq(s.rejected, before + 1, "버린다: " .. why)
	h.eq({ s.data.set, s.data.diff, n, s.data.best }, { snap.set, snap.diff, snap.seenN, snap.best }, "자료는 그대로: " .. why)
end
rejected("set", { music = 200, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 }, "음량 200")
rejected("set", { music = 50, sfx = 60 }, "빠진 칸")
rejected("set", { music = 50.5, sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 }, "정수가 아닌 값")
rejected("set", { music = "50", sfx = 60, fx = 1, shake = 0, hand = 1, bloom = 0 }, "문자열")
rejected("set", { music = 50, sfx = 60, fx = 3, shake = 0, hand = 1, bloom = 0 }, "이펙트 3")
rejected("set", "설정", "표가 아닌 설정")
rejected("seen", "bogus", "없는 안내 이름")
rejected("seen", 5, "수로 된 안내 이름")
rejected("diff", 4, "난이도 4")
rejected("diff", -1, "난이도 -1")
rejected("diff", 1.5, "난이도 1.5")
rejected("diff", "1", "문자열 난이도")
rejected("hack", 1, "모르는 갈래")
rejected(123, 1, "갈래가 문자열이 아니다")
rejected("run", { diff = 1, t = 20, kills = 10, level = 3, won = true, zone = 6 }, "20초 만에 도착")
rejected("run", { diff = 1, t = 30, kills = 10, level = 3, won = false, zone = 5 }, "30초 만에 에스컬레이터")
rejected("run", { diff = 1, t = 5, kills = 99999, level = 3, won = false, zone = 0 }, "5초에 99999명")
rejected("run", { diff = 1, t = 0 / 0, kills = 1, level = 1, won = false, zone = 0 }, "NaN")
rejected("run", { diff = 1, t = 5, kills = 1, level = 0, won = false, zone = 0 }, "레벨 0")
rejected("run", { diff = 1, t = 5, kills = 1, level = 1, won = "yes", zone = 0 }, "won이 불이 아니다")
rejected("run", { diff = 9, t = 5, kills = 1, level = 1, won = false, zone = 0 }, "난이도 9")
rejected("run", "기록", "표가 아닌 기록")
rejected("run", { diff = 1, t = 500, kills = 100, level = 20, won = true, zone = 6 }, "실제로 흐른 시간보다 긴 판(들어온 지 얼마 안 됐다)")

section("맞는 쓰기는 받는다 · 기록은 더 나을 때만")
h.advance(6)
send("set", { music = 10, sfx = 20, fx = 2, shake = 1, hand = 0, bloom = 1 })
h.eq(s.data.set, { music = 10, sfx = 20, fx = 2, shake = 1, hand = 0, bloom = 1 }, "설정")
send("seen", "dash")
h.eq(s.data.seen.dash, 1, "본 안내")
send("diff", 3)
h.eq(s.data.diff, 3, "난이도")
-- 판의 시간은 실제로 흐른 시간보다 길 수 없다: 방금 기록을 보냈으니 100초짜리 판은 아직 못 받는다 → 130초 뒤에는 받는다
local r0 = s.rejected
send("run", { diff = 2, t = 100, kills = 50, level = 5, won = false, zone = 2 })
h.eq(s.rejected, r0 + 1, "실제 시간이 모자라면 버린다")
h.advance(130)
r0 = s.rejected
send("run", { diff = 2, t = 100, kills = 50, level = 5, won = false, zone = 2 })
h.eq(s.rejected, r0, "130초 뒤: 버리지 않는다")
h.eq(s.data.best["2"].t, 120, "하지만 더 못한 기록이라 그대로(같은 장소 · 더 짧은 시간)")
Data.RUN_SLACK = 1e9 -- (아래는 「더 나은 기록」 규칙만 본다 — 시간 검사는 위에서 봤다)
send("run", { diff = 2, t = 125, kills = 50, level = 5, won = false, zone = 2 })
h.eq(s.data.best["2"].t, 125, "같은 장소에서 더 오래 버텼다 → 바뀐다")
send("run", { diff = 2, t = 115, kills = 70, level = 6, won = false, zone = 3 })
h.eq(s.data.best["2"].zone, 3, "더 먼 장소 → 바뀐다")
send("run", { diff = 0, t = 380, kills = 1500, level = 25, won = true, zone = 6 })
h.eq(s.data.best["0"].t, 380, "이긴 기록끼리는 더 빠른 것")
send("run", { diff = 0, t = 390, kills = 1500, level = 25, won = true, zone = 6 })
h.eq(s.data.best["0"].t, 380, "더 느린 도착은 남기지 않는다")
send("run", { diff = 0, t = 395, kills = 1500, level = 25, won = false, zone = 6 })
h.eq(s.data.best["0"].won, true, "진 판은 이긴 기록을 덮지 못한다")
Data.RUN_SLACK = 10
h.advance(8)
local saved = h.datastore.get(STORE, KEY)
h.eq(saved.set, { music = 10, sfx = 20, fx = 2, shake = 1, hand = 0, bloom = 1 }, "DataStore: 설정")
h.eq(saved.diff, 3, "DataStore: 난이도")
h.eq(saved.seen, { move = 1, xp = 1, dash = 1 }, "DataStore: 본 안내(합쳐진다)")
h.eq(saved.best["2"], { t = 115, kills = 70, level = 6, won = false, zone = 3 }, "DataStore: 혼잡 기록")
h.eq(saved.best["0"].t, 380, "DataStore: 여유 기록")
h.eq(saved.best["1"], nil, "DataStore: 틀렸던 기록은 지워졌다")
h.eq(saved.v, 1, "DataStore: 판 번호")

section("너무 잦은 요청")
h.advance(10)
local before, kept = s.rejected, s.data.diff
h.asClient(function()
	for i = 1, 100 do
		save:FireServer("diff", i % 4)
	end
end)
h.step(3)
h.expect(s.rejected - before >= 75, "한꺼번에 100번 → 대부분 버린다 (" .. (s.rejected - before) .. "개 버림)")
h.expect(s.rejected - before <= 82, "20개쯤은 받는다")
local _ = kept

section("저장 실패 → 다음에 다시")
h.advance(12)
send("seenReset", nil)
h.eq(next(s.data.seen), nil, "본 안내를 지웠다")
send("diff", 1)
local warns = #h.warnings()
h.datastore.failNext(2)
h.advance(8)
h.expect(#h.warnings() > warns, "저장에 실패하면 경고를 낸다")
h.eq(h.datastore.get(STORE, KEY).diff ~= 1, true, "실패한 동안은 DataStore가 그대로")
h.eq(s.dirty.diff, true, "쓸 것이 남아 있다")
send("seen", "esc")
h.advance(8)
saved = h.datastore.get(STORE, KEY)
h.eq(saved.diff, 1, "다음 저장에서 들어갔다")
h.eq(saved.seen, { esc = 1 }, "지운 뒤 새로 본 것만 남는다")

section("나갔다가 다시 들어온다")
send("set", { music = 5, sfx = 95, fx = 0, shake = 0, hand = 1, bloom = 0 })
h.fire(Players, "PlayerRemoving", player) -- 나감: 모아 둔 것을 바로 쓴다
h.advance(1)
h.eq(Data.sessions[player], nil, "서버가 접속 자료를 버렸다")
h.eq(h.datastore.get(STORE, KEY).set, { music = 5, sfx = 95, fx = 0, shake = 0, hand = 1, bloom = 0 }, "나갈 때 저장됐다")
h.fire(Players, "PlayerAdded", player) -- 다시 들어옴
local got
h.asClient(function()
	task.spawn(function()
		got = game.ReplicatedStorage.SsbNet.Load:InvokeServer()
	end)
end)
h.waitFor(function()
	return got ~= nil
end, 15, "Load의 답")
h.eq(got.ok, true, "다시 읽었다")
h.eq(got.set, { music = 5, sfx = 95, fx = 0, shake = 0, hand = 1, bloom = 0 }, "다시 들어와도 설정이 그대로")
h.eq(got.diff, 1, "난이도도")
h.eq(got.seen, { esc = 1 }, "본 안내도")
h.eq(got.best["2"].zone, 3, "기록도")
h.eq(Net.better({ t = 1, kills = 0, level = 1, won = true, zone = 6 }, { t = 999, kills = 0, level = 1, won = false, zone = 6 }), true, "better: 이긴 것이 진 것보다 낫다")

section("서버가 닫힐 때")
s = Data.sessions[player]
send("diff", 2)
h.shutdown()
h.eq(h.datastore.get(STORE, KEY).diff, 2, "닫힐 때 남은 것을 쓴다")

print("끝: server")
