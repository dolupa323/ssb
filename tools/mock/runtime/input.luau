-- 입력 흉내: 글쇠 · 마우스 · 손가락(여러 개) · 글 칸. UserInputService · ContextActionService · GuiObject/GuiButton의 이벤트를 낸다.
--  하네스가 주는 좌표는 「화면 좌표」(창의 왼쪽 위가 0, 0 — GetMouseLocation과 같다).
--  InputObject.Position · MouseButton1Down(x, y) 은 Roblox처럼 위쪽 띠(GuiInset)만큼 뺀 좌표(AbsolutePosition과 같은 자리)다.
local R = require("./rt")
R.mark()
local Types = require("./types")
local Sched = require("./sched")
local Inst = require("./inst")
local Layout = require("./layout")
local Services = require("./services")
local raise = R.raise
local V2, V3 = Types.V2, Types.V3
local E = Types.enumItem
local P = Layout.P

local Input = {}
R.Input = Input

Input.mouseX, Input.mouseY = 0, 0
Input.keys = {} :: { [string]: any } -- 눌린 글쇠 이름 → InputObject
Input.mouseButtons = {} :: { [number]: any }
Input.touches = {} :: { [any]: any } -- 손가락 번호 → { input, target, x, y }
Input.focused = nil :: any -- 글을 쓰고 있는 TextBox
Input.lastType = nil :: any
Input.hovered = {} :: { [any]: boolean }
Input.pressed = {} :: { [any]: any } -- 눌린 단추(마우스 단추 번호 · 손가락 번호 → GuiButton)

local function uis()
	return Services.get("UserInputService")
end

local function newInput(inputType: string, keyCode: string?, state: string, x: number?, y: number?, z: number?)
	local io = Inst.create("InputObject")
	local st = Inst.st(io)
	st.props.UserInputType = E("UserInputType", inputType)
	st.props.KeyCode = E("KeyCode", keyCode or "Unknown")
	st.props.UserInputState = E("UserInputState", state)
	st.props.Position = V3(x or 0, y or 0, z or 0)
	return io
end

local function setLastType(inputType: string)
	local item = E("UserInputType", inputType)
	if Input.lastType ~= item then
		Input.lastType = item
		Inst.fire(uis(), "LastInputTypeChanged", item)
		-- PreferredInput: 마지막으로 쓴 입력의 갈래
		local pref = if inputType == "Touch" then "Touch" elseif string.sub(inputType, 1, 7) == "Gamepad" then "Gamepad" else "KeyboardAndMouse"
		if not Input.forcedPreferred then
			Inst.setRaw(uis(), "PreferredInput", E("PreferredInput", pref))
		end
	end
end

-- ---------- ContextActionService ----------
local actions = {} :: { any } -- { name, fn, ctx, inputs = { EnumItem… }, priority, seq }
local function matches(action, io): boolean
	local key, typ = io.KeyCode, io.UserInputType
	for _, i in action.inputs do
		if i == key or i == typ then
			return true
		end
	end
	return false
end
-- 돌려주는 것: 누가 삼켰는가(Sink)
local function dispatchActions(io): boolean
	if #actions == 0 then
		return false
	end
	local list = table.clone(actions)
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.seq > b.seq
	end)
	for _, a in list do
		if matches(a, io) then
			local result = nil
			Sched.call(a.ctx, function()
				result = a.fn(a.name, io.UserInputState, io)
			end)
			if result == nil or result == E("ContextActionResult", "Sink") then
				return true
			end
		end
	end
	return false
end

do
	local h = Inst.hook("ContextActionService")
	local seq = 0
	local function bind(name, fn, priority, ...)
		for i = #actions, 1, -1 do
			if actions[i].name == name then
				table.remove(actions, i)
			end
		end
		local inputs = { ... }
		for i, v in inputs do
			if Types.typeof(v) ~= "EnumItem" or (Types.enumName(v) ~= "KeyCode" and Types.enumName(v) ~= "UserInputType") then
				raise("ContextActionService:BindAction: 입력 " .. i .. "은 Enum.KeyCode나 Enum.UserInputType이어야 하는데 " .. Inst.describe(v) .. "이(가) 왔다")
			end
		end
		seq += 1
		table.insert(actions, { name = name, fn = fn, ctx = Sched.ctx, inputs = inputs, priority = priority, seq = seq })
	end
	h.methods.BindAction = function(_, _, name, fn, createTouchButton, ...)
		if createTouchButton then
			R.note("CAS.touchButton", "ContextActionService의 손가락 단추(createTouchButton = true)는 만들지 않는다")
		end
		bind(name, fn, 2000, ...)
	end
	h.methods.BindActionAtPriority = function(_, _, name, fn, createTouchButton, priority, ...)
		if createTouchButton then
			R.note("CAS.touchButton", "ContextActionService의 손가락 단추(createTouchButton = true)는 만들지 않는다")
		end
		bind(name, fn, priority, ...)
	end
	h.methods.UnbindAction = function(_, _, name)
		for i = #actions, 1, -1 do
			if actions[i].name == name then
				local a = actions[i]
				table.remove(actions, i)
				-- Roblox: 풀 때 Cancel 상태로 한 번 부른다
				local io = newInput("None", nil, "Cancel")
				Sched.call(a.ctx, a.fn, a.name, E("UserInputState", "Cancel"), io)
			end
		end
	end
	h.methods.UnbindAllActions = function()
		table.clear(actions)
	end
	h.methods.GetAllBoundActionInfo = function()
		local out = {}
		for _, a in actions do
			out[a.name] = { inputTypes = table.clone(a.inputs), priorityLevel = a.priority, stackOrder = a.seq }
		end
		return out
	end
	h.methods.GetBoundActionInfo = function(_, _, name)
		for _, a in actions do
			if a.name == name then
				return { inputTypes = table.clone(a.inputs), priorityLevel = a.priority, stackOrder = a.seq }
			end
		end
		return {}
	end
	h.methods.GetButton = function()
		return nil
	end
	h.methods.SetTitle = function() end
	h.methods.SetImage = function() end
	h.methods.SetPosition = function() end
	h.methods.SetDescription = function() end
end

-- ---------- UserInputService ----------
do
	local h = Inst.hook("UserInputService")
	h.defaults.KeyboardEnabled = true
	h.defaults.MouseEnabled = true
	h.defaults.MouseIconEnabled = true
	h.defaults.PreferredInput = E("PreferredInput", "KeyboardAndMouse")
	h.methods.IsKeyDown = function(_, _, key)
		return Input.keys[key.Name] ~= nil
	end
	h.methods.IsMouseButtonPressed = function(_, _, button)
		local n = tonumber(string.match(button.Name, "MouseButton(%d)"))
		return n ~= nil and Input.mouseButtons[n] ~= nil
	end
	h.methods.IsGamepadButtonDown = function(_, _, _pad, key)
		return Input.keys[key.Name] ~= nil
	end
	h.methods.GetKeysPressed = function()
		local out = {}
		for _, io in Input.keys do
			table.insert(out, io)
		end
		return out
	end
	h.methods.GetMouseButtonsPressed = function()
		local out = {}
		for _, io in Input.mouseButtons do
			table.insert(out, io)
		end
		return out
	end
	h.methods.GetMouseLocation = function()
		return V2(Input.mouseX, Input.mouseY)
	end
	h.methods.GetMouseDelta = function()
		return V2(0, 0)
	end
	h.methods.GetFocusedTextBox = function()
		return Input.focused
	end
	h.methods.GetLastInputType = function()
		return Input.lastType or E("UserInputType", "None")
	end
	h.methods.GetGamepadConnected = function()
		return Inst.getRaw(uis(), "GamepadEnabled")
	end
	h.methods.GetConnectedGamepads = function()
		return if Inst.getRaw(uis(), "GamepadEnabled") then { E("UserInputType", "Gamepad1") } else {}
	end
	h.methods.GetNavigationGamepads = function()
		return {}
	end
	h.methods.GetStringForKeyCode = function(_, _, key)
		local n = key.Name
		return if #n == 1 then n else ""
	end
	local function clientSignal(ctx)
		if ctx and not ctx.client then
			raise("UserInputService의 이벤트는 클라이언트(LocalScript)에서만 쓸 수 있다(지금: " .. ctx.name .. ")")
		end
	end
	for _, ev in { "InputBegan", "InputChanged", "InputEnded", "TouchStarted", "TouchMoved", "TouchEnded", "TouchTap" } do
		h.sigCheck[ev] = clientSignal
	end
end

-- ---------- 글 칸(TextBox) ----------
local function releaseFocus(box, enter: boolean, io: any)
	if Input.focused ~= box then
		return
	end
	Input.focused = nil
	Inst.fire(box, "FocusLost", enter, io)
	Inst.fire(uis(), "TextBoxFocusReleased", box)
	Sched.flush()
end
local function captureFocus(box)
	if Input.focused == box then
		return
	end
	if Input.focused then
		releaseFocus(Input.focused, false, nil)
	end
	Input.focused = box
	if P(Inst.st(box), "ClearTextOnFocus") then
		box.Text = ""
	end
	Inst.fire(box, "Focused")
	Inst.fire(uis(), "TextBoxFocused", box)
	Sched.flush()
end
Input.captureFocus = captureFocus
Input.releaseFocus = releaseFocus
do
	local h = Inst.hook("TextBox")
	h.methods.CaptureFocus = function(_, inst)
		captureFocus(inst)
	end
	h.methods.ReleaseFocus = function(_, inst, submitted)
		releaseFocus(inst, submitted == true, nil)
	end
	h.methods.IsFocused = function(_, inst)
		return Input.focused == inst
	end
	h.destroy = function(_, inst)
		if Input.focused == inst then
			Input.focused = nil
		end
	end
end

-- ---------- 누른 자리 찾기 ----------
-- 화면 좌표 (x, y)에서: 위에서부터, 처음으로 입력을 삼키는 것(Active)까지의 목록과 그 삼키는 것
local function pick(x: number, y: number)
	local ay = y - R.opts.insetTop
	local hits = Layout.hitList(x, ay)
	local over = {}
	local target = nil
	for _, e in hits do
		local st = e.st
		if P(st, "Interactable") then
			table.insert(over, st.self)
			if P(st, "Active") then
				target = st.self
				break
			end
		end
	end
	return over, target, hits
end
Input.pick = pick

local function setGuiState(inst, name: string)
	if Inst.is(inst) and not Inst.st(inst).destroyed then
		Inst.setRaw(inst, "GuiState", E("GuiState", name))
	end
end

-- 마우스가 올라간 것들을 다시 본다(MouseEnter · MouseLeave · MouseMoved)
local function updateHover(x: number, y: number)
	local ay = y - R.opts.insetTop
	local now = {}
	if x >= 0 and y >= 0 and x < R.opts.viewW and y < R.opts.viewH then
		for _, e in Layout.hitList(x, ay) do
			now[e.st.self] = true
		end
	end
	for inst in Input.hovered do
		if not now[inst] then
			Input.hovered[inst] = nil
			Inst.fire(inst, "MouseLeave", x, ay)
			if Inst.isA(inst, "GuiButton") and Input.pressed[1] ~= inst then
				setGuiState(inst, "Idle")
			end
		end
	end
	for inst in now do
		if not Input.hovered[inst] then
			Input.hovered[inst] = true
			Inst.fire(inst, "MouseEnter", x, ay)
			if Inst.isA(inst, "GuiButton") and Input.pressed[1] ~= inst then
				setGuiState(inst, "Hover")
			end
		else
			Inst.fire(inst, "MouseMoved", x, ay)
		end
	end
end

-- ---------- 글쇠 ----------
local function keyItem(key: any)
	if type(key) == "string" then
		local it = E("KeyCode", key)
		if not it then
			raise('harness: 없는 글쇠 "' .. key .. '"' .. R.hint(key, (function()
				local names = {}
				for _, i in Types.enumType("KeyCode"):GetEnumItems() do
					names[i.Name] = true
				end
				return names
			end)()))
		end
		return it
	end
	if not Types.isEnumItem(key, "KeyCode") then
		raise("harness: 글쇠는 Enum.KeyCode나 그 이름이어야 하는데 " .. Inst.describe(key) .. "이(가) 왔다")
	end
	return key
end

local function inputTypeOfKey(name: string): string
	if string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 10) == "Thumbstick" then
		return "Gamepad1"
	end
	return "Keyboard"
end

function Input.keyDown(key: any)
	local item = keyItem(key)
	if Input.keys[item.Name] then
		return -- 이미 눌려 있다
	end
	local typ = inputTypeOfKey(item.Name)
	local io = newInput(typ, item.Name, "Begin")
	Input.keys[item.Name] = io
	setLastType(typ)
	local typing = Input.focused ~= nil
	if typing and item.Name == "Return" then
		Inst.fire(uis(), "InputBegan", io, true)
		releaseFocus(Input.focused, true, io)
		return
	end
	local sunk = false
	if not typing then
		sunk = dispatchActions(io)
	end
	Inst.fire(uis(), "InputBegan", io, typing or sunk)
	Sched.flush()
end

function Input.keyUp(key: any)
	local item = keyItem(key)
	local io = Input.keys[item.Name]
	if not io then
		return
	end
	Input.keys[item.Name] = nil
	Inst.st(io).props.UserInputState = E("UserInputState", "End")
	local typing = Input.focused ~= nil
	local sunk = false
	if not typing then
		sunk = dispatchActions(io)
	end
	Inst.fire(uis(), "InputEnded", io, typing or sunk)
	Sched.flush()
end

-- ---------- 마우스 ----------
function Input.mouseMove(x: number, y: number)
	local dx, dy = x - Input.mouseX, y - Input.mouseY
	Input.mouseX, Input.mouseY = x, y
	setLastType("MouseMovement")
	local ay = y - R.opts.insetTop
	local io = Input.moveInput
	if not io then
		io = newInput("MouseMovement", nil, "Change", x, ay)
		Input.moveInput = io
	end
	local st = Inst.st(io)
	st.props.Position = V3(x, ay, 0)
	st.props.Delta = V3(dx, dy, 0)
	local over, target = pick(x, y)
	for _, inst in over do
		Inst.fire(inst, "InputChanged", io)
	end
	updateHover(x, y)
	Inst.fire(uis(), "InputChanged", io, target ~= nil)
	local mouse = R.player and Inst.st(R.player).mouse
	if mouse then
		Inst.fire(mouse, "Move")
	end
	Sched.flush()
end

function Input.mouseDown(x: number?, y: number?, button: number?)
	local b = button or 1
	if x and y and (x ~= Input.mouseX or y ~= Input.mouseY) then
		Input.mouseMove(x, y)
	end
	x, y = Input.mouseX, Input.mouseY
	local ay = y - R.opts.insetTop
	local io = newInput("MouseButton" .. b, nil, "Begin", x, ay)
	Input.mouseButtons[b] = io
	setLastType("MouseButton" .. b)
	local over, target = pick(x, y)
	-- 글 칸 밖을 누르면 글 칸에서 손을 뗀다
	if Input.focused and target ~= Input.focused then
		releaseFocus(Input.focused, false, io)
	end
	for _, inst in over do
		Inst.fire(inst, "InputBegan", io)
	end
	if target then
		if Inst.isA(target, "GuiButton") then
			Input.pressed[b] = target
			if b == 1 then
				setGuiState(target, "Press")
				Inst.fire(target, "MouseButton1Down", x, ay)
			elseif b == 2 then
				Inst.fire(target, "MouseButton2Down", x, ay)
			end
		elseif Inst.isA(target, "TextBox") and b == 1 and P(Inst.st(target), "TextEditable") then
			captureFocus(target)
		end
	end
	local sunk = target ~= nil
	if not sunk then
		sunk = dispatchActions(io)
	end
	Inst.fire(uis(), "InputBegan", io, sunk)
	local mouse = R.player and Inst.st(R.player).mouse
	if mouse and not target then
		Inst.fire(mouse, if b == 1 then "Button1Down" else "Button2Down")
	end
	Sched.flush()
	return target
end

function Input.mouseUp(x: number?, y: number?, button: number?)
	local b = button or 1
	if x and y and (x ~= Input.mouseX or y ~= Input.mouseY) then
		Input.mouseMove(x, y)
	end
	x, y = Input.mouseX, Input.mouseY
	local ay = y - R.opts.insetTop
	local io = Input.mouseButtons[b]
	if not io then
		return nil
	end
	Input.mouseButtons[b] = nil
	local st = Inst.st(io)
	st.props.UserInputState = E("UserInputState", "End")
	st.props.Position = V3(x, ay, 0)
	local over, target = pick(x, y)
	for _, inst in over do
		Inst.fire(inst, "InputEnded", io)
	end
	local was = Input.pressed[b]
	Input.pressed[b] = nil
	if target and Inst.isA(target, "GuiButton") then
		if b == 1 then
			Inst.fire(target, "MouseButton1Up", x, ay)
			if was == target then
				Inst.fire(target, "MouseButton1Click")
				Inst.fire(target, "Activated", io, 1)
			end
		elseif b == 2 then
			Inst.fire(target, "MouseButton2Up", x, ay)
			if was == target then
				Inst.fire(target, "MouseButton2Click")
				Inst.fire(target, "SecondaryActivated", io)
			end
		end
	end
	if was then
		setGuiState(was, if Input.hovered[was] then "Hover" else "Idle")
	end
	local sunk = target ~= nil
	if not sunk then
		sunk = dispatchActions(io)
	end
	Inst.fire(uis(), "InputEnded", io, sunk)
	local mouse = R.player and Inst.st(R.player).mouse
	if mouse and not target then
		Inst.fire(mouse, if b == 1 then "Button1Up" else "Button2Up")
	end
	Sched.flush()
	return target
end

function Input.wheel(x: number, y: number, delta: number)
	Input.mouseMove(x, y)
	local ay = y - R.opts.insetTop
	local io = newInput("MouseWheel", nil, "Change", x, ay, delta)
	local over, target = pick(x, y)
	for _, inst in over do
		Inst.fire(inst, "InputChanged", io)
		Inst.fire(inst, if delta > 0 then "MouseWheelForward" else "MouseWheelBackward", x, ay)
	end
	-- 가장 위의 ScrollingFrame을 굴린다
	local _, _, hits = pick(x, y)
	for _, e in hits do
		if e.st.class == "ScrollingFrame" and P(e.st, "ScrollingEnabled") then
			local cp = P(e.st, "CanvasPosition")
			local maxY = math.max(0, (e.st.canvasH or e.st.ah) - e.st.ah)
			e.st.self.CanvasPosition = V2(cp.X, math.clamp(cp.Y - delta * 40, 0, maxY))
			break
		end
	end
	Inst.fire(uis(), "InputChanged", io, target ~= nil)
	Sched.flush()
end

-- ---------- 손가락 ----------
function Input.touchBegin(id: any, x: number, y: number)
	if Input.touches[id] then
		raise("harness.touchBegin: 손가락 " .. tostring(id) .. " 는 이미 닿아 있다")
	end
	local ay = y - R.opts.insetTop
	local io = newInput("Touch", nil, "Begin", x, ay)
	setLastType("Touch")
	local over, target = pick(x, y)
	Input.touches[id] = { input = io, target = target, x = x, y = y, over = over }
	if Input.focused and target ~= Input.focused then
		releaseFocus(Input.focused, false, io)
	end
	for _, inst in over do
		Inst.fire(inst, "InputBegan", io)
	end
	if target then
		if Inst.isA(target, "GuiButton") then
			Input.pressed["t" .. tostring(id)] = target
			setGuiState(target, "Press")
			Inst.fire(target, "MouseButton1Down", x, ay)
		elseif Inst.isA(target, "TextBox") and P(Inst.st(target), "TextEditable") then
			captureFocus(target)
		end
	end
	local sunk = target ~= nil
	if not sunk then
		sunk = dispatchActions(io)
	end
	Inst.fire(uis(), "TouchStarted", io, sunk)
	Inst.fire(uis(), "InputBegan", io, sunk)
	Sched.flush()
	return io
end

function Input.touchMove(id: any, x: number, y: number)
	local t = Input.touches[id]
	if not t then
		raise("harness.touchMove: 손가락 " .. tostring(id) .. " 는 닿아 있지 않다")
	end
	local ay = y - R.opts.insetTop
	local st = Inst.st(t.input)
	st.props.UserInputState = E("UserInputState", "Change")
	st.props.Delta = V3(x - t.x, y - t.y, 0)
	st.props.Position = V3(x, ay, 0)
	t.x, t.y = x, y
	-- 닿기 시작한 것들에 계속 알린다(끌기)
	for _, inst in t.over do
		Inst.fire(inst, "InputChanged", t.input)
	end
	local sunk = t.target ~= nil
	Inst.fire(uis(), "TouchMoved", t.input, sunk)
	Inst.fire(uis(), "InputChanged", t.input, sunk)
	Sched.flush()
	return t.input
end

function Input.touchEnd(id: any, x: number?, y: number?)
	local t = Input.touches[id]
	if not t then
		raise("harness.touchEnd: 손가락 " .. tostring(id) .. " 는 닿아 있지 않다")
	end
	if x and y and (x ~= t.x or y ~= t.y) then
		Input.touchMove(id, x, y)
	end
	x, y = t.x, t.y
	local ay = y - R.opts.insetTop
	Input.touches[id] = nil
	local st = Inst.st(t.input)
	st.props.UserInputState = E("UserInputState", "End")
	local over, target = pick(x, y)
	for _, inst in t.over do
		Inst.fire(inst, "InputEnded", t.input)
	end
	local key = "t" .. tostring(id)
	local was = Input.pressed[key]
	Input.pressed[key] = nil
	if target and Inst.isA(target, "GuiButton") then
		Inst.fire(target, "MouseButton1Up", x, ay)
		if was == target then
			Inst.fire(target, "MouseButton1Click")
			Inst.fire(target, "Activated", t.input, 1)
		end
	end
	if was then
		setGuiState(was, "Idle")
	end
	for _, inst in over do
		Inst.fire(inst, "TouchTap", { V2(x, ay) })
	end
	local sunk = t.target ~= nil
	if not sunk then
		sunk = dispatchActions(t.input)
	end
	Inst.fire(uis(), "TouchEnded", t.input, sunk)
	Inst.fire(uis(), "InputEnded", t.input, sunk)
	Inst.fire(uis(), "TouchTap", { V2(x, ay) }, sunk)
	Sched.flush()
	return target
end

-- ---------- 글 쓰기 ----------
function Input.typeText(text: string)
	local box = Input.focused
	if not box then
		raise("harness.typeText: 글을 쓰고 있는 TextBox가 없다(먼저 그 칸을 누르거나 CaptureFocus)")
	end
	box.Text = box.Text .. text
	Sched.flush()
end

-- ---------- 기기 갈래 ----------
function Input.setDevice(opts: { [string]: any })
	local u = uis()
	for k, v in opts do
		if k == "touch" then
			Inst.setRaw(u, "TouchEnabled", v == true)
		elseif k == "keyboard" then
			Inst.setRaw(u, "KeyboardEnabled", v == true)
		elseif k == "mouse" then
			Inst.setRaw(u, "MouseEnabled", v == true)
		elseif k == "gamepad" then
			Inst.setRaw(u, "GamepadEnabled", v == true)
		elseif k == "preferred" then
			local item = E("PreferredInput", v)
			if not item then
				raise('harness.setDevice: preferred는 "Touch" · "KeyboardAndMouse" · "Gamepad" 가운데 하나여야 한다')
			end
			Input.forcedPreferred = true
			Inst.setRaw(u, "PreferredInput", item)
		else
			raise("harness.setDevice: 모르는 열쇠 " .. tostring(k) .. " (touch · keyboard · mouse · gamepad · preferred)")
		end
	end
	Sched.flush()
end

function Input.windowFocus(focused: boolean)
	Inst.fire(uis(), if focused then "WindowFocused" else "WindowFocusReleased")
	Sched.flush()
end

function Input.menu(open: boolean)
	local gs = Services.get("GuiService")
	Inst.st(gs).menuOpen = open
	Inst.fire(gs, if open then "MenuOpened" else "MenuClosed")
	Sched.flush()
end

return Input
