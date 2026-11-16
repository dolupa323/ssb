--!strict
-- 입력: 원본 main.js의 「input」 부분.
--  글쇠: WASD · 방향키 = 이동. 그 밖의 글쇠(Space · Shift · P · 1~3 · R · Enter)는 handlers.key가 먼저 본다.
--  손가락 · 마우스: 세계를 누르고 끌면 그 자리에 뜨는 조이스틱(8px 안쪽은 무시 · 52px에서 끝까지), 끄는 동안 다른 손가락으로 치면 대시.
--  게임패드(원본에는 없다 — 작게 덧붙인 것): 왼쪽 막대 = 이동 · A = 대시 · Start = 일시정지.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Input = {}

export type Handlers = {
	key: (code: Enum.KeyCode) -> boolean, -- 글쇠를 눌렀다. true를 돌려주면 이동 글쇠로 치지 않는다
	canJoy: () -> boolean, -- 지금 세계를 끌 수 있는가(원본: mode === 'play')
	dash: () -> (),
	pause: () -> (), -- 게임패드 Start
	blur: () -> (), -- 창이 뒤로 갔다
	menu: () -> (), -- Roblox 메뉴(Esc)가 열렸다
	wake: () -> (), -- 처음 누름(원본: 소리를 깨운다)
}

Input.DEAD = 8 -- 조이스틱: 이만큼(px)은 움직여야 방향으로 친다
Input.RADIUS = 52 -- 이만큼 끌면 끝까지
Input.KNOB = 21
Input.STICK_DEAD = 0.2 -- 게임패드 막대

local KEYMAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "u",
	[Enum.KeyCode.W] = "u",
	[Enum.KeyCode.Down] = "d",
	[Enum.KeyCode.S] = "d",
	[Enum.KeyCode.Left] = "l",
	[Enum.KeyCode.A] = "l",
	[Enum.KeyCode.Right] = "r",
	[Enum.KeyCode.D] = "r",
}

local keys = {} :: { [string]: boolean } -- 눌린 방향("u" "d" "l" "r")
local held = {} :: { [Enum.KeyCode]: string } -- 눌린 글쇠 → 방향 (같은 방향의 글쇠 둘을 따로 센다)
local joy = { active = false, id = nil :: any, mouse = false, ox = 0, oy = 0, x = 0, y = 0 }
local stick = { x = 0, y = 0 }
Input.joy = joy
Input.keys = keys
Input.stick = stick

local stage: any = nil
local ring: Frame? = nil
local knob: Frame? = nil

-- 원본 keys.clear(); joy.active = false
function Input.clear()
	table.clear(keys)
	table.clear(held)
	joy.active = false
	joy.id = nil
end

-- 원본 readInput()
function Input.read(): { x: number, y: number }
	local x = (if keys.r then 1 else 0) - (if keys.l then 1 else 0)
	local y = (if keys.d then 1 else 0) - (if keys.u then 1 else 0)
	if x == 0 and y == 0 and (stick.x ~= 0 or stick.y ~= 0) then
		x, y = stick.x, stick.y
	end
	if joy.active then
		local dx, dy = joy.x - joy.ox, joy.y - joy.oy
		local d = math.sqrt(dx * dx + dy * dy)
		if d > Input.DEAD then
			local m = math.min(1, d / Input.RADIUS)
			x, y = dx / d * m, dy / d * m
		end
	end
	local l = math.sqrt(x * x + y * y)
	if l > 1 then
		x, y = x / l, y / l
	end
	return { x = x, y = y }
end

-- 조이스틱을 그린다(원본 gfx.js 1193줄: 반지름 52의 고리 + 반지름 21의 손잡이). 매 장면 부른다
function Input.draw(show: boolean)
	local r, k = ring :: Frame, knob :: Frame
	if not (show and joy.active) then
		if r.Visible then
			r.Visible = false
			k.Visible = false
		end
		return
	end
	local dx, dy = joy.x - joy.ox, joy.y - joy.oy
	local d = math.sqrt(dx * dx + dy * dy)
	if d == 0 then
		d = 1
	end
	local m = math.min(Input.RADIUS, d)
	r.Position = UDim2.fromOffset(joy.ox, joy.oy)
	k.Position = UDim2.fromOffset(joy.ox + dx / d * m, joy.oy + dy / d * m)
	r.Visible = true
	k.Visible = true
end

local function circle(parent: Instance, name: string, radius: number, color: Color3, alpha: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(radius * 2, radius * 2)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	f.BorderSizePixel = 0
	f.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	f.Parent = parent
	return f
end

function Input.init(stageModule: any, handlers: Handlers)
	stage = stageModule

	-- 조이스틱 그림: 화면 틀의 맨 아래(HUD보다 아래)
	local layer = Instance.new("Frame")
	layer.Name = "Joy"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = 1
	layer.Parent = stage.ui
	-- 고리: 선 3px이 반지름 52를 가운데로 지난다 → 틀의 반지름 50.5 + 바깥 테두리 3
	local r = circle(layer, "Ring", Input.RADIUS - 1.5, Color3.fromRGB(20, 26, 30), 0.25)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = Color3.new(1, 1, 1)
	s.Transparency = 0.5
	s.Parent = r
	ring = r
	knob = circle(layer, "Knob", Input.KNOB, Color3.new(1, 1, 1), 0.75)

	local wake = handlers.wake

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard then
			if processed then
				return -- 채팅 칸에 쓰는 중
			end
			wake()
			local code = input.KeyCode
			if handlers.key(code) then
				return
			end
			local k = KEYMAP[code]
			if k then
				held[code] = k
				keys[k] = true
			end
		elseif t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			wake()
		elseif t == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.ButtonA then
				handlers.dash()
			elseif input.KeyCode == Enum.KeyCode.ButtonStart then
				handlers.pause()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard then
			local k = held[input.KeyCode]
			if k then
				held[input.KeyCode] = nil
				local still = false
				for _, other in held do
					if other == k then
						still = true
						break
					end
				end
				if not still then
					keys[k] = nil
				end
			end
		elseif t == Enum.UserInputType.Touch then
			if joy.active and not joy.mouse and input == joy.id then
				joy.active = false
				joy.id = nil
			end
		elseif t == Enum.UserInputType.MouseButton1 then
			if joy.active and joy.mouse then
				joy.active = false
				joy.id = nil
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if joy.active and not joy.mouse and input == joy.id then
				joy.x, joy.y = stage.toUi(input.Position)
			end
		elseif t == Enum.UserInputType.MouseMovement then
			if joy.active and joy.mouse then
				joy.x, joy.y = stage.toUi(input.Position)
			end
		elseif t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x, y = input.Position.X, -input.Position.Y
			if math.sqrt(x * x + y * y) < Input.STICK_DEAD then
				x, y = 0, 0
			end
			stick.x, stick.y = x, y
		end
	end)

	-- 세계를 누름(원본 cv의 pointerdown): 조이스틱을 놓는다. 이미 끄는 중이면 다른 손가락은 대시
	stage.pad.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not handlers.canJoy() then
			return
		end
		if joy.active and input ~= joy.id then
			handlers.dash()
			return
		end
		joy.active = true
		joy.id = input
		joy.mouse = t == Enum.UserInputType.MouseButton1
		joy.ox, joy.oy = stage.toUi(input.Position)
		joy.x, joy.y = joy.ox, joy.oy
	end)

	-- 창이 뒤로 갔다(원본 blur + visibilitychange)
	UserInputService.WindowFocusReleased:Connect(function()
		Input.clear()
		handlers.blur()
	end)
	-- Esc는 Roblox가 제 메뉴에 쓴다 → 메뉴가 열리면 일시정지
	GuiService.MenuOpened:Connect(function()
		Input.clear()
		handlers.menu()
	end)
end

return Input
