-- (일부러 틀린 견본) 시작하자마자 나는 오류: 모듈 안의 속성 오타 → 역추적에 두 파일의 줄이 다 나와야 한다
local Players = game:GetService("Players")
local Util = require(script.Parent.Util)

local gui = Instance.new("ScreenGui")
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function build()
	local label = Instance.new("TextLabel")
	label.Parent = gui
	Util.style(label)
end

build()
print("여기까지 오면 안 된다")
