-- 자체 시험 2: 차례지기 · 가상 시계 · 신호 · 트윈 · 소리.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --script tools/mock/sample/scenarios/sched.luau
local h = harness
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

print("== task ==")
local log = {}
local t0 = h.time()
h.asClient(function()
	task.spawn(function()
		table.insert(log, "spawn")
		local dt = task.wait(0.5)
		table.insert(log, string.format("waited %.3f", dt))
	end)
	task.defer(function()
		table.insert(log, "defer")
	end)
	task.delay(1, function(a, b)
		table.insert(log, "delay " .. a .. b)
	end, "x", "y")
	table.insert(log, "main")
end)
h.eq(log, { "spawn", "main", "defer" }, "spawn은 바로 · defer는 지금 것이 끝난 뒤")
h.step(29)
h.eq(#log, 3, "0.483초: 아직 깨지 않았다")
h.step(1)
h.eq(log[4], "waited 0.500", "0.5초 뒤에 깬다")
h.step(29)
h.eq(#log, 4, "delay는 아직")
h.step(1)
h.eq(log[5], "delay xy", "task.delay(1) — 인자도 넘어온다")
h.near(h.time() - t0, 1, 1e-9, "가상 시각 1초")

-- task.wait()는 다음 장에 깬다 · task.cancel
local ticks = 0
local looper
h.asClient(function()
	looper = task.spawn(function()
		while true do
			task.wait()
			ticks += 1
		end
	end)
end)
h.step(5)
h.eq(ticks, 5, "task.wait() = 한 장")
task.cancel(looper)
h.step(5)
h.eq(ticks, 5, "task.cancel 뒤에는 돌지 않는다")

-- 시계
local c0, t1, o0 = os.clock(), tick(), os.time()
h.step(60)
h.near(os.clock() - c0, 1, 0.001, "os.clock은 가상 시계")
h.near(tick() - t1, 1, 1e-6, "tick도")
h.eq(os.time() - o0, 1, "os.time도")
h.near(time(), h.time(), 1e-9, "time()")
h.eq(os.date("!%Y-%m-%d", 0), "1970-01-01", "os.date")

-- 옛 wait · delay · spawn
local legacy = {}
h.asClient(function()
	spawn(function()
		table.insert(legacy, "spawn")
	end)
	delay(0.1, function()
		table.insert(legacy, "delay")
	end)
	local dt = wait(0.2)
	table.insert(legacy, string.format("wait %.2f", dt))
end)
h.step(13)
h.eq(legacy, { "spawn", "delay", "wait 0.20" }, "wait · delay · spawn")

print("== 신호 ==")
local ev = Instance.new("BindableEvent")
local got = {}
local conn = ev.Event:Connect(function(a)
	table.insert(got, "A" .. a)
end)
ev.Event:Once(function(a)
	table.insert(got, "once" .. a)
end)
ev:Fire(1)
ev:Fire(2)
h.eq(got, { "A1", "once1", "A2" }, "Connect · Once")
conn:Disconnect()
h.eq(conn.Connected, false, "Disconnect → Connected = false")
ev:Fire(3)
h.eq(#got, 3, "끊은 뒤에는 오지 않는다")
-- Wait
local waited
h.asClient(function()
	waited = ev.Event:Wait()
end)
ev:Fire("값")
h.eq(waited, "값", "신호:Wait()")
-- 미뤄 부르기(기본): 신호를 낸 스레드가 멈춘 뒤에 받는 쪽이 돈다
local order = {}
ev.Event:Connect(function()
	table.insert(order, "handler")
end)
h.asClient(function()
	ev:Fire()
	table.insert(order, "after fire")
end)
h.eq(order, { "after fire", "handler" }, "신호는 미뤄서 부른다(Deferred)")
-- 표는 베껴서 간다
local sent = { n = 1 }
local received
ev.Event:Once(function(tb)
	received = tb
end)
ev:Fire(sent)
h.eq(received ~= sent and received.n == 1, true, "BindableEvent: 표는 베낀 것이 간다")
-- BindableFunction
local bf = Instance.new("BindableFunction")
bf.OnInvoke = function(a, b)
	return a + b, "ok"
end
h.eq({ bf:Invoke(2, 3) }, { 5, "ok" }, "BindableFunction")

-- RunService: 차례와 dt
local frames = {}
local c1 = RunService.RenderStepped:Connect(function(dt)
	table.insert(frames, "render")
	h.near(dt, 1 / 60, 1e-9, "RenderStepped의 dt")
end)
local c2 = RunService.Heartbeat:Connect(function()
	table.insert(frames, "heartbeat")
end)
local c3 = RunService.Stepped:Connect(function(now, dt)
	table.insert(frames, "stepped")
end)
h.asClient(function()
	RunService:BindToRenderStep("first", Enum.RenderPriority.First.Value, function()
		table.insert(frames, "bind")
	end)
end)
h.step(1)
h.eq(frames, { "bind", "render", "stepped", "heartbeat" }, "한 장 안의 차례")
c1:Disconnect()
c2:Disconnect()
c3:Disconnect()
RunService:UnbindFromRenderStep("first")
h.expectError(function()
	h.asServer(function()
		RunService.RenderStepped:Connect(function() end)
	end)
	error(h.takeErrors()[1].message, 0)
end, "can only be used from local scripts", "서버에서 RenderStepped")
h.eq(h.asServer(function()
	return RunService:IsServer(), RunService:IsClient()
end), true, "서버 문맥: IsServer")
h.eq(h.asClient(function()
	return RunService:IsClient()
end), true, "클라이언트 문맥: IsClient")

print("== 트윈 ==")
local frame = Instance.new("Frame")
frame.Parent = h.playerGui():FindFirstChild("Sample")
local tw = TweenService:Create(frame, TweenInfo.new(1, Enum.EasingStyle.Linear), { Position = UDim2.fromOffset(100, 50), BackgroundTransparency = 1 })
local done
tw.Completed:Connect(function(state)
	done = state
end)
h.eq(tw.PlaybackState, Enum.PlaybackState.Begin, "처음 상태")
tw:Play()
h.eq(tw.PlaybackState, Enum.PlaybackState.Playing, "Play 뒤")
h.step(30)
h.near(frame.Position.X.Offset, 50, 0.01, "반쯤(선형)")
h.near(frame.BackgroundTransparency, 0.5, 0.001, "수 속성도")
h.eq(done, nil, "아직 끝나지 않았다")
h.step(30)
h.eq(frame.Position, UDim2.fromOffset(100, 50), "끝 값에 닿는다")
h.eq(done, Enum.PlaybackState.Completed, "Completed 이벤트")
-- 모든 완급에서 끝 값에 닿는가
for _, style in Enum.EasingStyle:GetEnumItems() do
	for _, dir in Enum.EasingDirection:GetEnumItems() do
		local fr = Instance.new("Frame")
		local tween = TweenService:Create(fr, TweenInfo.new(0.2, style, dir), { Size = UDim2.fromOffset(40, 40) })
		tween:Play()
		h.step(13)
		if fr.Size ~= UDim2.fromOffset(40, 40) then
			h.fail("완급 " .. style.Name .. "/" .. dir.Name .. " 이 끝 값에 닿지 않았다: " .. tostring(fr.Size))
		end
	end
end
h.near(TweenService:GetValue(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 0.75, 1e-9, "GetValue(Quad, Out)")
-- 멈추기 · 미루기 · 되돌기
local fr2 = Instance.new("Frame")
local tw2 = TweenService:Create(fr2, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true, 0.5), { Rotation = 90 })
local state2
tw2.Completed:Connect(function(s)
	state2 = s
end)
tw2:Play()
h.eq(tw2.PlaybackState, Enum.PlaybackState.Delayed, "DelayTime 동안은 Delayed")
h.step(30)
h.eq(fr2.Rotation, 0, "미루는 동안 그대로")
h.step(60)
h.near(fr2.Rotation, 90, 0.01, "갔다가")
h.step(30)
h.near(fr2.Rotation, 45, 0.01, "돌아오는 중(Reverses)")
tw2:Cancel()
h.eq(state2, Enum.PlaybackState.Cancelled, "Cancel → Completed(Cancelled)")
h.step(10)
h.near(fr2.Rotation, 45, 0.01, "Cancel 뒤에는 멈춘다")
-- 옛 메서드
local fr3 = Instance.new("Frame")
local cb
fr3:TweenPosition(UDim2.fromOffset(10, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.1, true, function(status)
	cb = status
end)
h.step(7)
h.eq({ fr3.Position, cb }, { UDim2.fromOffset(10, 0), Enum.TweenStatus.Completed }, "GuiObject:TweenPosition")

print("== 소리 ==")
local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://1234"
sound.Parent = game:GetService("SoundService")
local ended = false
sound.Ended:Connect(function()
	ended = true
end)
sound:Play()
h.eq(sound.IsPlaying, true, "Play → IsPlaying")
h.step(30)
h.near(sound.TimePosition, 0.5, 0.001, "TimePosition이 흐른다")
h.step(31)
h.eq({ ended, sound.IsPlaying }, { true, false }, "길이(mock: 1초)가 지나면 Ended")
h.eq(h.sounds()[1].id, "rbxassetid://1234", "튼 소리의 기록")

print("== WaitForChild ==")
local folder = Instance.new("Folder")
local found
h.asClient(function()
	found = folder:WaitForChild("Late")
end)
h.step(3)
h.eq(found, nil, "아직 없다")
local late = Instance.new("Frame")
late.Name = "Late"
late.Parent = folder
h.eq(found, late, "생기면 깨어난다")
local timedOut = "?"
h.asClient(function()
	timedOut = folder:WaitForChild("Never", 0.5)
end)
h.step(31)
h.eq(timedOut, nil, "시간이 다 되면 nil")
h.asClient(function()
	folder:WaitForChild("Forever")
end)
h.step(301)
local w = h.warnings()
h.eq(string.find(w[#w].text, "Infinite yield possible", 1, true) ~= nil, true, "5초가 지나면 Infinite yield 경고")

print("끝: sched")
