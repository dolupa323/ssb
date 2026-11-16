-- (일부러 틀린 견본) 돌다가 나는 오류 · 경고
local RunService = game:GetService("RunService")

warn("일부러 낸 경고", 123)

local frames = 0
local conn
conn = RunService.RenderStepped:Connect(function(dt)
	frames += 1
	if frames == 3 then
		conn:Disconnect()
		local frame = Instance.new("Frame");
		(frame :: any).Size = Vector2.new(10, 10) -- 틀린 형: UDim2가 와야 한다
	end
end)

task.spawn(function()
	task.wait(0.1)
	local t = nil :: any
	print(t.x) -- nil을 읽는다
end)
