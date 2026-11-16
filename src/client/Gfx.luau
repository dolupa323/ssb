-- 세계 그리기 (원본 commute-survival/js/gfx.js의 GFX를 옮긴 것)
--  캔버스에 매 장면 그리던 것을 GuiObject로 옮겼다: 그림은 구운 판에서 잘라 쓰고(Art), 선 · 원 · 글은 Frame · UICorner · UIStroke · TextLabel로 만든다.
--  세계 → 화면: 틀 하나(Root)에 UIScale(= 배율)을 걸고, 그 안의 Cam을 카메라만큼 민다. 물건의 자리 · 크기는 Scale로 준다(gfx/Draw).
--  나눠 둔 곳: gfx/Draw(풀) · gfx/Parts(입자 · 이벤트) · gfx/World(바닥) · gfx/Ground(바닥 효과 · 줍는 것) · gfx/Actors(캐릭터) · gfx/Weapons(무기 · 효과)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(script.Parent.Art)
local Sim = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("Sim")) :: any
local D = require(script.Parent.gfx.Draw) :: any

local floor, sqrt, sin, min, max, pow = math.floor, math.sqrt, math.sin, math.min, math.max, math.pow
local band, rshift, lshift, bxor = bit32.band, bit32.rshift, bit32.lshift, bit32.bxor
local rnd = math.random
local U = D.U
local INV = 1 / U

-- ---------- 원본의 hash · srand (바닥의 쓰레기 · 낙엽 자리, 번개의 꺾임이 원본과 같게) ----------
local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	return band(al * b + lshift(band(ah * b, 0xFFFF), 16), 0xFFFFFFFF)
end
local function hash(x: number, y: number): number
	local h = bxor(imul(band(x, 0xFFFFFFFF), 73856093), imul(band(y, 0xFFFFFFFF), 19349663))
	return imul(bxor(h, rshift(h, 13)), 1274126177)
end
local function srand(seed: number): () -> number
	local s = band(seed, 0xFFFFFFFF)
	return function(): number
		s = band(imul(s, 1664525) + 1013904223, 0xFFFFFFFF)
		return s / 4294967296
	end
end

-- ---------- 함께 쓰는 상태 ----------
local G = {
	D = D, Art = Art, Sim = Sim,
	hash = hash, srand = srand,
	chars = Art.atlas.chars,
	TS = 1.18, -- 원본의 글자 크기(px) → TextSize (Roblox의 TextSize는 줄 높이라 같은 수면 글자가 작다)
	gl = 1.4, -- 빛(더하기 섞기 + 번짐)을 보통 섞기로 옮길 때 투명도에 곱하는 값 (장소의 바닥 밝기에 따라 바뀐다 — setLight)
	time = 0, W = 1, H = 1, zoom = 1, zf = 1,
	cam = { x = 0, y = Sim.LANE_GAP / 2, init = false },
	cx = 0, cy = 0, vw = 1, vh = 1, x0 = 0, y0 = 0, x1 = 1, y1 = 1,
	fxLv = 2, shakeOn = true, bloomOn = true,
	shakeAmt = 0, flash = 0, hurtFlash = 0, healFlash = 0, lastPick = 0, wipeT = 0, S_rage = 0,
	zoomKick = 0, stopT = 0, speedT = 0, bagFling = 0,
	parts = {}, nums = {}, fxs = {}, corpses = {}, ghosts = {}, decals = {}, says = {}, pk = { t = 0, x = 0, y = 0 },
	L = {} :: { [string]: any },
}

local Gfx = {}
local inited, prepared = false, false
local worldFrame: Frame, overlayFrame: Frame
local root: Frame, uiScale: UIScale, camFrame: Frame
local Parts, World, Ground, Actors, Weapons
local lastScale, lastCamX, lastCamY = -1, 0 / 0, 0 / 0
local ov = {} :: { [string]: any }
local C_DUSK = D.rgb("10,14,34")
local stats = { ms = 0, writes = 0, visible = 0 }

-- 층의 차례(아래 → 위). 원본 render가 그리는 차례와 같다
local LAYERS = {
	"f1", -- 바닥 무늬 아래(열차 안: 터널 · 창밖 승강장)
	"tile", -- 바닥 무늬
	"f3", -- 열린 문의 빛
	"f4", -- 깔아 둔 배경
	"f5", -- 개찰구 날개 / 위로 가는 발판
	"f6", -- 아래로 가는 발판
	"f7", -- 깔아 둔 배경(위)
	"f8", -- 선로 신호 점
	"f9", -- 진입 경고 / 열차 벽 · 문
	"ground", -- 바닥 효과
	"pick", -- 원두 · 아이템
	"ent", -- 캐릭터 (y 순서)
	"corpse", -- 쓰러지는 모습
	"over", -- 열차 안: 앞줄에 앉은 사람 · 봉
	"overD", -- 열차 안: 손잡이
	"say", -- 보스 말풍선
	"veh", -- 버스 · 열차
	"dusk", -- 해 질 녘 덧칠
	"fx", -- 무기 · 효과 · 입자
	"num", -- 숫자
	"ind", -- 화면 밖 표시
}

local function resize()
	local size = worldFrame.AbsoluteSize
	local W, H = max(1, size.X), max(1, size.Y)
	if W ~= G.W or H ~= G.H then
		G.W, G.H = W, H
		G.zoom = max(0.82, min(1.5, min(W, H) / 520))
	end
end

-- 장소의 바닥 밝기에 맞춰 「빛」의 흰 정도와 진하기를 정한다.
--  원본의 빛은 더하기 섞기라서 밝은 바닥(밝기 200쯤)에서는 조금만 얹어도 하얗게 뜨고, 어두운 바닥에서는 제 색이 난다
local lightZone, lightBloom = -1, nil :: boolean?
local function setLight(zone: number)
	if zone == lightZone and lightBloom == G.bloomOn then
		return
	end
	lightZone, lightBloom = zone, G.bloomOn
	local Z = Sim.ZONES[zone + 1]
	local B = (Z.floor[1] + Z.floor[2] + Z.floor[3]) / 3
	if Z.kind == "esc" then
		B = 95 -- 에스컬레이터의 발판은 어둡다
	end
	local t = math.clamp((B - 90) / 110, 0, 1)
	D.setLite(0.35 + 0.25 * t)
	D.glowName = if B >= 170 then "prim/glow2" else "fx/glow"
	G.gl = (1.2 + 1.2 * t) * (if G.bloomOn then 1 else 0.75)
end

function Gfx.init(world: Frame, overlay: Frame)
	if inited then
		return
	end
	inited = true
	worldFrame, overlayFrame = world, overlay
	root = Instance.new("Frame")
	root.Name = "GfxRoot"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(U, U)
	uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	camFrame = Instance.new("Frame")
	camFrame.Name = "Cam"
	camFrame.BackgroundTransparency = 1
	camFrame.BorderSizePixel = 0
	camFrame.Size = UDim2.fromScale(1, 1)
	camFrame.Parent = root
	for i, name in LAYERS do
		G.L[name] = D.layer(camFrame, name, i)
	end
	root.Parent = worldFrame

	-- 화면에 붙는 것: 가장자리 어둠 · 장면 바뀜 · 붉은 덧칠 · 번쩍임 · 집중선
	local function full(class: string, name: string, z: number): any
		local g = Instance.new(class) :: any
		g.Name = name
		g.BackgroundTransparency = 1
		g.BorderSizePixel = 0
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = z
		g.Visible = false
		g.Parent = overlayFrame
		return g
	end
	ov.amb = { g = full("ImageLabel", "Ambient", 1), a = -1, on = false, img = "ui/vig/amb" }
	ov.wipe = { g = full("Frame", "Wipe", 2), a = -1, on = false, col = Color3.fromRGB(8, 11, 13) }
	ov.rage = { g = full("Frame", "Rage", 3), a = -1, on = false, col = Color3.fromRGB(229, 40, 45) }
	ov.hurt = { g = full("ImageLabel", "Hurt", 4), a = -1, on = false, img = "ui/vig/hurt" }
	ov.heal = { g = full("ImageLabel", "Heal", 5), a = -1, on = false, img = "ui/vig/heal" }
	ov.flash = { g = full("Frame", "Flash", 6), a = -1, on = false, col = Color3.new(1, 1, 1) }
	ov.speed = { g = full("ImageLabel", "Speed", 7), a = -1, on = false, img = "ui/speedlines" }
	for _, o in ov do
		if o.col then
			o.g.BackgroundColor3 = o.col
		end
	end

	Parts = require(script.Parent.gfx.Parts)(G)
	Actors = require(script.Parent.gfx.Actors)(G)
	World = require(script.Parent.gfx.World)(G)
	Ground = require(script.Parent.gfx.Ground)(G)
	Weapons = require(script.Parent.gfx.Weapons)(G, Parts)

	resize()
	worldFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
end

-- 화면에 붙는 것 하나의 투명도 (0이면 숨긴다)
local function setOv(o, a: number)
	a = if a <= 0.004 then 0 else floor(min(1, a) * 64 + 0.5) / 64
	if o.a == a then
		return
	end
	o.a = a
	local on = a > 0
	if o.on ~= on then
		o.on = on
		o.g.Visible = on
	end
	if on then
		if o.img then
			o.g.ImageTransparency = 1 - a
		else
			o.g.BackgroundTransparency = 1 - a
		end
	end
end

local function prepare()
	prepared = true
	for _, o in ov do
		if o.img then
			Art.set(o.g, o.img)
		end
	end
end

function Gfx.reset()
	table.clear(G.parts)
	table.clear(G.nums)
	table.clear(G.fxs)
	table.clear(G.corpses)
	table.clear(G.ghosts)
	table.clear(G.decals)
	G.shakeAmt, G.flash, G.hurtFlash, G.healFlash, G.zoomKick, G.stopT, G.speedT, G.wipeT = 0, 0, 0, 0, 0, 0, 0, 0
	G.cam.init = false
	if World then
		World.reset()
	end
end

function Gfx.view(): { w: number, h: number }
	local zm = G.zoom * G.zf
	return { w = G.W / zm, h = G.H / zm }
end

function Gfx.size(): { W: number, H: number }
	return { W = G.W, H = G.H }
end

function Gfx.shake(a: number)
	G.shakeAmt = max(G.shakeAmt, a)
end

function Gfx.frozen(): boolean
	return G.stopT > 0
end

function Gfx.opts(o: { fx: number?, shake: any, bloom: any })
	if o.fx ~= nil then
		G.fxLv = o.fx
	end
	if o.shake ~= nil then
		G.shakeOn = o.shake ~= 0 and o.shake ~= false
	end
	if o.bloom ~= nil then
		G.bloomOn = o.bloom ~= 0 and o.bloom ~= false
	end
end

-- 도착했을 때 뿌리는 색종이
local CONFETTI = { "0,168,77", "255,201,40", "229,72,77", "255,255,255", "53,183,255" }
function Gfx.celebrate()
	if not Parts then
		return
	end
	local vw, vh = G.W / G.zoom, G.H / G.zoom
	for i = 0, 149 do
		Parts.P({
			k = "paper", x = G.cam.x + (rnd() - 0.5) * vw, y = G.cam.y - vh / 2 - rnd() * vh * 0.6, vx = (rnd() - 0.5) * 160, vy = 120 + rnd() * 220, g = 60,
			life = 2.6 + rnd() * 1.6, size = 6 + rnd() * 4, col = CONFETTI[i % 5 + 1], drag = 0.5,
		})
	end
end

-- 아이콘 그림의 이름 (Art.set에 넣는다). evo = 진화 · 조합 카드에 뜰 때(별 붙음)
function Gfx.icon(key: string, evo: boolean?): string
	local name = "icon/" .. tostring(key)
	if evo and Art.has(name .. "/evo") then
		return name .. "/evo"
	end
	if Art.has(name) then
		return name
	end
	return "icon/heal"
end

local DYNAMIC = { "ground", "pick", "ent", "corpse", "say", "veh", "dusk", "fx", "num", "ind" }

local function render(S, o)
	local L = G.L
	local p = S.p
	local dt = o.dt or 0
	local adt = if o.running or o.fx then dt else 0
	G.time += dt
	local time = G.time
	G.S_rage = S.rage or 0
	setLight(S.zone)
	Parts.consume(S)
	Parts.step(adt, S)

	-- 카메라
	resize()
	local W, H = G.W, G.H
	local inTrain = S.zk == "train"
	G.zf = if inTrain and W < H then 0.88 else 1
	local zm = G.zoom * G.zf
	local vw, vh = W / zm, H / zm
	local play = if o.mode == "play" then 1 else 0
	local tx = p.x + (o.offX or 0) * vw + p.fx * 18 * play
	local ty = if inTrain then 0 else p.y + (o.offY or 0) * vh + p.fy * 18 * play
	local cam = G.cam
	if not cam.init or sqrt((tx - cam.x) ^ 2 + (ty - cam.y) ^ 2) > 500 then
		cam.x, cam.y, cam.init = tx, ty, true
	else
		local f = min(1, dt * 9)
		cam.x += (tx - cam.x) * f
		cam.y += (ty - cam.y) * f
	end
	local sx, sy = 0, 0
	if G.shakeAmt > 0.4 and G.shakeOn then
		sx, sy = (rnd() - 0.5) * G.shakeAmt, (rnd() - 0.5) * G.shakeAmt
	end
	G.zoomKick *= pow(0.004, dt)
	G.speedT = max(0, G.speedT - dt * 3.2)
	G.stopT = max(0, G.stopT - dt)
	-- 배율: Root의 크기(U × 배율)가 정수 픽셀이 되게 맞춘다
	local k = floor(U * zm * (1 + G.zoomKick) + 0.5) / U
	-- 카메라 자리는 화면 픽셀에 맞춘다(바닥의 글 · 무늬가 떨리지 않게)
	local cx, cy = floor((cam.x + sx) * k + 0.5) / k, floor((cam.y + sy) * k + 0.5) / k
	if lastScale ~= k then
		lastScale = k
		uiScale.Scale = k
		D.writes += 1
	end
	if lastCamX ~= cx or lastCamY ~= cy then
		lastCamX, lastCamY = cx, cy
		camFrame.Position = UDim2.fromScale(-cx * INV, -cy * INV)
		D.writes += 1
	end
	G.cx, G.cy, G.vw, G.vh = cx, cy, vw, vh
	G.x0, G.y0, G.x1, G.y1 = cx - vw / 2, cy - vh / 2, cx + vw / 2, cy + vh / 2
	D.vx0, D.vy0, D.vx1, D.vy1 = G.x0, G.y0, G.x1, G.y1

	for _, n in DYNAMIC do
		D.begin(L[n])
	end
	World.draw(S, adt)
	Ground.draw(S)
	Actors.draw(S)
	Actors.drawCorpses()
	Actors.drawSays(S)
	Actors.drawVehicle(S)
	-- 빛이 밝은 바닥 위에서도 보이게 살짝 어둡게 덮는다
	if G.bloomOn then
		D.rect(L.dusk, 1, cx - vw / 2 - 20, cy - vh / 2 - 20, vw + 40, vh + 40, C_DUSK, 0.1)
	end
	Weapons.draw(S)
	Parts.drawNums()
	if play == 1 then
		Actors.drawIndicators(S)
	end
	for _, n in DYNAMIC do
		D.finish(L[n])
	end

	-- 화면에 붙는 것
	local st = Sim.ZONES[S.zone + 1]
	if ov.amb.tint ~= st.tint then
		ov.amb.tint = st.tint
		ov.amb.g.ImageColor3 = D.rgb(st.tint)
	end
	setOv(ov.amb, st.amb)
	if G.wipeT > 0 then
		G.wipeT = max(0, G.wipeT - dt)
	end
	setOv(ov.wipe, min(1, G.wipeT / 0.45))
	if play == 1 then
		setOv(ov.rage, if G.S_rage > 0 then 0.04 + 0.02 * min(3, G.S_rage) + 0.03 * sin(time * 3) else 0)
		local low = if p.hp / p.maxhp < 0.3 then 0.22 + 0.12 * sin(time * 7) else 0
		setOv(ov.hurt, max(low, G.hurtFlash * 0.8))
		setOv(ov.heal, G.healFlash * 0.5)
		setOv(ov.flash, min(0.6, G.flash))
		setOv(ov.speed, G.speedT)
	else
		setOv(ov.rage, 0)
		setOv(ov.hurt, 0)
		setOv(ov.heal, 0)
		setOv(ov.flash, 0)
		setOv(ov.speed, 0)
	end
end

-- 한 장면을 그린다. o = { mode = "menu"|"play", dt, running, fx, offX, offY }. S.ev는 여기서 읽고 비운다
local errCount = 0
function Gfx.render(S, o)
	if not inited or not Art.ready then
		return
	end
	if not prepared then
		prepare()
	end
	local w0 = D.writes
	local t0 = os.clock()
	local ok, err = xpcall(render, debug.traceback, S, o)
	if not ok then
		-- 한 번 틀어진 장면이 다음 장면까지 망치지 않게: 풀의 세던 자리를 되돌린다
		for _, n in DYNAMIC do
			D.finish(G.L[n])
		end
		errCount += 1
		if errCount <= 3 then
			warn("[Gfx] 그리다가 오류: " .. tostring(err))
		end
		Gfx.lastError = err
	end
	stats.ms = (os.clock() - t0) * 1000
	stats.writes = D.writes - w0
end

-- 잴 때 쓰는 숫자: 이번 장면에 쓴 속성 수 · 보이는 물건 수 · 지금까지 만든 물건 수
function Gfx.stats()
	return {
		writes = stats.writes, ms = stats.ms, visible = D.visible() + (if Actors then Actors.active * (if Actors.shadows then 2 else 1) + 4 else 0), created = D.created,
		enemies = if Actors then Actors.active else 0, parts = #G.parts, errors = errCount,
	}
end

Gfx.G = G -- 시험용

return Gfx
