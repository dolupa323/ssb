--!strict
-- 견본 화면 틀: 게임 세계(384x216 도트)와 화면 글씨 층(576x324 점)을 UIScale 하나씩으로 화면에 맞춘다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.shared.Config)

local Stage = {}
Stage.scale = 1 -- 게임 세계의 배율
Stage.uiScale = 1 -- 글씨 층의 배율
Stage.UI_W, Stage.UI_H = 576, 324

function Stage.scalesFor(w: number, h: number): (number, number)
	local fit = math.min(w / Config.VIEW_W, h / Config.VIEW_H)
	local s = if fit >= 2 then math.floor(fit) else fit
	return s, s * Config.VIEW_W / Stage.UI_W
end

function Stage.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Sample"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	back.BorderSizePixel = 0
	back.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Parent = gui

	local view = Instance.new("Frame")
	view.Name = "View"
	view.Size = UDim2.fromOffset(Config.VIEW_W, Config.VIEW_H)
	view.BackgroundColor3 = Color3.fromRGB(86, 110, 96)
	view.BorderSizePixel = 0
	view.Parent = holder
	local viewScale = Instance.new("UIScale")
	viewScale.Parent = view

	local ui = Instance.new("Frame")
	ui.Name = "Ui"
	ui.Size = UDim2.fromOffset(Stage.UI_W, Stage.UI_H)
	ui.BackgroundTransparency = 1
	ui.BorderSizePixel = 0
	ui.ZIndex = 10
	ui.Parent = holder
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = ui

	local function fit()
		local real = gui.AbsoluteSize
		local s, us = Stage.scalesFor(real.X, real.Y)
		Stage.scale, Stage.uiScale = s, us
		viewScale.Scale = s
		uiScale.Scale = us
		local hw, hh = math.floor(Config.VIEW_W * s + 0.5), math.floor(Config.VIEW_H * s + 0.5)
		holder.Size = UDim2.fromOffset(hw, hh)
		holder.Position = UDim2.fromOffset(math.floor((real.X - hw) / 2), math.floor((real.Y - hh) / 2))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	Stage.gui, Stage.view, Stage.ui, Stage.holder = gui, view, ui, holder
	return Stage
end

return Stage
