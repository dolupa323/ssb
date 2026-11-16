--!strict
-- 화면의 틀. 층은 아래부터:
--   World    게임 세계(Gfx가 그린다 · 원본의 <canvas>)
--   Overlay  화면에 붙는 이펙트(Gfx)
--   Pad      세계를 누르고 끄는 손가락 · 마우스를 받는 투명한 판(원본에서 canvas가 받던 pointer 이벤트)
--   Ui       HUD · 메뉴 · 카드 … (UIScale 하나로 배율을 건다 — 그 아래는 모두 「CSS px」 좌표)
--   Top      불러오는 화면
-- 배율: 원본은 CSS px로 짜여 있고 화면 폭에 따라 배치가 바뀐다(980px 이상 = 메뉴가 왼쪽, 640px 이하 = 폰 배치).
--  1920x1080까지는 화면의 한 점 = CSS 1px(원본과 같은 크기 · 같은 배치). 그보다 큰 화면(4K 등)은 1920x1080에 맞춘 것과 같게 키운다.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local Stage = {}
Stage.scale = 1 -- 화면 픽셀 / CSS px
Stage.w, Stage.h = 1280, 720 -- 화면 틀의 크기(CSS px)
Stage.wide = true -- 폭 980px 이상(원본 @media (min-width:980px))
Stage.phone = false -- 폭 640px 이하(원본 @media (max-width:640px))
Stage.insetTop = 0 -- Roblox 윗줄의 높이(CSS px)
Stage.insetLeft = 0 -- Roblox 기본 단추(메뉴 · 채팅)가 왼쪽 위에서 차지하는 폭(CSS px)
Stage.REF_W, Stage.REF_H = 1920, 1080
Stage.CORE_W = 64 -- Roblox가 단추의 폭을 알려 주지 않을 때 쓰는 값(왼쪽 12 + 44px 메뉴 단추 + 8) [제가 정한 것]

local resized = {} :: { () -> () }

function Stage.scaleFor(w: number, h: number): number
	return math.max(1, math.min(w / Stage.REF_W, h / Stage.REF_H))
end

-- Roblox가 기본으로 띄우는 것 가운데 2D 게임이 쓰지 않는 것을 끈다. 혼자 하는 게임이라 채팅도 끈다(왼쪽 위에 Roblox 메뉴 단추 하나만 남는다)
local function coreOff()
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				for _, kind in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Chat } do
					StarterGui:SetCoreGuiEnabled(kind, false)
				end
			end)
			if ok then
				break
			end
			task.wait(0.5) -- 시작 직후에는 아직 준비되지 않았을 수 있다
		end
	end)
	pcall(function()
		GuiService.TouchControlsEnabled = false -- 기본 조이스틱 · 뛰기 단추
	end)
	pcall(function()
		Players.LocalPlayer:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end)
end

local function full(name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	return f
end

function Stage.init()
	coreOff()

	local gui = Instance.new("ScreenGui")
	gui.Name = "Ssb"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local world = full("World", 1)
	world.BackgroundTransparency = 0
	world.BackgroundColor3 = Color3.fromRGB(20, 25, 28) -- 원본 body의 바탕 #14191c
	world.ClipsDescendants = true
	world.Parent = gui

	local overlay = full("Overlay", 2)
	overlay.ClipsDescendants = true
	overlay.Parent = gui

	local pad = Instance.new("TextButton")
	pad.Name = "Pad"
	pad.Text = ""
	pad.AutoButtonColor = false
	pad.Size = UDim2.fromScale(1, 1)
	pad.BackgroundTransparency = 1
	pad.BorderSizePixel = 0
	pad.ZIndex = 3
	pad.Parent = gui

	local ui = Instance.new("Frame")
	ui.Name = "Ui"
	ui.BackgroundTransparency = 1
	ui.BorderSizePixel = 0
	ui.ZIndex = 10
	ui.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = ui

	local top = full("Top", 50)
	top.Parent = gui

	Stage.gui, Stage.world, Stage.overlay, Stage.pad, Stage.ui, Stage.top = gui, world, overlay, pad, ui, top

	local function fit()
		local real = gui.AbsoluteSize
		if real.X < 1 or real.Y < 1 then
			return
		end
		local s = Stage.scaleFor(real.X, real.Y)
		local w, h = real.X / s, real.Y / s
		local it, il = 0, 0
		local okInset, inset = pcall(function()
			return GuiService:GetGuiInset()
		end)
		if okInset then
			it = inset.Y / s
		end
		-- 왼쪽 위 단추가 끝나는 자리: TopbarInset이 알려 주면 그것, 아니면 어림
		local okBar, bar = pcall(function()
			return GuiService.TopbarInset
		end)
		if okBar and typeof(bar) == "Rect" and (bar :: any).Min.X > 0 then
			il = (bar :: any).Min.X / s
		elseif it > 0 then
			il = Stage.CORE_W / s
		end
		local changed = s ~= Stage.scale or w ~= Stage.w or h ~= Stage.h or it ~= Stage.insetTop or il ~= Stage.insetLeft
		Stage.scale, Stage.w, Stage.h, Stage.insetTop, Stage.insetLeft = s, w, h, it, il
		Stage.wide = w >= 980
		Stage.phone = w <= 640
		uiScale.Scale = s
		ui.Size = UDim2.fromOffset(w, h)
		if changed then
			for _, fn in resized do
				fn()
			end
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)
	end)
	fit()
	return Stage
end

-- 화면 크기 · 배치가 바뀌면 부른다
function Stage.onResize(fn: () -> ())
	table.insert(resized, fn)
end

-- 입력의 자리(InputObject.Position) → 화면 틀의 좌표(CSS px)
function Stage.toUi(pos: Vector3 | Vector2): (number, number)
	local origin = Stage.ui.AbsolutePosition
	return (pos.X - origin.X) / Stage.scale, (pos.Y - origin.Y) / Stage.scale
end

-- 손가락으로 하는 화면인가
function Stage.touchLike(): boolean
	local ok, pref = pcall(function()
		return UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end)
	if ok then
		return pref
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return Stage
