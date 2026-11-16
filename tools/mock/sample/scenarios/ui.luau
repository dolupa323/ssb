-- 자체 시험 5: 견본 게임을 돌린다 — 점 그림(EditableImage) · 한글 글씨 · 마우스 · 손가락 · 글쇠로 움직이기 · 화면 찍기.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --script tools/mock/sample/scenarios/ui.luau --shot-dir tools/mock/sample/shots
--  node tools/mock/run.mjs … --viewport 844x390 (폰 가로)
local h = harness
local W, H = h.viewport()
local tagName = string.format("%dx%d", W, H)

h.step(40) -- 트윈(0.5초) · 서버에 다녀오는 것이 끝나게

print("== 화면 틀 ==")
local view = h.get("PlayerGui.Sample.Holder.View")
local ui = h.get("PlayerGui.Sample.Holder.Ui")
local holder = h.get("PlayerGui.Sample.Holder")
local fit = math.min(W / 384, H / 216)
local s = if fit >= 2 then math.floor(fit) else fit
h.near(view.UIScale.Scale, s, 1e-9, "게임 세계의 배율")
h.near(ui.UIScale.Scale, s * 384 / 576, 1e-9, "글씨 층의 배율")
local hx, hy, hw, hh = h.rect(holder)
h.eq({ hw, hh }, { math.floor(384 * s + 0.5), math.floor(216 * s + 0.5) }, "틀의 크기")
h.eq({ hx, hy }, { math.floor((W - hw) / 2), math.floor((H - hh) / 2) }, "틀은 화면 가운데")
print(string.format("  화면 %s · 배율 %.4f · 틀 [%d,%d %dx%d]", tagName, s, hx, hy, hw, hh))

print("== 그림 조각 ==")
local world = view.World
local right, left = world.PersonRight, world.PersonLeft
h.eq({ right.ImageRectOffset, right.ImageRectSize }, { Vector2.new(0, 0), Vector2.new(16, 16) }, "오른쪽을 보는 조각")
h.eq({ left.ImageRectOffset, left.ImageRectSize }, { Vector2.new(16, 0), Vector2.new(-16, 16) }, "뒤집은 조각(폭이 음수)")
local rx, ry, rw, rh = h.rect(right)
h.near(rw, 16 * s, 0.001, "조각의 화면 크기 = 16 x 배율")
h.near(rx, hx + 40 * s, 0.001, "조각의 화면 자리")
local atlas = right.ImageContent.Object
h.eq(atlas.Size, Vector2.new(64, 16), "그림판의 크기")
local px = atlas:ReadPixelsBuffer(Vector2.new(11, 6), Vector2.new(1, 1))
h.eq({ buffer.readu8(px, 0), buffer.readu8(px, 1), buffer.readu8(px, 2), buffer.readu8(px, 3) }, { 240, 200, 160, 255 }, "그림판에 찍힌 점(코)")

print("== 글씨 ==")
h.eq(h.findByText("출근길 서바이벌", false) ~= nil, true, "한글 제목을 글로 찾는다")
h.eq(ui.Best.Text, "최고 기록: 0", "서버에서 받은 기록")
h.eq(ui.Clock.Text, "시각 08:00", "시계")
local bar = ui.BarBack.Bar
h.eq(bar.Size, UDim2.fromScale(0.8, 1), "트윈이 끝 값에 닿았다")
h.shot("ui-" .. tagName .. "-1.png")

print("== 글쇠로 움직이기 ==")
local hero = world.Hero
h.eq(hero.Position, UDim2.fromOffset(184, 140), "처음 자리")
h.keyDown(Enum.KeyCode.D)
h.step(30)
h.keyUp(Enum.KeyCode.D)
h.eq(hero.Position, UDim2.fromOffset(229, 140), "D를 30장(0.5초) → 오른쪽으로 45도트")
h.step(10)
h.eq(hero.Position, UDim2.fromOffset(229, 140), "떼면 멈춘다")
h.keyDown("W")
h.step(12)
h.keyUp("W")
h.eq(hero.Position, UDim2.fromOffset(229, 122), "W를 12장 → 위로 18도트")
h.keyDown(Enum.KeyCode.Left)
h.keyDown(Enum.KeyCode.Down)
h.step(6)
h.keyUp(Enum.KeyCode.Left)
h.keyUp(Enum.KeyCode.Down)
h.eq(hero.Position, UDim2.fromOffset(220, 131), "왼쪽 + 아래를 같이 6장")
h.eq(hero.ImageRectSize, Vector2.new(-16, 16), "왼쪽으로 가면 그림을 뒤집는다")
h.eq(game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.Left), false, "IsKeyDown")
h.eq(ui.Clock.Text, "시각 08:01", "1초가 지나 시계가 간다")

print("== 마우스 ==")
local counter = ui.Counter
local startButton = ui.Menu.Start
h.clickOn(startButton)
h.clickOn(startButton)
h.eq(counter.Text, "누른 횟수: 2", "마우스로 두 번")

print("== 손가락 ==")
h.setDevice({ touch = true, preferred = "Touch" })
h.tapOn(startButton)
h.eq(counter.Text, "누른 횟수: 3", "손가락으로 한 번 더")
local pad = ui.Pad
local padX, padY = h.center(pad)
local touchA = h.touchBegin(1, padX - 10, padY)
local touchB = h.touchBegin(2, padX + 10, padY)
h.eq(touchA ~= touchB, true, "손가락마다 InputObject가 다르다")
h.eq(ui.Touches.Text, "손가락 2개", "두 손가락")
local moved = h.touchMove(1, padX - 20, padY - 5)
h.eq(moved == touchA and moved.UserInputState == Enum.UserInputState.Change, true, "움직여도 같은 InputObject")
h.eq(moved.Position, Vector3.new(padX - 20, padY - 5 - 58, 0), "InputObject.Position은 띠를 뺀 좌표")
h.touchEnd(1)
h.eq(ui.Touches.Text, "손가락 1개", "하나를 뗀다")
h.touchEnd(2)
h.eq(ui.Touches.Text, "손가락 0개", "다 뗀다")

print("== 기록 내기 ==")
h.tapOn(ui.Menu.Submit)
h.step(30)
h.eq(ui.Best.Text, "최고 기록: 30", "3번 x 10점이 서버에 저장되어 돌아온다")
h.shot("ui-" .. tagName .. "-2.png")

print("== 차림표 닫기 ==")
local sx, sy = h.center(startButton)
h.tapOn(ui.Menu.Settings)
h.eq(h.isVisible(startButton), false, "차림표가 닫혀 단추가 보이지 않는다")
h.eq(h.tap(sx, sy), nil, "그 자리를 눌러도 받는 것이 없다")
h.eq(counter.Text, "누른 횟수: 3", "횟수도 그대로")

print("끝: ui " .. tagName)
