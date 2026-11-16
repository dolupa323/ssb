-- 시험용 대역(진짜 src/client/Gfx.luau가 아니다). UI 시나리오가 화면 담당의 모듈 없이도 돌게 한다.
--  세계는 바닥 색 + 점(플레이어 · 적)으로만 그리고, 불린 것을 Gfx.calls에 적어 시나리오가 확인하게 한다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sim = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("Sim"))

local Gfx = {}
Gfx.isStub = true
Gfx.calls = { init = 0, reset = 0, render = 0, shake = {}, celebrate = 0, opts = {} }
Gfx.last = nil :: any -- 마지막 render의 o
Gfx.freeze = false -- 시나리오가 켜면 frozen() = true

local world: Frame? = nil
local floor: Frame? = nil
local dots = {} :: { Frame }
local hero: Frame? = nil

local function zoom(): number
	local s = (world :: Frame).AbsoluteSize
	return math.clamp(math.min(s.X, s.Y) / 520, 0.82, 1.5)
end

function Gfx.init(worldFrame: Frame, _overlayFrame: Frame)
	Gfx.calls.init += 1
	world = worldFrame
	local f = Instance.new("Frame")
	f.Name = "StubFloor"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(198, 192, 182)
	f.Parent = worldFrame
	floor = f
	local h = Instance.new("Frame")
	h.Name = "StubHero"
	h.AnchorPoint = Vector2.new(0.5, 0.5)
	h.Size = UDim2.fromOffset(22, 22)
	h.BorderSizePixel = 0
	h.BackgroundColor3 = Color3.fromRGB(0, 168, 77)
	h.ZIndex = 3
	h.Parent = worldFrame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = h
	hero = h
end

function Gfx.reset()
	Gfx.calls.reset += 1
end

function Gfx.size()
	local s = (world :: Frame).AbsoluteSize
	return { W = s.X, H = s.Y }
end

function Gfx.view()
	local s = (world :: Frame).AbsoluteSize
	local z = zoom()
	return { w = s.X / z, h = s.Y / z }
end

function Gfx.render(S: any, o: any)
	Gfx.calls.render += 1
	Gfx.last = o
	local s = (world :: Frame).AbsoluteSize
	local z = zoom()
	local zone = Sim.ZONES[S.zone + 1]
	local fl = zone.floor
	;(floor :: Frame).BackgroundColor3 = Color3.fromRGB(fl[1], fl[2], fl[3])
	local cx, cy = s.X * (0.5 - (o.offX or 0)), s.Y * (0.5 - (o.offY or 0))
	;(hero :: Frame).Position = UDim2.fromOffset(cx, cy)
	local n = 0
	for _, e in S.enemies do
		if n >= 80 then
			break
		end
		local x, y = cx + (e.x - S.p.x) * z, cy + (e.y - S.p.y) * z
		if x > -20 and y > -20 and x < s.X + 20 and y < s.Y + 20 then
			n += 1
			local d = dots[n]
			if not d then
				d = Instance.new("Frame")
				d.Name = "StubFoe"
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.BorderSizePixel = 0
				d.ZIndex = 2
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(1, 0)
				c.Parent = d
				d.Parent = world
				dots[n] = d
			end
			local r = e.r * z * 2
			d.Size = UDim2.fromOffset(r, r)
			d.Position = UDim2.fromOffset(x, y)
			d.BackgroundColor3 = if e.boss then Color3.fromRGB(176, 59, 214) else Color3.fromRGB(90, 100, 110)
			d.Visible = true
		end
	end
	for i = n + 1, #dots do
		dots[i].Visible = false
	end
	table.clear(S.ev) -- 화면이 읽고 비운다(SIM_API 3절)
end

function Gfx.shake(a: number)
	table.insert(Gfx.calls.shake, a)
end

function Gfx.celebrate()
	Gfx.calls.celebrate += 1
end

function Gfx.frozen(): boolean
	return Gfx.freeze
end

function Gfx.opts(o: any)
	for k, v in o do
		Gfx.calls.opts[k] = v
	end
end

-- 아이콘 그림 이름 (원본 GFX.icon(key, evo))
function Gfx.icon(key: string, evo: any): string
	if evo and Sim.WEAPONS[key] or evo and Sim.FUSIONS[key] then
		return "icon/" .. key .. "/evo"
	end
	return "icon/" .. key
end

return Gfx
