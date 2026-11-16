--!strict
-- 여러 화면이 같이 쓰는 조각: 큰 단추(.go) · 글쇠 표시(kbd) · 덮개(.overlay) · 음량 막대(input[type=range]) · 고르는 단추 줄(.seg).
local UserInputService = game:GetService("UserInputService")
local T = require(script.Parent.Theme)
local Stage = require(script.Parent.Parent.Stage) :: any

local C = T.C
local W = {}
W.click = nil :: (() -> ())? -- 단추 소리(원본: .go 단추를 누르면 'click')

-- ---------- .go / .go.sub ----------
export type GoOpts = { text: string, x: number, y: number, w: number, h: number, sub: boolean?, light: boolean?, icon: ((Frame) -> number)? }
-- light = 밝은 바탕 위(메뉴): sub 단추의 글 · 테두리가 먹색. 아니면 흰색(.panel .go.sub)
function W.go(parent: Instance, name: string, o: GoOpts): TextButton
	local btn = T.button(parent, name, { x = o.x, y = o.y, w = o.w, h = o.h })
	local body: Frame
	local face: Frame
	if o.sub then
		local col = if o.light then C.ink else C.white
		body = T.box(btn, "Body", { size = UDim2.fromScale(1, 1), bg = C.white, a = 0, r = 10, b = 2, bc = col })
		face = body
		T.label(body, "T", { text = o.text, fs = 18, font = "display", color = col, ax = "Center", size = UDim2.fromScale(1, 1) })
		T.states(btn, function(over)
			if not o.light then
				body.BackgroundTransparency = if over then 0.88 else 1
			end
		end, nil)
	else
		body = T.box(btn, "Body", { size = UDim2.fromScale(1, 1), bg = C.line2, r = 10 })
		face = T.box(body, "Face", { size = UDim2.new(1, 0, 1, -5), bg = C.ink, r = 10 })
		local label = T.label(face, "T", { text = o.text, fs = 24, font = "display", color = C.white, ax = "Center", size = UDim2.fromScale(1, 1) })
		if o.icon then
			-- 그림 + 글을 가운데로 (gap 12)
			label.Size = UDim2.fromOffset(2000, 30)
			local tw = T.bounds(label)
			local holder = T.box(face, "Icon", { w = 10, h = 10 })
			local iw = o.icon(holder)
			local x0 = (o.w - (iw + 12 + tw)) / 2
			holder.Position = UDim2.new(0, x0, 0.5, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(x0 + iw + 12, 0)
			label.Size = UDim2.new(0, tw + 2, 1, 0)
		end
		-- :hover 바탕 #000 · :active translateY(2px)
		local setY = T.transition(0.08, T.EASE.ease, function(v)
			body.Position = UDim2.fromOffset(0, v)
		end)
		setY(0, true)
		T.states(btn, function(over)
			face.BackgroundColor3 = if over then C.black else C.ink
		end, function(down)
			setY(if down then 2 else 0)
		end)
	end
	btn.MouseButton1Click:Connect(function()
		if W.click then
			W.click()
		end
	end)
	return btn
end

-- ---------- kbd ----------
-- 글쇠 하나. 돌려주는 것: 틀, 폭, 글. (원본 kbd: 12px 600 · 흰 바탕 · 테두리 1px, 아래 2px · 둥글기 4 · 안쪽 여백 1px 6px)
function W.kbd(parent: Instance, text: string, x: number, y: number, dark: boolean?): (Frame, number, TextLabel)
	local l = T.label(parent, "kbdT", { text = text, fs = 12, wt = 600, color = if dark then C.white else C.ink, ax = "Center", z = 2 })
	l.Size = UDim2.fromOffset(400, 18)
	local tw = T.bounds(l)
	local w = tw + 12 + 2
	local h = 23
	local edge = if dark then C.white else T.hex("#c9c6bd")
	local f = T.box(parent, "kbd", { x = x, y = y, w = w, h = h, bg = if dark then nil else C.white, r = 4, b = 1, bc = edge, ba = if dark then 0.5 else 1 })
	T.box(f, "under", { pos = UDim2.new(0, 2, 1, -1), size = UDim2.new(1, -4, 0, 1), bg = edge, a = if dark then 0.5 else 1 }) -- 아래 테두리가 1px 더 굵다
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h - 1)
	return f, w, l
end

-- ---------- .overlay ----------
export type Overlay = { root: Frame, scroll: ScrollingFrame, place: (panel: GuiObject, w: number, h: number, left: number?, inner: number?) -> () }
-- 화면을 덮는 판. 안의 것이 화면보다 길면 굴린다(원본 overflow-y:auto), 짧으면 가운데(margin:auto)
function W.overlay(name: string, z: number, bg: Color3?, alpha: number?): Overlay
	local root = T.box(Stage.ui, name, { size = UDim2.fromScale(1, 1), bg = bg, a = alpha, z = z, active = true, visible = false })
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.white
	scroll.ScrollBarImageTransparency = 0.5
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = root
	-- inner = 판 안에서 실제로 무언가 그려지는 맨 왼쪽(판은 넓어도 안의 것이 가운데에 좁게 놓일 때)
	local function place(panel: GuiObject, w: number, h: number, left: number?, inner: number?)
		local sw, sh = Stage.w, Stage.h
		local x = if left then left else math.floor((sw - w) / 2)
		-- 왼쪽 위의 Roblox 기본 단추와 겹칠 만큼 왼쪽까지 오는 판은, 위에 붙을 때 그 띠 아래에서 시작한다
		local topPad = if x + (inner or 0) < Stage.insetLeft + 4 then math.max(16, Stage.insetTop + 6) else 16
		if h + 32 <= sh then
			local y = math.floor((sh - h) / 2)
			if y < topPad and h + topPad + 16 <= sh then
				y = topPad
			end
			panel.Position = UDim2.fromOffset(x, y)
			scroll.CanvasSize = UDim2.fromOffset(0, 0)
		else
			panel.Position = UDim2.fromOffset(x, topPad)
			scroll.CanvasSize = UDim2.fromOffset(0, h + topPad + 16)
		end
	end
	return { root = root, scroll = scroll, place = place }
end

-- ---------- input[type=range] ----------
export type Slider = { root: TextButton, set: (number) -> (), value: () -> number }
-- 0..100, 5씩. onInput = 값이 바뀔 때마다, onChange = 손을 뗐을 때
function W.slider(parent: Instance, name: string, x: number, y: number, w: number, value: number, onInput: (number) -> (), onChange: (() -> ())?): Slider
	local h = 28
	local btn = T.button(parent, name, { x = x, y = y, w = w, h = h })
	-- (Chrome이 그리는 기본 막대의 모습: 어두운 줄 + 초록으로 찬 부분 + 초록 동그라미)
	local track = T.box(btn, "Track", { pos = UDim2.new(0, 0, 0.5, -3), size = UDim2.new(1, 0, 0, 6), bg = T.hex("#404040"), r = 3 })
	local fill = T.box(track, "Fill", { size = UDim2.new(0, 0, 1, 0), bg = C.line2, r = 3 })
	local thumb = T.box(btn, "Thumb", { pos = UDim2.new(0, 8, 0.5, 0), w = 16, h = 16, anchor = Vector2.new(0.5, 0.5), bg = C.line2, r = 1000, z = 2 })
	local cur = value
	local function show()
		local f = cur / 100
		thumb.Position = UDim2.new(0, 8 + (w - 16) * f, 0.5, 0)
		fill.Size = UDim2.new(0, math.max(0, 8 + (w - 16) * f - 1), 1, 0)
	end
	show()
	local dragging: InputObject? = nil
	local function at(pos: Vector3)
		local px = Stage.toUi(pos)
		local left = (btn.AbsolutePosition.X - Stage.ui.AbsolutePosition.X) / Stage.scale
		local f = math.clamp((px - left - 8) / (w - 16), 0, 1)
		local v = math.floor(f * 20 + 0.5) * 5
		if v ~= cur then
			cur = v
			show()
			onInput(v)
		end
	end
	btn.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			at(input.Position)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if not d then
			return
		end
		if input == d or (d.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
			at(input.Position)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = dragging
		if d and (input == d or (d.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			dragging = nil
			if onChange then
				onChange()
			end
		end
	end)
	btn.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	return {
		root = btn,
		set = function(v: number)
			cur = v
			show()
		end,
		value = function()
			return cur
		end,
	}
end

-- ---------- .seg ----------
export type Seg = { buttons: { TextButton }, press: (number?) -> () }
-- 나란한 단추들. items = { { 글, 값 } … }. press(값) = 그 값의 단추를 눌린 모양으로(aria-pressed)
function W.seg(parent: Instance, name: string, x: number, y: number, w: number, items: { { any } }, onPick: (any) -> ()): Seg
	local n = #items
	local bw = (w - 5 * (n - 1)) / n
	local buttons = {}
	local faces = {} :: { { any } }
	for i, it in ipairs(items) do
		local b = T.button(parent, name .. i, { x = x + (i - 1) * (bw + 5), y = y, w = bw, h = 37, bg = C.white, r = 7, b = 2, bc = T.hex("#cfcbc0") })
		local l = T.label(b, "T", { text = it[1], fs = 13, wt = 700, color = C.ink, ax = "Center", size = UDim2.fromScale(1, 1) })
		b.MouseButton1Click:Connect(function()
			onPick(it[2])
		end)
		buttons[i] = b
		faces[i] = { b, l, b:FindFirstChildOfClass("UIStroke"), it[2] }
	end
	local function press(v: any)
		for _, f in faces do
			local on = v ~= nil and f[4] == v
			f[1].BackgroundColor3 = if on then C.ink else C.white
			f[2].TextColor3 = if on then C.white else C.ink
			f[3].Color = if on then C.ink else T.hex("#cfcbc0")
		end
	end
	return { buttons = buttons, press = press }
end

return W
