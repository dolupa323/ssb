-- 자체 시험 6: 화면 그림이 받는 것들을 한 장에 늘어놓는다(눈으로 본다) — 글 맞춤 · 줄 바꿈 · 꾸밈 글 · 모서리 · 테두리 · 색 번짐 ·
--  돌리기 · 그림의 ScaleType(Stretch · Fit · Crop · Tile · Slice) · 뒤집기 · 색 입히기 · 짝 없는 에셋(자리 표시).
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --script tools/mock/sample/scenarios/gallery.luau --assets tools/mock/sample/assets.json --shot-dir tools/mock/sample/shots
local h = harness
local pg = h.playerGui()
pg.Sample.Enabled = false

local gui = Instance.new("ScreenGui")
gui.Name = "Gallery"
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
back.BorderSizePixel = 0
back.Parent = gui

local function label(text, x, y, w, hh)
	local t = Instance.new("TextLabel")
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, hh)
	t.BackgroundColor3 = Color3.fromRGB(60, 66, 80)
	t.BorderSizePixel = 0
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.SourceSans
	t.TextSize = 16
	t.Text = text
	t.Parent = back
	return t
end
local function caption(text, x, y)
	local t = label(text, x, y, 300, 14)
	t.BackgroundTransparency = 1
	t.TextSize = 11
	t.TextColor3 = Color3.fromRGB(170, 180, 200)
	t.TextXAlignment = Enum.TextXAlignment.Left
	return t
end

-- 1줄: 글 맞춤 아홉 가지
caption("글 맞춤(왼 · 가운데 · 오른 x 위 · 가운데 · 아래)", 20, 70)
local xs = { Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right }
local ys = { Enum.TextYAlignment.Top, Enum.TextYAlignment.Center, Enum.TextYAlignment.Bottom }
for i, xa in xs do
	for j, ya in ys do
		local t = label("가나 Ab", 20 + (i - 1) * 104, 88 + (j - 1) * 44, 100, 40)
		t.TextXAlignment = xa
		t.TextYAlignment = ya
	end
end

-- 줄 바꿈 · 크기 맞춤 · 꾸밈 글 · 글 테두리
caption("줄 바꿈 · TextScaled · RichText · 글 테두리", 350, 70)
local wrapped = label("줄을 바꾸는 긴 글입니다. 틀의 폭에 맞춰 여러 줄로 나뉩니다.", 350, 88, 150, 84)
wrapped.TextWrapped = true
wrapped.TextXAlignment = Enum.TextXAlignment.Left
wrapped.TextYAlignment = Enum.TextYAlignment.Top
local scaled = label("크기 맞춤", 510, 88, 150, 40)
scaled.TextScaled = true
local rich = label('<b>굵게</b> <i>기울임</i> <font color="#ff5050">빨강</font> <font size="24">큰</font>', 510, 132, 220, 40)
rich.RichText = true
local stroked = label("글 테두리", 670, 88, 120, 40)
stroked.TextSize = 22
stroked.TextStrokeTransparency = 0
stroked.TextStrokeColor3 = Color3.fromRGB(20, 20, 120)
local uiStroked = label("UIStroke", 800, 88, 120, 40)
uiStroked.TextSize = 22
uiStroked.BackgroundTransparency = 1
local us = Instance.new("UIStroke")
us.Thickness = 2
us.Color = Color3.fromRGB(200, 40, 40)
us.Parent = uiStroked
local bold = label("굵은 고딕 Bold", 740, 132, 180, 40)
bold.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

-- 2줄: 틀의 모양
caption("모서리 · 테두리(UIStroke) · 옛 테두리(BorderSizePixel) · 색 번짐 · 돌리기 · 반투명", 20, 232)
local function box(x, y, w, hh, color)
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, hh)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = back
	return f
end
local round = box(20, 252, 100, 60, Color3.fromRGB(80, 160, 240))
Instance.new("UICorner", round).CornerRadius = UDim.new(0, 16)
local pill = box(130, 252, 100, 60, Color3.fromRGB(240, 160, 80))
Instance.new("UICorner", pill).CornerRadius = UDim.new(0.5, 0)
local strokeBox = box(244, 256, 92, 52, Color3.fromRGB(50, 56, 70))
Instance.new("UICorner", strokeBox).CornerRadius = UDim.new(0, 8)
local sb = Instance.new("UIStroke")
sb.Thickness = 4
sb.Color = Color3.fromRGB(120, 230, 140)
sb.Parent = strokeBox
local old = box(356, 256, 92, 52, Color3.fromRGB(200, 200, 210))
old.BorderSizePixel = 4
old.BorderColor3 = Color3.fromRGB(200, 60, 60)
local gradBox = box(464, 252, 120, 60, Color3.new(1, 1, 1))
local g = Instance.new("UIGradient")
g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 120, 255)) })
g.Parent = gradBox
local gradV = box(596, 252, 60, 60, Color3.new(1, 1, 1))
local g2 = Instance.new("UIGradient")
g2.Rotation = 90
g2.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 30, 30))
g2.Transparency = NumberSequence.new(0, 0.8)
g2.Parent = gradV
local rotated = box(690, 256, 80, 50, Color3.fromRGB(150, 90, 220))
rotated.Rotation = 20
local inner = box(0, 0, 30, 20, Color3.fromRGB(255, 255, 120))
inner.Parent = rotated -- 부모와 같이 돈다
local half = box(800, 252, 100, 60, Color3.fromRGB(255, 255, 255))
half.BackgroundTransparency = 0.6

-- 3줄: 그림
caption("그림: 짝 지은 PNG(Stretch · Fit · Crop · Tile · Slice) · 자르기 · 뒤집기 · 색 입히기 · 짝 없는 에셋", 20, 340)
local function image(id, x, y, w, hh)
	local im = Instance.new("ImageLabel")
	im.Position = UDim2.fromOffset(x, y)
	im.Size = UDim2.fromOffset(w, hh)
	im.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	im.BorderSizePixel = 0
	im.ResampleMode = Enum.ResamplerMode.Pixelated
	im.Image = id
	im.Parent = back
	return im
end
image("rbxassetid://9003", 20, 360, 120, 80) -- Stretch(기본)
local fit = image("rbxassetid://9003", 150, 360, 120, 80)
fit.ScaleType = Enum.ScaleType.Fit
local crop = image("rbxassetid://9003", 280, 360, 120, 80)
crop.ScaleType = Enum.ScaleType.Crop
local tile = image("rbxassetid://9002", 410, 360, 120, 80)
tile.ScaleType = Enum.ScaleType.Tile
tile.TileSize = UDim2.fromOffset(32, 32)
local slice = image("rbxassetid://9001", 540, 360, 160, 80)
slice.ScaleType = Enum.ScaleType.Slice
slice.SliceCenter = Rect.new(8, 8, 16, 16)
slice.BackgroundTransparency = 1
local cut = image("rbxassetid://9003", 720, 360, 80, 80) -- 가운데 초록 칸만
cut.ImageRectOffset = Vector2.new(16, 0)
cut.ImageRectSize = Vector2.new(16, 16)
local flipped = image("rbxassetid://9003", 810, 360, 120, 40) -- 좌우로 뒤집기: 파랑이 왼쪽 · 흰 점이 오른쪽 위
flipped.ImageRectOffset = Vector2.new(48, 0)
flipped.ImageRectSize = Vector2.new(-48, 16)
local tinted = image("rbxassetid://9003", 810, 404, 120, 36)
tinted.ImageColor3 = Color3.fromRGB(255, 255, 0) -- 파랑 칸이 검어진다
local faded = image("rbxassetid://9003", 940, 360, 120, 80)
faded.ImageTransparency = 0.6
local smooth = image("rbxassetid://9003", 1070, 360, 120, 80)
smooth.ResampleMode = Enum.ResamplerMode.Default
image("rbxassetid://123456789", 20, 460, 160, 60) -- 짝 없는 에셋
local part = image("rbxasset://textures/ui/GuiImagePlaceholder.png", 190, 460, 100, 60)
part.ImageRectOffset = Vector2.new(8, 8)
part.ImageRectSize = Vector2.new(32, 32)

-- 4줄: 자르기 · 겹치기
caption("자르기(ClipsDescendants) · 겹치는 차례(ZIndex) · 글 칸 · 굴리는 틀", 20, 540)
local clip = box(20, 560, 120, 60, Color3.fromRGB(70, 90, 70))
clip.ClipsDescendants = true
local big = box(60, 20, 120, 80, Color3.fromRGB(230, 120, 120))
big.Parent = clip
local z1 = box(160, 560, 70, 50, Color3.fromRGB(220, 80, 80))
local z2 = box(190, 575, 70, 50, Color3.fromRGB(80, 220, 80))
local z3 = box(220, 590, 70, 50, Color3.fromRGB(80, 80, 220))
z1.ZIndex = 3 -- 빨강이 맨 위
z2.ZIndex = 2
z3.ZIndex = 1
local tb = Instance.new("TextBox")
tb.Position = UDim2.fromOffset(310, 560)
tb.Size = UDim2.fromOffset(200, 32)
tb.Text = ""
tb.PlaceholderText = "이름을 적으세요"
tb.TextSize = 16
tb.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
tb.Parent = back
local sf = Instance.new("ScrollingFrame")
sf.Position = UDim2.fromOffset(530, 560)
sf.Size = UDim2.fromOffset(160, 80)
sf.CanvasSize = UDim2.fromOffset(0, 300)
sf.CanvasPosition = Vector2.new(0, 30)
sf.BackgroundColor3 = Color3.fromRGB(50, 56, 70)
sf.BorderSizePixel = 0
sf.Parent = back
for i = 1, 8 do
	local row = label("줄 " .. i, 4, (i - 1) * 34 + 4, 140, 30)
	row.Parent = sf
end

h.step(1)
-- 수로도 본다
h.eq(scaled.TextBounds.Y <= 40 and scaled.TextBounds.Y >= 30, true, "TextScaled: 틀의 높이에 가깝게")
h.eq(wrapped.TextBounds.Y > 16, true, "줄 바꿈: 두 줄이 넘는다")
h.eq(inner.AbsoluteRotation, 20, "돌린 틀의 아이")
local W, H = h.viewport()
h.shot(string.format("gallery-%dx%d.png", W, H))
print("끝: gallery")
