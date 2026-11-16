-- 자체 시험 4: 클라이언트 ⇄ 서버(원격 이벤트 · 함수) · 기억 속 DataStore · 실패 넣기 · 문맥(서버/클라이언트) 검사.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --no-start --script tools/mock/sample/scenarios/net.luau
local h = harness
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("== 미리 넣은 기록으로 시작 ==")
h.datastore.set("MockSampleBest", "u1001", { best = 70, at = 0 })
h.start()
h.step(30)
local best = h.get("PlayerGui.Sample.Holder.Ui.Best")
local counter = h.get("PlayerGui.Sample.Holder.Ui.Counter")
h.eq(best.Text, "최고 기록: 70", "서버가 DataStore에서 읽은 기록이 클라이언트 화면에 뜬다")

print("== 단추 → 원격 이벤트 → DataStore → 원격 이벤트 → 화면 ==")
local startButton = h.findByText("시작", true)
local submitButton = h.findByText("기록 내기", true)
for _ = 1, 3 do
	h.clickOn(startButton)
end
h.eq(counter.Text, "누른 횟수: 3", "단추를 세 번")
h.clickOn(submitButton)
h.step(30)
h.eq(h.datastore.get("MockSampleBest", "u1001").best, 70, "30점은 최고 기록(70)을 넘지 못한다")
h.eq(best.Text, "최고 기록: 70", "화면도 그대로")
for _ = 1, 5 do
	h.clickOn(startButton)
end
h.clickOn(submitButton)
h.eq(best.Text, "최고 기록: 70", "보낸 바로 그 순간에는 아직(서버에 다녀와야 한다)")
h.step(30)
h.eq(h.datastore.get("MockSampleBest", "u1001").best, 80, "80점이 저장된다")
h.eq(best.Text, "최고 기록: 80", "서버가 알려 주면 화면이 바뀐다")
local calls = h.datastore.calls()
h.eq(calls[1].op, "GetAsync", "DataStore 부른 기록: 처음은 읽기")
h.eq(calls[#calls].op, "UpdateAsync", "마지막은 UpdateAsync")

print("== DataStore 실패 넣기 ==")
h.datastore.failNext(1)
h.clickOn(startButton)
h.clickOn(submitButton)
h.step(30)
local warns = h.warnings()
h.eq(#warns > 0 and string.find(warns[#warns].text, "기록을 저장하지 못했다", 1, true) ~= nil, true, "서버가 pcall로 잡아 경고를 낸다")
h.eq(h.datastore.get("MockSampleBest", "u1001").best, 80, "실패하면 저장되지 않는다")
h.eq(best.Text, "최고 기록: 80", "화면도 그대로")
h.clickOn(submitButton)
h.step(30)
h.eq(best.Text, "최고 기록: 90", "다음 것은 된다")

print("== 원격 이벤트: 값은 베껴서, 한 장 뒤에 ==")
local ev = Instance.new("RemoteEvent")
ev.Name = "Test"
ev.Parent = ReplicatedStorage
local got
h.asServer(function()
	ev.OnServerEvent:Connect(function(player, data, fn)
		got = { player = player, data = data, fn = fn, hasFn = fn ~= nil }
	end)
end)
local sent = { list = { 1, 2, 3 }, name = "가", pos = Vector2.new(1, 2) }
h.asClient(function()
	ev:FireServer(sent, function() end)
end)
h.eq(got, nil, "보낸 장에는 아직 닿지 않는다")
h.step(1)
h.eq(got.player, h.player(), "서버는 보낸 플레이어를 첫 인자로 받는다")
h.eq(got.data, sent, "값은 같다")
h.eq(got.data ~= sent, true, "하지만 베낀 표다(같은 표가 아니다)")
h.eq(got.hasFn, false, "함수는 건너가지 못한다(nil)")
local gotC
h.asClient(function()
	ev.OnClientEvent:Connect(function(a, b)
		gotC = { a, b }
	end)
end)
h.asServer(function()
	ev:FireAllClients("모두", 7)
end)
h.step(1)
h.eq(gotC, { "모두", 7 }, "서버 → 클라이언트")
-- 아직 건 것이 없을 때 온 것은 쌓였다가 처음 걸 때 온다
local ev2 = Instance.new("RemoteEvent")
ev2.Parent = ReplicatedStorage
h.asServer(function()
	ev2:FireClient(h.player(), 1)
	ev2:FireClient(h.player(), 2)
end)
h.step(2)
local queued = {}
h.asClient(function()
	ev2.OnClientEvent:Connect(function(n)
		table.insert(queued, n)
	end)
end)
h.step(2)
h.eq(queued, { 1, 2 }, "쌓인 것이 차례대로 온다")

print("== 원격 함수 ==")
local fn = Instance.new("RemoteFunction")
fn.Parent = ReplicatedStorage
h.asServer(function()
	fn.OnServerInvoke = function(player, a, b)
		if a == "boom" then
			error("서버에서 터짐")
		end
		task.wait(0.1) -- 서버가 기다렸다가 답한다
		return a + b, player.Name
	end
end)
local answer
h.asClient(function()
	answer = { fn:InvokeServer(2, 3) }
end)
h.eq(answer, nil, "답은 바로 오지 않는다")
h.step(12)
h.eq(answer, { 5, "Player1" }, "서버의 답")
local ok, err
h.asClient(function()
	ok, err = pcall(function()
		return fn:InvokeServer("boom")
	end)
end)
h.step(5)
h.eq(ok, false, "서버가 오류를 내면 부른 쪽도 오류")
h.eq(#h.takeErrors(), 1, "서버 쪽 오류는 따로 적힌다(여기서는 알고 낸 것이라 거둔다)")
print("  부른 쪽이 받은 오류:", err)

print("== 문맥 검사 ==")
local function errorOf(side, f)
	local good, e = h.pcallAs(side, f)
	return if good == false then tostring(e) else "(오류 없음)"
end
local function has(text, part)
	return string.find(text, part, 1, true) ~= nil
end
h.eq(has(errorOf("server", function()
	ev:FireServer(1)
end), "클라이언트(LocalScript)에서만"), true, "서버에서 FireServer")
h.eq(has(errorOf("client", function()
	ev:FireClient(h.player(), 1)
end), "서버에서만"), true, "클라이언트에서 FireClient")
h.eq(has(errorOf("client", function()
	ev.OnServerEvent:Connect(function() end)
end), "OnServerEvent can only be used on the server"), true, "클라이언트에서 OnServerEvent")
h.eq(has(errorOf("server", function()
	ev.OnClientEvent:Connect(function() end)
end), "OnClientEvent can only be used on the client"), true, "서버에서 OnClientEvent")
h.eq(has(errorOf("client", function()
	game:GetService("DataStoreService"):GetDataStore("x")
end), "서버에서만"), true, "클라이언트에서 DataStore")
h.eq(has(errorOf("server", function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end), "클라이언트(LocalScript)에서만"), true, "서버에서 SetCoreGuiEnabled")
h.eq(has(errorOf("client", function()
	fn.OnServerInvoke = function() end
end), "OnServerInvoke can only be set on the server"), true, "클라이언트에서 OnServerInvoke")
h.eq(select(2, h.pcallAs("server", function()
	return Players.LocalPlayer
end)), nil, "서버에서 LocalPlayer는 nil")
h.eq(select(2, h.pcallAs("client", function()
	return Players.LocalPlayer
end)), h.player(), "클라이언트에서 LocalPlayer")
-- 모듈은 쪽마다 따로 읽는다
local Config = ReplicatedStorage.shared.Config
local cfgServer, cfgClient = h.require(Config, "server"), h.require(Config, "client")
h.eq(cfgServer ~= cfgClient and cfgServer.STORE == cfgClient.STORE, true, "require: 서버와 클라이언트가 따로 가진다")

print("== DataStore에 넣을 수 없는 값 ==")
local function dsError(value)
	local good, e
	h.asServer(function()
		good, e = pcall(function()
			game:GetService("DataStoreService"):GetDataStore("T"):SetAsync("k", value)
		end)
	end)
	h.step(10)
	return if good == false then tostring(e) else "(오류 없음)"
end
h.eq(has(dsError({ f = function() end }), "function"), true, "함수")
h.eq(has(dsError({ 1, 2, x = 3 }), "섞인 표"), true, "배열과 사전이 섞인 표")
h.eq(has(dsError({ [1] = "a", [3] = "c" }), "열쇠"), true, "듬성듬성한 수 열쇠")
h.eq(has(dsError({ v = Vector2.new(1, 2) }), "Vector2"), true, "Roblox 자료형")
h.eq(has(dsError(0 / 0), "NaN"), true, "NaN")
h.eq(dsError({ name = "가", list = { 1, 2 }, deep = { ok = true } }), "(오류 없음)", "넣을 수 있는 값")
h.eq(h.datastore.get("T", "k"), { name = "가", list = { 1, 2 }, deep = { ok = true } }, "넣은 값")

print("== 나가기 ==")
local removing
h.asServer(function()
	Players.PlayerRemoving:Connect(function(p)
		removing = p.Name
	end)
end)
h.shutdown()
h.eq(removing, "Player1", "PlayerRemoving")
h.eq(#Players:GetPlayers(), 0, "플레이어가 없다")

print("끝: net")
