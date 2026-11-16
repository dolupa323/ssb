-- (mock 확인용) 달의 계승자의 stage · canvas · sprite를 베껴 와 그대로 돌려 본다 — mock이 실제 화면 코드의 API를 받아 주는지 본다.
local Stage = require(script.Parent.lune.stage)
local Canvas = require(script.Parent.lune.canvas)
local Sprite = require(script.Parent.lune.sprite)

local stage = Stage.init()
print("Stage.init:", stage.scale, stage.uiScale, stage.uiW, stage.uiH, "insetTop", stage.insetTop)

local world = Stage.group(stage.view, "World", 1)
local back, front = Canvas.attach(world, 2, 8)
back:begin(0, 0)
back:style(0xff3030)
back:rect(10, 10, 60, 40)
back:alpha(0.5)
back:style(0x30ff30)
back:rect(40, 30, 60, 40)
back:present()
front:begin(0, 0)
front:style(0xffffff)
front:rect(200, 100, 8, 8)
front:present()

local a = Sprite.new(world, "hero", 5)
a:set("idle", 1, 120, 160, 1)
local b = Sprite.new(world, "hero", 5)
b:set("walk", 2, 180, 160, -1)
local pet = Sprite.new(world, "pet", 5)
pet:set("idle", 1, 240, 160, 1)
a:setLook({ point = "red", robe = "blue" })
a:set("idle", 2, 120, 160, 1)
print("Sprite.frameAt:", Sprite.frameAt(a.char, "idle", 0.3), Sprite.frameAt(a.char, "walk", 0.3, true))

local hud = Stage.place(stage.ui, "Hud", "tl", 10, 10, 200, 40)
hud.BackgroundTransparency = 0.3
local br = Stage.placeRect(stage.ui, "Corner", { at = "br", x = 860, y = 480, w = 90, h = 50 })
br.BackgroundTransparency = 0.3
br.BackgroundColor3 = Color3.fromRGB(200, 120, 40)
local unbind = Stage.onResize(function(scaled)
	print("onResize:", scaled, Stage.scale, Stage.uiScale)
end)
local _ = unbind
print("touchLike:", Stage.touchLike())
