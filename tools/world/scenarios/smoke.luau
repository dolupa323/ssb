-- 첫 확인: 판을 만들고, 봇이 하는 판을 몇 초 그려 본다
local h = harness
local RS = game:GetService("ReplicatedStorage")
local Sim = h.require(RS.shared.Sim)
local client = h.player().PlayerScripts.client
local Art = h.require(client.Art)
local Gfx = h.require(client.Gfx)

local gui = Instance.new("ScreenGui")
gui.Name = "World"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local function full(name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = gui
	return f
end
local world, overlay = full("WorldLayer", 1), full("Overlay", 2)
gui.Parent = h.playerGui()

h.asClient(function()
	Art.init()
end)
h.waitFor(function()
	return Art.ready
end, 20, "Art.ready")
print("판 준비 끝 · 실패", #Art.failed)
h.asClient(function()
	Gfx.init(world, overlay)
end)
h.step(1)

local host = { sfx = function() end, banner = function() end, shake = function(a) Gfx.shake(a) end, levelUp = function() end, finish = function() end }
local sim = Sim.create(host, { diff = 1, autoPick = function(ch) return ch[1] end, build = { weapons = { card = 3, backpack = 2, battery = 2, coffee = 1 }, passives = {} } })
local S = sim.S
local function frame(dt)
	local b = sim.bot()
	S.input = b
	if b.dash then sim.dash() end
	if not Gfx.frozen() then
		sim.update(dt, Gfx.view())
	end
	h.asClient(function()
		Gfx.render(S, { mode = "play", dt = dt, running = true })
	end)
	h.step(1)
end
for i = 1, 300 do
	frame(1 / 60)
end
local st = Gfx.stats()
print(("t=%.1f 적 %d · 보이는 것 %d · 만든 것 %d · 이번 장면 쓰기 %d · 오류 %d"):format(S.t, #S.enemies, st.visible, st.created, st.writes, st.errors))
if Gfx.lastError then print(Gfx.lastError) end
h.shot("smoke.png")
