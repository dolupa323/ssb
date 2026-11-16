--!strict
-- 견본 클라이언트: 화면 틀 · 점 그림(EditableImage) · 한글 글씨 · 단추 · 글쇠로 움직이기 · 트윈 · 서버와 기록 주고받기.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.shared.Config)
local Pixels = require(ReplicatedStorage.shared.Pixels)
local Remotes = require(ReplicatedStorage.shared.Remotes)
local Stage = require(script.Parent.Stage)

local stage = Stage.init()
local view, ui = stage.view, stage.ui

-- ---------- 점 그림판 ----------
local art = Pixels.make()
local atlas = AssetService:CreateEditableImage({ Size = Vector2.new(art.w, art.h) })
atlas:WritePixelsBuffer(Vector2.zero, Vector2.new(art.w, art.h), art.buf)
local atlasContent = Content.fromObject(atlas)

-- 판에서 조각(index 0~3)을 잘라 놓는다. flip = 왼쪽을 보게(자르는 폭을 음수로)
local function sprite(parent: Instance, name: string, index: number, x: number, y: number, flip: boolean?, size: number?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ScaleType = Enum.ScaleType.Stretch
	label.Size = UDim2.fromOffset(size or 16, size or 16)
	label.Position = UDim2.fromOffset(x, y)
	label.ImageContent = atlasContent
	if flip then
		label.ImageRectOffset = Vector2.new(index * 16 + 16, 0)
		label.ImageRectSize = Vector2.new(-16, 16)
	else
		label.ImageRectOffset = Vector2.new(index * 16, 0)
		label.ImageRectSize = Vector2.new(16, 16)
	end
	label.Parent = parent
	return label
end

local world = Instance.new("Frame")
world.Name = "World"
world.Size = UDim2.fromScale(1, 1)
world.BackgroundTransparency = 1
world.Parent = view

sprite(world, "PersonRight", 0, 40, 60)
sprite(world, "PersonLeft", 0, 64, 60, true)
sprite(world, "ArrowRight", 1, 100, 60)
sprite(world, "ArrowLeft", 1, 124, 60, true)
sprite(world, "CoinBig", 2, 160, 52, false, 32)
sprite(world, "Checker", 3, 204, 60)
local tinted = sprite(world, "CoinTinted", 2, 228, 60)
tinted.ImageColor3 = Color3.fromRGB(120, 200, 255)

local hero = sprite(world, "Hero", 0, 184, 140)
hero.ZIndex = 5
local heroX, heroY = 184, 140

-- ---------- 화면 글씨 ----------
local function text(parent: Instance, name: string, str: string, x: number, y: number, w: number, h: number, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = Enum.Font.SourceSansBold
	t.TextSize = size
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = str
	t.Parent = parent
	return t
end

local title = text(ui, "Title", Config.TITLE, 0, 28, Stage.UI_W, 20, 18)
title.TextXAlignment = Enum.TextXAlignment.Center

local clock = text(ui, "Clock", "시각 08:00", 8, 52, 120, 14, 12)
local bestLabel = text(ui, "Best", "최고 기록: …", 8, 68, 160, 14, 12)
local counter = text(ui, "Counter", "누른 횟수: 0", 8, 84, 160, 14, 12)
local touchLabel = text(ui, "Touches", "손가락 0개", 8, 100, 160, 14, 12)

-- 오른쪽 차림표: UIListLayout
local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.AnchorPoint = Vector2.new(1, 0)
menu.Position = UDim2.new(1, -8, 0, 52)
menu.Size = UDim2.fromOffset(110, 96)
menu.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
menu.BackgroundTransparency = 0.2
menu.BorderSizePixel = 0
menu.Parent = ui
local menuPad = Instance.new("UIPadding")
menuPad.PaddingTop = UDim.new(0, 6)
menuPad.PaddingLeft = UDim.new(0, 6)
menuPad.PaddingRight = UDim.new(0, 6)
menuPad.Parent = menu
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 4)
list.Parent = menu
Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 6)

local function button(name: string, label: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 24)
	b.BackgroundColor3 = Color3.fromRGB(70, 110, 190)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.Parent = menu
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(200, 220, 255)
	stroke.Thickness = 1
	stroke.Parent = b
	return b
end
-- 만든 차례와 놓이는 차례가 다르다(LayoutOrder로 놓인다)
local settingsButton = button("Settings", "설정", 3)
local startButton = button("Start", "시작", 1)
local submitButton = button("Submit", "기록 내기", 2)

-- 아래 가방: UIGridLayout
local bag = Instance.new("Frame")
bag.Name = "Bag"
bag.AnchorPoint = Vector2.new(0.5, 1)
bag.Position = UDim2.new(0.5, 0, 1, -8)
bag.Size = UDim2.fromOffset(170, 58)
bag.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
bag.BackgroundTransparency = 0.3
bag.BorderSizePixel = 0
bag.Parent = ui
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(24, 24)
grid.CellPadding = UDim2.fromOffset(4, 4)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Center
grid.Parent = bag
for i = 1, 8 do
	local cell = Instance.new("Frame")
	cell.Name = "Cell" .. i
	cell.LayoutOrder = i
	cell.BackgroundColor3 = Color3.fromRGB(50, 58, 74)
	cell.BorderSizePixel = 0
	cell.Parent = bag
	if i <= 5 then
		local icon = sprite(cell, "Icon", if i % 2 == 1 then 2 else 1, 0, 0)
		icon.Size = UDim2.fromScale(1, 1)
	end
end

-- 잘리는 틀
local clip = Instance.new("Frame")
clip.Name = "Clip"
clip.Position = UDim2.fromOffset(8, 124)
clip.Size = UDim2.fromOffset(96, 30)
clip.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
clip.BorderSizePixel = 0
clip.ClipsDescendants = true
clip.Parent = ui
local clipped = text(clip, "Long", "잘리는 글 — 이 줄은 틀 밖으로 나간다", 4, 4, 300, 22, 14)
clipped.TextStrokeTransparency = 1

-- 트윈으로 차오르는 막대(UIGradient)
local barBack = Instance.new("Frame")
barBack.Name = "BarBack"
barBack.Position = UDim2.fromOffset(8, 164)
barBack.Size = UDim2.fromOffset(120, 10)
barBack.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
barBack.BorderSizePixel = 0
barBack.Parent = ui
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = Color3.new(1, 1, 1)
bar.BorderSizePixel = 0
bar.Parent = barBack
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(80, 220, 120), Color3.fromRGB(240, 220, 60))
grad.Parent = bar
local barTween = TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.8, 1) })
barTween:Play()

-- 돌린 딱지
local tag = text(ui, "Tag", "신상", 150, 120, 44, 18, 13)
tag.BackgroundTransparency = 0
tag.BackgroundColor3 = Color3.fromRGB(230, 80, 60)
tag.TextXAlignment = Enum.TextXAlignment.Center
tag.TextStrokeTransparency = 1
tag.Rotation = -15

-- 손가락 판(왼쪽 아래): 닿은 손가락을 센다
local pad = Instance.new("TextButton")
pad.Name = "Pad"
pad.AnchorPoint = Vector2.new(0, 1)
pad.Position = UDim2.new(0, 8, 1, -8)
pad.Size = UDim2.fromOffset(90, 60)
pad.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
pad.BackgroundTransparency = 0.8
pad.BorderSizePixel = 0
pad.Text = "손가락 판"
pad.TextSize = 11
pad.TextColor3 = Color3.new(1, 1, 1)
pad.AutoButtonColor = false
pad.Parent = ui

-- ---------- 동작 ----------
local clicks = 0
startButton.Activated:Connect(function()
	clicks += 1
	counter.Text = "누른 횟수: " .. clicks
end)
submitButton.MouseButton1Click:Connect(function()
	Remotes.submit:FireServer(clicks * 10)
end)
settingsButton.MouseButton1Click:Connect(function()
	menu.Visible = false -- 차림표를 닫는다
end)
Remotes.saved.OnClientEvent:Connect(function(best: number)
	bestLabel.Text = "최고 기록: " .. best
end)

local touches: { [InputObject]: boolean } = {}
local function countTouches(): number
	local n = 0
	for _ in touches do
		n += 1
	end
	return n
end
pad.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		touches[input] = true
		touchLabel.Text = "손가락 " .. countTouches() .. "개"
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if touches[input] then
		touches[input] = nil
		touchLabel.Text = "손가락 " .. countTouches() .. "개"
	end
end)

-- 글쇠로 주인공을 움직인다
local held: { [Enum.KeyCode]: boolean } = {}
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	held[input.KeyCode] = true
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	held[input.KeyCode] = nil
end)

local elapsed = 0
RunService.RenderStepped:Connect(function(dt: number)
	local dx, dy = 0, 0
	if held[Enum.KeyCode.D] or held[Enum.KeyCode.Right] then
		dx += 1
	end
	if held[Enum.KeyCode.A] or held[Enum.KeyCode.Left] then
		dx -= 1
	end
	if held[Enum.KeyCode.S] or held[Enum.KeyCode.Down] then
		dy += 1
	end
	if held[Enum.KeyCode.W] or held[Enum.KeyCode.Up] then
		dy -= 1
	end
	if dx ~= 0 or dy ~= 0 then
		heroX = math.clamp(heroX + dx * Config.SPEED * dt, 0, Config.VIEW_W - 16)
		heroY = math.clamp(heroY + dy * Config.SPEED * dt, 0, Config.VIEW_H - 16)
		hero.Position = UDim2.fromOffset(math.floor(heroX + 0.5), math.floor(heroY + 0.5))
		if dx < 0 then
			hero.ImageRectOffset = Vector2.new(16, 0)
			hero.ImageRectSize = Vector2.new(-16, 16)
		elseif dx > 0 then
			hero.ImageRectOffset = Vector2.new(0, 0)
			hero.ImageRectSize = Vector2.new(16, 16)
		end
	end
	elapsed += dt
	local minutes = math.floor(elapsed) -- 1초 = 게임 속 1분
	clock.Text = string.format("시각 %02d:%02d", 8 + minutes // 60, minutes % 60)
end)

-- 서버에 최고 기록을 묻는다
task.spawn(function()
	local best = Remotes.best:InvokeServer()
	bestLabel.Text = "최고 기록: " .. tostring(best)
	print("클라이언트: 최고 기록", best)
end)

print("클라이언트: 준비 끝", Players.LocalPlayer.Name, stage.scale, stage.uiScale)
