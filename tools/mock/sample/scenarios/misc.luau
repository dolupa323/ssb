-- 자체 시험 7: 그 밖의 서비스 — ContextActionService · 기기 갈래 · OrderedDataStore · CollectionService · ContentProvider · Debris · StarterGui.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --touch --script tools/mock/sample/scenarios/misc.luau
local h = harness
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

print("== 기기 갈래(--touch) ==")
h.eq({ UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, UIS.PreferredInput }, { true, false, false, Enum.PreferredInput.Touch }, "--touch로 시작한 기기")
h.setDevice({ touch = false, keyboard = true, mouse = true, preferred = "KeyboardAndMouse" })
h.eq({ UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.PreferredInput }, { false, true, Enum.PreferredInput.KeyboardAndMouse }, "harness.setDevice")
local lastType
UIS.LastInputTypeChanged:Connect(function(t)
	lastType = t
end)
h.keyTap(Enum.KeyCode.Q)
h.eq({ lastType, UIS:GetLastInputType() }, { Enum.UserInputType.Keyboard, Enum.UserInputType.Keyboard }, "LastInputTypeChanged")

print("== ContextActionService ==")
local calls = {}
h.asClient(function()
	CAS:BindAction("Jump", function(name, state, input)
		table.insert(calls, name .. " " .. state.Name .. " " .. input.KeyCode.Name)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end)
local seenByUIS = {}
local conn = UIS.InputBegan:Connect(function(input, processed)
	table.insert(seenByUIS, input.KeyCode.Name .. (if processed then " processed" else ""))
end)
h.keyTap(Enum.KeyCode.Space)
h.keyTap(Enum.KeyCode.E)
h.eq(calls, { "Jump Begin Space", "Jump End Space" }, "묶은 글쇠만 불린다")
h.eq(seenByUIS, { "Space processed", "E" }, "삼킨(Sink) 입력은 UserInputService에 processed = true로 간다")
conn:Disconnect()
h.asClient(function()
	CAS:UnbindAction("Jump")
end)
h.eq(calls[3], "Jump Cancel " .. Enum.KeyCode.Unknown.Name, "풀 때 Cancel로 한 번 불린다")
h.eq(Enum.KeyCode.Unknown, Enum.KeyCode.None, "옛 이름(Unknown)도 같은 값을 가리킨다(API 덤프의 LegacyNames)")
h.expectError(function()
	CAS:BindAction("Bad", function() end, false, "Space" :: any)
end, "Enum.KeyCode나 Enum.UserInputType", "BindAction에 문자열")

print("== Heartbeat:Wait() ==")
local waited
h.asClient(function()
	waited = RunService.Heartbeat:Wait()
end)
h.step(1)
h.near(waited, 1 / 60, 1e-9, "Wait()가 dt를 돌려준다")

print("== OrderedDataStore ==")
local page
h.asServer(function()
	local ods = game:GetService("DataStoreService"):GetOrderedDataStore("Rank")
	ods:SetAsync("a", 30)
	ods:SetAsync("b", 90)
	ods:SetAsync("c", 60)
	local pages = ods:GetSortedAsync(false, 2)
	page = pages:GetCurrentPage()
end)
h.step(40)
h.eq(page, { { key = "b", value = 90 }, { key = "c", value = 60 } }, "큰 것부터 둘")

print("== CollectionService · Debris · ContentProvider ==")
local CS = game:GetService("CollectionService")
local part = Instance.new("Folder")
part.Parent = workspace
local added
CS:GetInstanceAddedSignal("Mob"):Connect(function(inst)
	added = inst
end)
part:AddTag("Mob")
h.eq({ added, CS:GetTagged("Mob")[1], part:HasTag("Mob") }, { part, part, true }, "꼬리표")
game:GetService("Debris"):AddItem(part, 0.5)
h.step(31)
h.eq(part.Parent, nil, "Debris가 0.5초 뒤에 없앤다")
local loaded = {}
h.asClient(function()
	game:GetService("ContentProvider"):PreloadAsync({ "rbxassetid://1", "rbxassetid://2" }, function(id, status)
		table.insert(loaded, id .. " " .. status.Name)
	end)
end)
h.step(2)
h.eq(loaded, { "rbxassetid://1 Success", "rbxassetid://2 Success" }, "PreloadAsync")

print("== StarterGui ==")
h.asClient(function()
	local sg = game:GetService("StarterGui")
	sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	sg:SetCore("SendNotification", { Title = "알림", Text = "글" })
end)
h.eq(game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.Chat), false, "SetCoreGuiEnabled(All)")
h.eq(h.coreCalls()[1].name, "SendNotification", "SetCore 부른 기록")

print("== 흉내 내지 않는 메서드 ==")
local result = game:GetService("MarketplaceService"):GetProductInfo(1)
h.eq(result, nil, "nil을 돌려주고 「흉내 내지 않는다」 목록에 적는다")
h.eq(h.notes()["method:MarketplaceService.GetProductInfo"] ~= nil, true, "목록에 있다")

print("끝: misc")
