-- 자체 시험 3: 화면 자리 셈(UIScale 겹치기 · 기준점 · 줄/격자 배치 · 자르기 · 겹치는 차례) · 누른 자리 찾기 · 글 칸.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --script tools/mock/sample/scenarios/layout.luau
--  (화면 1280x720 · 위쪽 띠 58 기준의 수로 적혀 있다)
local h = harness
local pg = h.playerGui()
pg.Sample.Enabled = false -- 견본 게임의 화면은 꺼 둔다

local function frame(parent, name, x, y, w, hh)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, hh)
	f.Parent = parent
	return f
end
local function button(parent, name, x, y, w, hh)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = name
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, hh)
	b.Parent = parent
	return b
end

print("== 화면 틀과 위쪽 띠 ==")
local gui = Instance.new("ScreenGui")
gui.Name = "T"
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = pg
h.eq(gui.AbsoluteSize, Vector2.new(1280, 720), "IgnoreGuiInset: 화면 전체")
h.eq(gui.AbsolutePosition, Vector2.new(0, -58), "IgnoreGuiInset: AbsolutePosition.Y = -띠")
local gui2 = Instance.new("ScreenGui")
gui2.Name = "Inset"
gui2.Parent = pg
h.eq(gui2.AbsoluteSize, Vector2.new(1280, 662), "띠를 뺀 크기")
h.eq(gui2.AbsolutePosition, Vector2.new(0, 0), "띠 아래가 (0, 0)")
h.eq(gui2.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets, "ScreenInsets의 기본")
h.eq(gui.ScreenInsets, Enum.ScreenInsets.DeviceSafeInsets, "IgnoreGuiInset → ScreenInsets")
local inset = game:GetService("GuiService"):GetGuiInset()
h.eq(inset, Vector2.new(0, 58), "GuiService:GetGuiInset")
h.eq(workspace.CurrentCamera.ViewportSize, Vector2.new(1280, 720), "Camera.ViewportSize")

print("== 기준점 · 비율 ==")
local mid = Instance.new("Frame")
mid.Name = "Mid"
mid.AnchorPoint = Vector2.new(0.5, 0.5)
mid.Position = UDim2.fromScale(0.5, 0.5)
mid.Size = UDim2.new(0.5, 0, 0, 100)
mid.Parent = gui
h.eq(mid.AbsoluteSize, Vector2.new(640, 100), "Scale 크기")
h.eq(mid.AbsolutePosition, Vector2.new(320, 252), "AnchorPoint 0.5")
h.eq({ h.rect(mid) }, { 320, 310, 640, 100 }, "harness.rect는 화면 좌표")
mid.Visible = false

print("== UIScale 겹치기 ==")
local o = frame(gui, "O", 100, 100, 200, 100)
local os_ = Instance.new("UIScale")
os_.Scale = 2
os_.Parent = o
h.eq(o.AbsoluteSize, Vector2.new(400, 200), "제 UIScale은 제 크기에 곱해진다")
h.eq(o.AbsolutePosition, Vector2.new(100, 42), "자리는 그대로")
local c = frame(o, "C", 10, 10, 50, 20)
h.eq(c.AbsoluteSize, Vector2.new(100, 40), "아이의 오프셋 크기 x2")
h.eq(c.AbsolutePosition, Vector2.new(120, 62), "아이의 오프셋 자리 x2")
local half = Instance.new("Frame")
half.Size = UDim2.fromScale(0.5, 0.5)
half.Parent = o
h.eq(half.AbsoluteSize, Vector2.new(200, 100), "아이의 Scale 크기는 부모의 보이는 크기 기준")
half:Destroy()
local cs = Instance.new("UIScale")
cs.Scale = 1.5
cs.Parent = c
h.eq(c.AbsoluteSize, Vector2.new(150, 60), "배율이 곱해진다(2 x 1.5)")
local g = frame(c, "G", 4, 4, 10, 10)
h.eq(g.AbsoluteSize, Vector2.new(30, 30), "손자: x3")
h.eq(g.AbsolutePosition, Vector2.new(132, 74), "손자의 자리: x3")
-- 바뀜 알림
local sizeChanges = 0
g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	sizeChanges += 1
end)
os_.Scale = 1
h.step(1)
h.eq(sizeChanges, 1, "배율이 바뀌면 AbsoluteSize 알림")
h.eq(g.AbsoluteSize, Vector2.new(15, 15), "새 배율로")
o.Visible = false

print("== UIPadding · 크기 묶기 ==")
local p = frame(gui, "P", 0, 0, 200, 100)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 5)
pad.PaddingRight = UDim.new(0, 20)
pad.PaddingBottom = UDim.new(0, 15)
pad.Parent = p
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.Parent = p
h.eq(fill.AbsoluteSize, Vector2.new(170, 80), "패딩 안쪽 크기")
h.eq(fill.AbsolutePosition, Vector2.new(10, -53), "패딩 안쪽 자리")
local sq = Instance.new("Frame")
sq.Size = UDim2.fromScale(1, 1)
sq.SizeConstraint = Enum.SizeConstraint.RelativeYY
sq.Parent = p
h.eq(sq.AbsoluteSize, Vector2.new(80, 80), "SizeConstraint.RelativeYY")
local ar = frame(gui, "Aspect", 0, 0, 200, 100)
local arc = Instance.new("UIAspectRatioConstraint")
arc.AspectRatio = 1
arc.Parent = ar
h.eq(ar.AbsoluteSize, Vector2.new(100, 100), "UIAspectRatioConstraint")
local lim = frame(gui, "Limit", 0, 0, 200, 100)
local szc = Instance.new("UISizeConstraint")
szc.MaxSize = Vector2.new(50, 60)
szc.Parent = lim
h.eq(lim.AbsoluteSize, Vector2.new(50, 60), "UISizeConstraint")
local rot = frame(gui, "Rot", 0, 0, 10, 10)
rot.Rotation = 30
local rot2 = frame(rot, "Rot2", 0, 0, 5, 5)
rot2.Rotation = 15
h.eq(rot2.AbsoluteRotation, 45, "AbsoluteRotation")
for _, x in { p, ar, lim, rot } do
	x.Visible = false
end

print("== UIListLayout ==")
local box = frame(gui, "List", 300, 200, 200, 150)
local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 5)
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Bottom
list.Parent = box
local i3 = frame(box, "three", 999, 999, 100, 20)
i3.LayoutOrder = 3
local i1 = frame(box, "one", 0, 0, 100, 30)
i1.LayoutOrder = 1
local i2 = frame(box, "two", 0, 0, 100, 40)
i2.LayoutOrder = 2
local hidden = frame(box, "hidden", 0, 0, 100, 500)
hidden.Visible = false
h.eq(list.AbsoluteContentSize, Vector2.new(100, 100), "AbsoluteContentSize")
h.eq({ h.rect(i1) }, { 350, 250, 100, 30 }, "첫째(LayoutOrder 1) — 가운데 · 아래 맞춤")
h.eq({ h.rect(i2) }, { 350, 285, 100, 40 }, "둘째")
h.eq({ h.rect(i3) }, { 350, 330, 100, 20 }, "셋째(제 Position은 무시)")
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Left
list.VerticalAlignment = Enum.VerticalAlignment.Top
h.eq({ h.rect(i2) }, { 405, 200, 100, 40 }, "가로로 놓기")
h.eq(list.AbsoluteContentSize, Vector2.new(310, 40), "가로일 때의 내용 크기")
list.SortOrder = Enum.SortOrder.Name
h.eq({ h.rect(i3) }, { 405, 200, 100, 20 }, "이름순(one · three · two)")
box.Visible = false

print("== UIGridLayout ==")
local gbox = frame(gui, "Grid", 600, 100, 200, 200)
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(40, 30)
grid.CellPadding = UDim2.fromOffset(10, 5)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = gbox
local cells = {}
for i = 1, 7 do
	local cell = frame(gbox, "c" .. i, 0, 0, 1, 1)
	cell.LayoutOrder = i
	cells[i] = cell
end
h.eq({ h.rect(cells[1]) }, { 600, 100, 40, 30 }, "칸의 크기는 CellSize")
h.eq({ h.rect(cells[4]) }, { 750, 100, 40, 30 }, "한 줄에 넷")
h.eq({ h.rect(cells[5]) }, { 600, 135, 40, 30 }, "다섯째는 다음 줄")
h.eq(grid.AbsoluteContentSize, Vector2.new(190, 65), "격자의 내용 크기")
grid.FillDirectionMaxCells = 3
h.eq({ h.rect(cells[4]) }, { 600, 135, 40, 30 }, "FillDirectionMaxCells = 3")
gbox.Visible = false

print("== AutomaticSize · 글의 크기 ==")
local auto = Instance.new("TextLabel")
auto.AutomaticSize = Enum.AutomaticSize.XY
auto.TextSize = 20
auto.Text = "가나다"
auto.Parent = gui
h.eq(auto.TextBounds, Vector2.new(51, 20), "한글 3자 · 20: 폭 = 3 x 20 x 0.85")
h.eq(auto.AbsoluteSize, Vector2.new(51, 20), "AutomaticSize.XY = 글의 크기")
auto.Text = "가나다\n라"
h.eq(auto.AbsoluteSize, Vector2.new(51, 40), "두 줄")
local wrap = Instance.new("TextLabel")
wrap.Size = UDim2.fromOffset(40, 100)
wrap.TextSize = 20
wrap.TextWrapped = true
wrap.Text = "가나다"
wrap.Parent = gui
h.eq(wrap.TextBounds, Vector2.new(34, 40), "TextWrapped: 폭 40에 두 자씩")
h.eq(wrap.TextFits, true, "TextFits")
wrap.TextWrapped = false
h.eq(wrap.TextFits, false, "한 줄로는 넘친다")
local scaled = Instance.new("TextLabel")
scaled.Size = UDim2.fromOffset(170, 50)
scaled.TextScaled = true
scaled.Text = "가나다라"
scaled.Parent = gui
h.eq(scaled.TextBounds.Y, 50, "TextScaled: 높이 50에 꽉 차게(폭 4 x 50 x 0.85 = 170)")
local ts = game:GetService("TextService")
h.eq(ts:GetTextSize("가나다", 20, Enum.Font.SourceSans, Vector2.new(1000, 1000)), Vector2.new(51, 20), "TextService:GetTextSize")
h.eq(ts:GetTextSize("가나다", 20, Enum.Font.SourceSans, Vector2.new(40, 1000)), Vector2.new(34, 40), "GetTextSize(줄 바꿈)")
local rich = Instance.new("TextLabel")
rich.RichText = true
rich.Text = '<b>굵게</b> <font color="#ff0000">빨강</font>'
h.eq(rich.ContentText, "굵게 빨강", "RichText의 ContentText")
local grow = frame(gui, "Grow", 0, 0, 100, 0)
grow.AutomaticSize = Enum.AutomaticSize.Y
frame(grow, "Kid", 0, 10, 50, 50)
h.eq(grow.AbsoluteSize, Vector2.new(100, 60), "AutomaticSize.Y = 아이의 끝")
for _, x in { auto, wrap, scaled, grow } do
	x.Visible = false
end

print("== ScrollingFrame ==")
local sf = Instance.new("ScrollingFrame")
sf.Position = UDim2.fromOffset(900, 100)
sf.Size = UDim2.fromOffset(100, 100)
sf.CanvasSize = UDim2.fromOffset(0, 500)
sf.Parent = gui
local item = frame(sf, "Item", 0, 300, 50, 20)
h.eq(sf.AbsoluteCanvasSize, Vector2.new(100, 500), "AbsoluteCanvasSize")
h.eq({ h.rect(item) }, { 900, 400, 50, 20 }, "굴리기 전")
sf.CanvasPosition = Vector2.new(0, 250)
h.eq({ h.rect(item) }, { 900, 150, 50, 20 }, "CanvasPosition만큼 올라간다")
h.eq(h.at(925, 160), item, "잘린 틀 안: 보인다")
sf.CanvasPosition = Vector2.new(0, 0)
h.eq(h.at(925, 410) ~= item, true, "틀 밖으로 나간 것은 누를 수 없다")
h.wheel(950, 150, -1)
h.eq(sf.CanvasPosition, Vector2.new(0, 40), "휠로 굴리기")
sf.Visible = false

print("== 누른 자리 · 자르기 · 겹치는 차례 ==")
local clip = frame(gui, "Clip", 500, 300, 100, 100)
clip.ClipsDescendants = true
local inside = button(clip, "Inside", 50, 50, 100, 100)
local downAt
inside.MouseButton1Down:Connect(function(x, y)
	downAt = { x, y }
end)
h.eq(h.click(620, 420), nil, "잘려 나간 자리는 누를 수 없다")
h.eq(h.click(575, 375), inside, "보이는 자리는 눌린다")
h.eq(downAt, { 575, 317 }, "MouseButton1Down의 좌표는 띠를 뺀 것")
clip.Visible = false

local low = button(gui, "Low", 200, 500, 100, 50)
local high = button(gui, "High", 250, 500, 100, 50)
high.ZIndex = 2
h.eq(h.click(275, 525), high, "ZIndex가 큰 것이 위")
low.ZIndex = 3
h.eq(h.click(275, 525), low, "ZIndex를 바꾸면 차례가 바뀐다")
low.Visible = false
h.eq(h.click(275, 525), high, "숨긴 것은 누를 수 없다")
low.Visible = true
low.ZIndex = 1
local cover = frame(gui, "Cover", 200, 480, 200, 100)
cover.ZIndex = 5
cover.BackgroundTransparency = 0.5
h.eq(h.click(275, 525), high, "Active가 아닌 틀은 입력을 흘려보낸다")
cover.Active = true
h.eq(h.click(275, 525), cover, "Active인 틀은 입력을 삼킨다")
cover.Visible = false
-- 같은 ZIndex면 나중에 넣은 아이가 위
high.ZIndex = 1
h.eq(h.click(275, 525), high, "ZIndex가 같으면 나중 아이가 위")
-- Sibling: 아이는 부모의 차례 안에서만 견준다
local parentLow = frame(gui, "ParentLow", 200, 500, 150, 50)
parentLow.ZIndex = 0
local kid = button(parentLow, "Kid", 0, 0, 150, 50)
kid.ZIndex = 100
h.eq(h.click(275, 525), high, "Sibling: 낮은 부모의 아이는 ZIndex가 커도 아래")
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
h.eq(h.click(275, 525), kid, "Global: ZIndex만으로 견준다")
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
parentLow.Visible = false
-- DisplayOrder
local top = Instance.new("ScreenGui")
top.Name = "Top"
top.IgnoreGuiInset = true
top.DisplayOrder = 20
top.Parent = pg
local topButton = button(top, "TopButton", 250, 500, 100, 50)
h.eq(h.click(275, 525), topButton, "DisplayOrder가 큰 화면 틀이 위")
top.Enabled = false
h.eq(h.click(275, 525), high, "꺼진 화면 틀은 누를 수 없다")
h.eq(pg:GetGuiObjectsAtPosition(275, 525 - 58)[1], high, "GetGuiObjectsAtPosition")

print("== 마우스 이벤트 ==")
local seen = {}
high.MouseEnter:Connect(function()
	table.insert(seen, "enter")
end)
high.MouseLeave:Connect(function()
	table.insert(seen, "leave")
end)
high.MouseButton1Click:Connect(function()
	table.insert(seen, "click")
end)
high.Activated:Connect(function(input, count)
	table.insert(seen, "activated " .. input.UserInputType.Name)
end)
local UIS = game:GetService("UserInputService")
local uisSeen = {}
UIS.InputBegan:Connect(function(input, processed)
	table.insert(uisSeen, input.UserInputType.Name .. (if processed then " processed" else ""))
end)
h.mouseMove(10, 10)
seen = {} -- (앞의 누름으로 마우스가 이미 단추 위에 있었다 → 나감이 한 번 온다)
h.mouseMove(300, 520)
h.eq(high.GuiState, Enum.GuiState.Hover, "GuiState.Hover")
h.mouseDown()
h.eq(high.GuiState, Enum.GuiState.Press, "GuiState.Press")
h.mouseUp()
h.mouseMove(10, 10)
h.eq(seen, { "enter", "click", "activated MouseButton1", "leave" }, "들어옴 · 누름 · 나감")
h.eq(UIS:GetMouseLocation(), Vector2.new(10, 10), "GetMouseLocation은 화면 좌표")
h.click(10, 10)
h.eq(uisSeen, { "MouseButton1 processed", "MouseButton1" }, "단추 위의 누름은 gameProcessed = true")
-- 누른 채 밖으로 나가 떼면 Click이 아니다
seen = {}
h.mouseDown(300, 520)
h.mouseUp(10, 10)
h.eq(seen, { "enter", "leave" }, "밖에서 떼면 Click이 나지 않는다")

print("== 글 칸 ==")
local tbox = Instance.new("TextBox")
tbox.Position = UDim2.fromOffset(700, 500)
tbox.Size = UDim2.fromOffset(200, 30)
tbox.Text = "처음"
tbox.Parent = gui
local lost
tbox.FocusLost:Connect(function(enter)
	lost = enter
end)
local released = false
UIS.TextBoxFocusReleased:Connect(function()
	released = true
end)
h.click(800, 515)
h.eq(tbox:IsFocused(), true, "누르면 글을 쓴다")
h.eq(UIS:GetFocusedTextBox(), tbox, "GetFocusedTextBox")
h.eq(tbox.Text, "", "ClearTextOnFocus")
h.typeText("1234")
uisSeen = {}
h.keyDown(Enum.KeyCode.A)
h.keyUp(Enum.KeyCode.A)
h.eq(uisSeen, { "Keyboard processed" }, "글을 쓰는 동안의 글쇠는 gameProcessed = true")
h.keyTap(Enum.KeyCode.Return)
h.eq({ tbox.Text, lost, released, tbox:IsFocused() }, { "1234", true, true, false }, "Enter로 끝낸다")

print("== 창 크기 바꾸기 ==")
local resized = 0
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	resized += 1
end)
h.resize(844, 390)
h.eq(gui.AbsoluteSize, Vector2.new(844, 390), "새 크기")
h.eq(resized, 1, "AbsoluteSize 알림")
h.eq(gui2.AbsoluteSize, Vector2.new(844, 332), "띠를 뺀 크기")

print("끝: layout")
