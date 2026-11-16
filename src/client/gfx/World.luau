-- 바닥과 장소마다의 배경 (원본 gfx.js의 drawPlatform · drawStreet · drawGates · drawEsc · drawOffice · drawTrainIn · drawTrainOver)
--  · 움직이지 않는 것은 「보이는 네모 + 여유」만큼 한 번 깔아 두고, 카메라가 그 밖으로 나갈 때만 다시 깐다.
--  · 움직이는 것(진입 경고 · 개찰구 날개 · 열차 문 · 손잡이)은 매 장면 그린다.
--  · 에스컬레이터 발판은 깔아 둔 층을 통째로 민다.
return function(G)
	local D, Sim, Art = G.D, G.Sim, G.Art
	local L = G.L
	local rgb = D.rgb
	local floor, ceil, sin, abs, min, max, fmod = math.floor, math.ceil, math.sin, math.abs, math.min, math.max, math.fmod
	local band, rshift, arshift = bit32.band, bit32.rshift, bit32.arshift
	local LANE_GAP, GATE_GAP, GATE_PER, GATE_HALF = Sim.LANE_GAP, Sim.GATE_GAP, Sim.GATE_PER, Sim.GATE_HALF
	local ESC_W, ESC_PUSH, AISLE, DOOR_PER, DOOR_OPEN = Sim.ESC_W, Sim.ESC_PUSH, Sim.AISLE, Sim.DOOR_PER, Sim.DOOR_OPEN
	local ZONES, STOPS = Sim.ZONES, Sim.STOPS
	local WALL, OUT = 118, 132
	local INV = 1 / D.U
	local M = 224 -- 깔아 두는 여유
	local hash = G.hash

	local W = {}
	W.trainV, W.trainScroll, W.platA, W.doorA = 900, 0, 0, 0

	local C_INK = rgb("#1f262b")
	local C_FLOORTXT = rgb("27,33,36")
	local C_OFFTXT = rgb("60,44,20")
	local C_GREEN = rgb("0,168,77")
	local C_YELLOW = rgb("255,201,40")
	local C_WARN = rgb("229,40,45")
	local C_LEDR = rgb("255,60,60")
	local C_LEDG = rgb("90,255,150")
	local WHITE = D.WHITE

	-- ---------- 바닥 무늬 (이어 붙이는 그림 한 장) ----------
	local tileClip = D.newFrame(L.tile.frame, "TileClip", 1)
	tileClip.ClipsDescendants = true
	tileClip.Visible = false
	local tileImg = Instance.new("ImageLabel")
	tileImg.Name = "Tile"
	tileImg.BackgroundTransparency = 1
	tileImg.BorderSizePixel = 0
	tileImg.ScaleType = Enum.ScaleType.Tile
	tileImg.Parent = tileClip
	D.created += 1
	local tile = { name = "", x = 0 / 0, y = 0, w = 0, h = 0, cy0 = 0, cy1 = 0, on = false }

	-- (x0..x1, y0..y1)을 덮게 바닥 무늬를 놓는다. clip0, clip1 = 세로로 잘라 보일 범위(열차 안)
	local function setTiles(name: string, x0: number, y0: number, x1: number, y1: number, clip0: number?, clip1: number?)
		local tx0, ty0 = floor(x0 / 512) * 512, floor(y0 / 512) * 512
		local cols, rows = ceil((x1 - tx0) / 512), ceil((y1 - ty0) / 512)
		local cy0, cy1 = clip0 or ty0, clip1 or (ty0 + rows * 512)
		if tile.name ~= name then
			tile.name = name
			Art.setWhole(tileImg, name)
		end
		if not tile.on then
			tile.on = true
			tileClip.Visible = true
		end
		if tile.x ~= tx0 or tile.y ~= ty0 or tile.w ~= cols or tile.h ~= rows or tile.cy0 ~= cy0 or tile.cy1 ~= cy1 then
			tile.x, tile.y, tile.w, tile.h, tile.cy0, tile.cy1 = tx0, ty0, cols, rows, cy0, cy1
			tileClip.Position = UDim2.fromScale(tx0 * INV, cy0 * INV)
			tileClip.Size = UDim2.fromScale(cols * 512 * INV, (cy1 - cy0) * INV)
			tileImg.Position = UDim2.fromOffset(0, ty0 - cy0)
			tileImg.Size = UDim2.fromOffset(cols * 512, rows * 512)
			tileImg.TileSize = UDim2.fromScale(1 / cols, 1 / rows)
			D.writes += 5
		end
	end
	local function hideTiles()
		if tile.on then
			tile.on = false
			tileClip.Visible = false
		end
	end

	-- ---------- 깔아 둔 범위 ----------
	local function newBuilt()
		return { ok = false, x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
	end
	local function inside(b, x0: number, y0: number, x1: number, y1: number): boolean
		return b.ok and x0 >= b.x0 and x1 <= b.x1 and y0 >= b.y0 and y1 <= b.y1
	end
	local function grow(b, x0: number, y0: number, x1: number, y1: number)
		b.ok = true
		b.x0, b.y0, b.x1, b.y1 = x0 - M, y0 - M, x1 + M, y1 + M
	end
	local builtMain, builtUp, builtDown = newBuilt(), newBuilt(), newBuilt()
	local lastZone, lastKey = -1, ""
	local scrollY = { [5] = 0, [6] = 0 }
	local ledSig = ""

	local function setScroll(i: number, y: number)
		if scrollY[i] ~= y then
			scrollY[i] = y
			L["f" .. i].frame.Position = UDim2.fromScale(0, y * INV)
			D.writes += 1
		end
	end

	function W.reset()
		builtMain.ok, builtUp.ok, builtDown.ok = false, false, false
		lastZone = -1
		W.trainV, W.platA, W.doorA = 900, 0, 0
	end

	-- 캔버스의 글(왼쪽 맞춤 · 밑줄 기준) → 글 상자
	local function floorText(Ly, z: number, str: string, x: number, baseY: number, px: number, col: Color3, alpha: number)
		D.text(Ly, z, str, x, baseY - px * 0.36, px * G.TS, col, alpha, nil, nil, nil, D.FD, true)
	end

	local function pools(Ly, z: number, x0: number, y0: number, x1: number, y1: number, a: number)
		local x = floor((x0 - 130) / 340) * 340
		while x < x1 + 130 do
			local y = floor((y0 - 130) / 300) * 300
			while y < y1 + 130 do
				D.img(Ly, z, "st/light", x + 180, y + 160, 240, 240, a)
				y += 300
			end
			x += 340
		end
	end

	local LITTER = { "st/litter/0", "st/litter/1", "st/litter/2", "st/litter/3", "st/litter/4", "st/litter/5", "st/litter/6" }
	local LEAF = { "ws/leaf/0", "ws/leaf/1", "ws/leaf/2" }

	local function strip256(Ly, z: number, name: string, x0: number, x1: number, cy: number, h: number)
		local x = floor(x0 / 256) * 256
		while x < x1 do
			D.img(Ly, z, name, x + 128, cy, 256, h)
			x += 256
		end
	end

	-- ---------- 승강장 ----------
	local function buildPlat(S, x0: number, y0: number, x1: number, y1: number)
		local A, vw = L.f4, x1 - x0
		local stName = ZONES[S.zone + 1].station or ""
		pools(A, 1, x0, y0, x1, y1, 1)
		for gx = floor(x0 / 170), floor(x1 / 170) do
			for gy = floor(y0 / 170), floor(y1 / 170) do
				local h = hash(gx, gy)
				if h % 100 < 30 then
					local lx, ly = gx * 170 + rshift(h, 8) % 130 + 20, gy * 170 + rshift(h, 16) % 130 + 20
					if abs(ly - floor(ly / LANE_GAP + 0.5) * LANE_GAP) >= 115 then
						D.img(A, 2, LITTER[rshift(h, 3) % 7 + 1], lx, ly, 36, 36)
					end
				end
			end
		end
		for k = floor((y0 - LANE_GAP) / LANE_GAP), floor(y1 / LANE_GAP) do
			local my = k * LANE_GAP + LANE_GAP / 2
			if my > y0 - 20 and my < y1 + 20 then
				D.rect(A, 3, x0, my - 5, vw, 10, C_GREEN, 0.78)
				D.rect(A, 4, x0, my - 8, vw, 1.5, WHITE, 0.5)
				D.rect(A, 4, x0, my + 6.5, vw, 1.5, WHITE, 0.5)
			end
			local x = floor((x0 - 500) / 1100) * 1100
			while x < x1 + 200 do
				if my + 60 < y1 + 90 and my + 170 > y0 then
					floorText(A, 5, stName .. "역", x + 90, my + 150, 92, C_FLOORTXT, 0.16)
				end
				if my - 70 > y0 - 70 and my - 170 < y1 then
					D.spr(A, 6, "sc/arrow/plat", x + 640, my - 120, 1)
				end
				x += 1100
			end
			for i = 1, 2 do
				local ey = if i == 1 then k * LANE_GAP + 122 else (k + 1) * LANE_GAP - 122
				if ey >= y0 - 20 and ey <= y1 + 20 then
					local up = ey < my
					local xx = floor(x0 / 216) * 216
					while xx < x1 + 216 do
						local n = ((floor(xx / 216) % 40) + 40) % 40
						D.text(A, 7, (1 + floor(n / 4)) .. "-" .. (1 + n % 4), xx + 108, ey + (if up then 16 else -8) - 4.3, 12 * G.TS, C_FLOORTXT, 0.3, nil, nil, nil, D.FB)
						D.spr(A, 6, "sc/doormark", xx + 108, ey, 1, 1, if up then 0 else math.pi)
						xx += 216
					end
				end
			end
		end
		-- 선로
		local Led = L.f8
		for k = floor((y0 - 110) / LANE_GAP), ceil((y1 + 110) / LANE_GAP) do
			local ly = k * LANE_GAP
			if not (ly + 100 < y0 or ly - 100 > y1) then
				strip256(A, 8, "st/track", x0, x1, ly, 152)
				strip256(A, 9, "st/tact", x0, x1, ly - 87, 22)
				strip256(A, 9, "st/tact", x0, x1, ly + 87, 22)
				local x = floor(x0 / 48) * 48
				while x < x1 do
					D.rect(Led, 1, x + 20, ly - 61, 8, 3, C_LEDG, 0.55)
					D.rect(Led, 1, x + 20, ly + 58, 8, 3, C_LEDG, 0.55)
					x += 48
				end
			end
		end
		ledSig = ""
	end

	-- 선로 가의 신호 점: 열차 상태가 바뀔 때만 색을 다시 입힌다
	local function updateLeds(S)
		local T = S.train
		local sig = "n"
		if T then
			if not T.on then
				sig = "w" .. T.y .. (if sin(G.time * 22) > 0 then "a" else "b")
			else
				sig = "l" .. T.y
			end
		end
		if sig == ledSig then
			return
		end
		ledSig = sig
		local warnA = if sin(G.time * 22) > 0 then 1 else 0.25
		D.each(L.f8, function(o)
			local ly = floor(o.y / LANE_GAP + 0.5) * LANE_GAP
			local col, a = C_LEDG, 0.55
			if T and T.y == ly then
				col = C_LEDR
				a = if T.on then 0.9 else warnA
			end
			a = floor(a * 64 + 0.5) / 64
			if o.col ~= col then
				o.col = col
				o.g.BackgroundColor3 = col
				D.writes += 1
			end
			if o.a ~= a then
				o.a = a
				o.g.BackgroundTransparency = 1 - a
				D.writes += 1
			end
		end)
	end

	-- 차선의 진입 경고: 붉은 띠 + 흘러가는 갈매기표 (원본 hazardLane · drawPlatform의 warn)
	local function hazardWarn(S, x0: number, y0: number, x1: number, y1: number)
		local T = S.train
		if not T or T.on then
			return
		end
		local ly = T.y
		if ly + 100 < y0 or ly - 100 > y1 then
			return
		end
		local Dy = L.f9
		D.rect(Dy, 1, x0, ly - 56, x1 - x0, 112, C_WARN, 0.16 + 0.12 * sin(G.time * 18))
		local off = fmod(G.time * 520 * T.dir, 140)
		local x = floor(x0 / 140) * 140 - 140
		while x < x1 + 140 do
			D.spr(Dy, 2, "sc/chevron", x + off, ly, 1, 1, nil, T.dir < 0)
			x += 140
		end
	end

	-- ---------- 역 앞 ----------
	local function buildStreet(_S, x0: number, y0: number, x1: number, y1: number)
		local A = L.f4
		for k = floor((y0 - LANE_GAP) / LANE_GAP), floor(y1 / LANE_GAP) do
			local my = k * LANE_GAP + LANE_GAP / 2
			if my > y0 - 20 and my < y1 + 20 then
				strip256(A, 1, "st/tact", x0, x1, my, 22)
			end
			local x = floor((x0 - 600) / 1200) * 1200
			while x < x1 + 200 do
				if my + 40 < y1 + 90 and my + 190 > y0 then
					floorText(A, 2, "역삼역 2번 출구", x + 60, my + 150, 74, C_FLOORTXT, 0.16)
					D.spr(A, 2, "sc/arrow/street", x + 640, my + 124, 1)
				end
				x += 1200
			end
			for i = 1, 2 do
				local ty = if i == 1 then k * LANE_GAP + 170 else (k + 1) * LANE_GAP - 170
				if not (ty < y0 - 110 or ty > y1 + 110) then
					local xx = floor((x0 - 120) / 460) * 460
					while xx < x1 + 120 do
						local q = xx / 460
						local h = hash(if q >= 0 then floor(q) else ceil(q), ty)
						local px = xx + 150 + (h % 60)
						D.img(A, 3, "ws/canopy", px, ty, 240, 240)
						D.img(A, 4, "ws/pit", px, ty, 70, 70)
						xx += 460
					end
				end
			end
		end
		for gx = floor(x0 / 120), floor(x1 / 120) do
			for gy = floor(y0 / 120), floor(y1 / 120) do
				local h = hash(gx, gy + 7)
				local lx, ly = gx * 120 + rshift(h, 8) % 100 + 10, gy * 120 + rshift(h, 16) % 100 + 10
				if abs(ly - floor(ly / LANE_GAP + 0.5) * LANE_GAP) >= 90 then
					local m = h % 100
					if m < 46 then
						D.img(A, 5, LEAF[h % 3 + 1], lx, ly, 16, 16)
					elseif m < 49 then
						D.img(A, 5, "ws/manhole", lx, ly, 44, 44)
					elseif m < 56 then
						D.img(A, 5, LITTER[rshift(h, 3) % 7 + 1], lx, ly, 36, 36)
					end
				end
			end
		end
		for k = floor((y0 - 110) / LANE_GAP), ceil((y1 + 110) / LANE_GAP) do
			local ly = k * LANE_GAP
			if not (ly + 100 < y0 or ly - 100 > y1) then
				strip256(A, 6, "ws/road", x0, x1, ly, 152)
				local x = floor((x0 - 300) / 1100) * 1100
				while x < x1 + 100 do
					D.spr(A, 7, "sc/crosswalk", x + 300, ly, 1)
					x += 1100
				end
			end
		end
	end

	-- ---------- 개찰구 ----------
	local function buildGates(_S, x0: number, y0: number, x1: number, y1: number)
		local A, B, vw = L.f4, L.f7, x1 - x0
		pools(A, 1, x0, y0, x1, y1, 1)
		for gx = floor(x0 / 170), floor(x1 / 170) do
			for gy = floor(y0 / 170), floor(y1 / 170) do
				local h = hash(gx, gy)
				if h % 100 < 18 then
					local lx, ly = gx * 170 + rshift(h, 8) % 130 + 20, gy * 170 + rshift(h, 16) % 130 + 20
					if abs(ly - floor(ly / GATE_GAP + 0.5) * GATE_GAP) >= 60 then
						D.img(A, 2, LITTER[rshift(h, 3) % 7 + 1], lx, ly, 36, 36)
					end
				end
			end
		end
		for k = floor((y0 - GATE_GAP) / GATE_GAP), ceil(y1 / GATE_GAP) do
			local ry = k * GATE_GAP
			local my = ry + GATE_GAP / 2
			if my > y0 - 60 and my < y1 + 60 then
				local x = floor((x0 - 500) / 1040) * 1040
				while x < x1 + 200 do
					floorText(A, 3, if k % 2 ~= 0 then "나가는 곳" else "타는 곳", x + 120, my + 26, 70, C_FLOORTXT, 0.15)
					x += 1040
				end
			end
			if not (ry < y0 - 60 or ry > y1 + 60) then
				D.rect(A, 4, x0, ry - 34, vw, 4, C_YELLOW, 0.85)
				D.rect(A, 4, x0, ry + 30, vw, 4, C_YELLOW, 0.85)
				local gx = floor((x0 - 130) / GATE_PER) * GATE_PER
				while gx < x1 + 130 do
					D.spr(A, 5, "sc/gatetri", gx, ry - 49, 1)
					D.spr(A, 5, "sc/gatetri", gx, ry + 49, 1, 1, math.pi)
					D.img(B, 1, "ws/gate", gx + GATE_PER / 2, ry + 4, 82, 48)
					gx += GATE_PER
				end
			end
		end
	end
	local C_FLAP = rgb("120,230,200")
	local function gateFlaps(x0: number, y0: number, x1: number, y1: number)
		local Dy = L.f5
		for k = floor((y0 - GATE_GAP) / GATE_GAP), ceil(y1 / GATE_GAP) do
			local ry = k * GATE_GAP
			if not (ry < y0 - 60 or ry > y1 + 60) then
				local gx = floor((x0 - 130) / GATE_PER) * GATE_PER
				while gx < x1 + 130 do
					local fl = 0.5 + 0.2 * sin(G.time * 3 + gx)
					for sd = -1, 1, 2 do
						D.line(Dy, 1, gx + sd * GATE_HALF, ry, gx + sd * (GATE_HALF - 10), ry - 14 * fl, 3, C_FLAP, 0.75, true)
					end
					gx += GATE_PER
				end
			end
		end
	end

	-- ---------- 에스컬레이터 ----------
	local function buildEscStairs(x0: number, y0: number, x1: number, y1: number)
		local A = L.f4
		local c = floor(x0 / ESC_W)
		while c * ESC_W < x1 do
			if ((c % 3) + 3) % 3 == 1 then
				local y = floor(y0 / 120) * 120
				while y < y1 do
					D.img(A, 1, "ws/stair", c * ESC_W + 110, y + 60, ESC_W, 120)
					y += 120
				end
			end
			c += 1
		end
		pools(L.f7, 1, x0, y0, x1, y1, 0.7)
	end
	-- 한쪽 방향 발판 층. y0, y1은 그 층 안의 좌표(세계 y − 밀린 만큼)
	local function buildEscMoving(Ly, want: number, dir: number, x0: number, y0: number, x1: number, y1: number)
		local c = floor(x0 / ESC_W)
		while c * ESC_W < x1 do
			if ((c % 3) + 3) % 3 == want then
				local x = c * ESC_W
				local y = floor(y0 / 104) * 104
				while y < y1 do
					D.img(Ly, 1, "ws/esc", x + 110, y + 52, ESC_W, 104)
					y += 104
				end
				y = floor(y0 / 300) * 300
				while y < y1 + 100 do
					D.spr(Ly, 2, "sc/escarrow", x + 110, y, 1, 1, if dir > 0 then 0 else math.pi)
					y += 300
				end
				y = floor(y0 / 60) * 60
				while y < y1 do
					D.rect(Ly, 3, x + 5, y, 3, 24, WHITE, 0.22)
					D.rect(Ly, 3, x + 212, y, 3, 24, WHITE, 0.22)
					y += 60
				end
			end
			c += 1
		end
	end

	-- ---------- 회사 앞 ----------
	local function buildOffice(_S, x0: number, y0: number, x1: number, y1: number)
		local A = L.f4
		-- 비스듬한 빛 띠 (가로 폭 340의 45도 띠)
		local d = floor((x0 + y0 - 900) / 1100) * 1100
		local ym, len = (y0 + y1) / 2, (y1 - y0) * math.sqrt(2)
		while d < x1 + y1 + 900 do
			D.box(A, 1, d - ym + 170, ym, len, 340 / math.sqrt(2), C_OFFTXT, 0.07, math.pi * 0.75)
			d += 1100
		end
		for gy = floor((y0 - 300) / 760), floor(y1 / 760) do
			for gx = floor((x0 - 700) / 1300), floor(x1 / 1300) do
				local odd = gy % 2 ~= 0
				local x, y = gx * 1300 + (if odd then 650 else 0), gy * 760
				floorText(A, 2, if odd then "출근 9:00" else "구로구", x + 80, y + 250, 64, C_OFFTXT, 0.2)
			end
		end
		for gx = floor(x0 / 120), floor(x1 / 120) do
			for gy = floor(y0 / 120), floor(y1 / 120) do
				local h = hash(gx + 3, gy)
				if h % 100 < 22 then
					D.img(A, 3, LEAF[h % 3 + 1], gx * 120 + rshift(h, 8) % 100 + 10, gy * 120 + rshift(h, 16) % 100 + 10, 16, 16)
				end
			end
		end
		for gx = floor((x0 - 80) / 520), floor((x1 + 80) / 520) do
			for gy = floor((y0 - 80) / 460), floor((y1 + 80) / 460) do
				local h = hash(gx, gy + 11)
				if h % 10 < 6 then
					D.img(A, 4, "ws/planter", gx * 520 + 120 + rshift(h, 8) % 220, gy * 460 + 110 + rshift(h, 16) % 180 - 2, 72, 72)
				end
			end
		end
	end

	-- ---------- 열차 안 ----------
	local C_TUNNEL, C_TLINE, C_TLIGHT, C_TGLOW, C_PLATF = rgb("#0b0f12"), rgb("#1a2025"), rgb("255,240,190"), rgb("255,236,180"), rgb("#cdc9be")
	local C_DOORLIGHT = rgb("255,250,228")
	local C_AISLE, C_SIGNTXT, C_BAR = rgb("40,56,64"), rgb("#ffb300"), rgb("205,212,216")
	local function seatDir(h: number): number
		return if band(rshift(h, 4), 1) == 1 then 1 else -1
	end
	local function buildTrain(_S, x0: number, _y0: number, x1: number, _y1: number)
		local A, vw = L.f4, x1 - x0
		D.rect(A, 1, x0, -AISLE, vw, 3, C_AISLE, 0.1)
		D.rect(A, 1, x0, AISLE - 3, vw, 3, C_AISLE, 0.1)
		local x = floor((x0 - 40) / 2560) * 2560
		while x < x1 + 40 do
			D.spr(A, 2, "tr/joint", x, 0, 1)
			x += 2560
		end
		local b = floor((x0 - 120) / DOOR_PER)
		while b * DOOR_PER < x1 + 120 do
			local bx, m8 = b * DOOR_PER, ((b % 8) + 8) % 8
			if m8 ~= 0 then
				local bench = if m8 == 1 or m8 == 7 then "ws/bench/1" else "ws/bench/0"
				D.img(A, 3, bench, bx, -WALL + 20, 230, 40)
				for s = 0, 6 do
					local h = hash(b, s)
					if h % 10 < 7 then
						G.char(A, 4, "pass", h % 4, 0, seatDir(h), false, bx - 96 + s * 32, -84, 0.9)
					end
				end
				D.img(A, 3, bench, bx, WALL - 20, 230, 40, 1, math.pi)
			end
			b += 1
		end
		-- 위에 덮이는 것: 앞줄에 앉은 사람 · 봉 · 천장 봉
		local O = L.over
		b = floor((x0 - 120) / DOOR_PER)
		while b * DOOR_PER < x1 + 280 do
			local bx = b * DOOR_PER
			local dx = bx + 160
			if ((b % 8) + 8) % 8 ~= 0 then
				for s = 0, 6 do
					local h = hash(b + 5, s)
					if h % 10 < 7 then
						G.char(O, 1, "pass", h % 4, 0, seatDir(h), false, bx - 96 + s * 32, WALL - 6, 0.9)
					end
				end
			end
			for sd = -1, 1, 2 do
				for hs = -1, 1, 2 do
					D.spr(O, 2, "tr/pole", dx + hs * 44, sd * (AISLE - 6), 1)
				end
			end
			b += 1
		end
		D.rect(O, 3, x0, -46 - 1.25, vw, 2.5, C_BAR, 0.5)
		D.rect(O, 3, x0, 46 - 1.25, vw, 2.5, C_BAR, 0.5)
	end

	local function trainFrame(S, x0: number, y0: number, x1: number, y1: number, dt: number)
		local time = G.time
		local open = S.doorT > 0
		W.trainV += ((if open then 0 else 900) - W.trainV) * min(1, dt * 2.4)
		W.trainScroll += W.trainV * dt
		W.platA += ((if open then 1 else 0) - W.platA) * min(1, dt * 3.2)
		W.doorA += ((if open then 1 else 0) - W.doorA) * min(1, dt * 5)
		local trainV, trainScroll, platA, doorA = W.trainV, W.trainScroll, W.platA, W.doorA
		local vw, vh = x1 - x0, y1 - y0
		local Un = L.f1
		D.rect(Un, 1, x0 - 2, y0 - 2, vw + 4, vh + 4, C_TUNNEL, 1)
		for _, yy in { -150, -162, 150, 162 } do
			D.rect(Un, 2, x0, yy, vw, 2.5, C_TLINE, 1)
		end
		local len = 18 + trainV * 0.14
		local x = floor((x0 + trainScroll) / 380) * 380 - trainScroll - 380
		while x < x1 + len do
			for sd = -1, 1, 2 do
				local yy = sd * 186
				D.rect(Un, 3, x, yy - 2.5, len, 5, C_TLIGHT, 0.55)
				D.img(Un, 4, "fx/glow", x + len / 2, yy, len + 68, 88, 0.4, nil, nil, C_TGLOW)
			end
			x += 380
		end
		if platA > 0.02 then
			local nm = if S.stopIdx > 0 and STOPS[S.stopIdx] then STOPS[S.stopIdx].name else ""
			for sd = -1, 1, 2 do
				local ya = if sd > 0 then OUT else -OUT - 230
				D.rect(Un, 5, x0, ya, vw, 230, C_PLATF, platA)
				local tx = floor(x0 / 256) * 256
				while tx < x1 do
					D.img(Un, 6, "st/tact", tx + 128, (if sd > 0 then OUT + 6 else -OUT - 28) + 11, 256, 22, platA)
					tx += 256
				end
				local sx = floor((x0 - 300) / 560) * 560
				while sx < x1 + 300 do
					local sy = sd * 212
					D.spr(Un, 7, "tr/sign", sx + 150, sy, 1, platA)
					D.text(Un, 8, nm, sx + 150, sy - 4, 24 * G.TS, C_INK, platA)
					sx += 560
				end
			end
			-- 승강장에 줄 선 사람들: 타면서 줄어든다
			local left = if open then max(0, S.doorT / DOOR_OPEN) else 0
			local nq = ceil(left * 11)
			local b = floor((x0 - 120) / DOOR_PER)
			while b * DOOR_PER < x1 + 280 do
				local dx = b * DOOR_PER + 160
				for sd = -1, 1, 2 do
					for j = 0, nq - 1 do
						local h = hash(b * 7 + (if sd > 0 then 3 else 0), j + S.stopIdx * 13)
						local col, row = (j % 3) - 1, floor(j / 3)
						local sh = arshift(h, 6)
						if sh >= 0x80000000 then
							sh -= 0x100000000
						end
						G.char(Un, 9, "pass", h % 4, floor(time * 6 + h) % 4, if sd > 0 then -1 else 1, false, dx + col * 24 + (fmod(sh, 9) - 4), (if sd > 0 then OUT + 46 + row * 28 else -OUT - 8 - row * 28) + sin(time * 7 + h) * 1.5, 0.92, platA)
					end
				end
				b += 1
			end
		end
		-- 열린 문으로 드는 빛
		if doorA > 0.05 then
			local b = floor((x0 - 120) / DOOR_PER)
			while b * DOOR_PER < x1 + 280 do
				local dx = b * DOOR_PER + 160
				-- 원본은 옅은 노란빛을 더하기 섞기로 얹어 밝은 바닥에서 하얗게 뜬다 → 흰 사다리꼴 빛으로 그린다
				D.spr(L.f3, 1, "prim/cone", dx, 0, 1, doorA * 0.9, nil, nil, C_DOORLIGHT)
				D.spr(L.f3, 1, "prim/cone", dx, 0, 1, doorA * 0.9, math.pi, nil, C_DOORLIGHT)
				b += 1
			end
		end
		-- 벽 · 창문 · 문
		local Dy = L.f9
		local wallSt = if platA > 0.3 then "1" else "0"
		local win = if platA > 0.5 then "tr/window/1" else "tr/window/0"
		local stopName
		if S.stopIdx < #STOPS then
			local st = if open then STOPS[S.stopIdx] else STOPS[S.stopIdx + 1]
			stopName = if st then st.name else ""
		else
			stopName = if open and S.stopIdx > 0 then STOPS[S.stopIdx].name else Sim.LAST_STOP
		end
		local label = (if open then "이번 역 " else "다음 역 ") .. stopName
		local g2 = 31 * doorA
		for sd = -1, 1, 2 do
			local wy = if sd > 0 then WALL else -OUT
			local wall = "tr/wall/" .. wallSt .. (if sd > 0 then "/bot" else "/top")
			local b = floor((x0 - 120) / DOOR_PER)
			while b * DOOR_PER < x1 + 280 do
				local bx = b * DOOR_PER
				local dx = bx + 160
				D.spr(Dy, 1, wall, bx, 0, 1)
				if ((b % 8) + 8) % 8 ~= 0 then
					D.spr(Dy, 2, win, bx, wy + 7, 1)
				end
				D.spr(Dy, 3, "tr/doorpanel", dx - 35 - g2, wy, 1)
				D.spr(Dy, 3, "tr/doorpanel", dx + g2, wy, 1)
				D.text(Dy, 4, label, dx, (if sd > 0 then WALL - 11.5 else -WALL + 18.5) - 3.6, 10 * G.TS, C_SIGNTXT, 1)
				b += 1
			end
		end
		-- 천장 손잡이: 열차가 설 때 한쪽으로 쏠린다
		local sway = (trainV - 900) / 900 * 10
		local Od = L.overD
		for i = 1, 2 do
			local yy = if i == 1 then -46 else 46
			local sx = floor(x0 / 38) * 38
			while sx < x1 + 38 do
				if abs(((sx % DOOR_PER) + DOOR_PER) % DOOR_PER - 160) >= 46 then
					local off = sin(time * 2.6 + sx * 0.07) * 1.6 - sway
					D.spr(Od, 1, "tr/strap", sx, yy, 1, 1, -math.asin(math.clamp(off / 9, -1, 1)))
				end
				sx += 38
			end
		end
	end

	-- ---------- 한 장면 ----------
	local FLOORS = { "f1", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "over", "overD" }
	function W.draw(S, dt: number)
		local x0, y0, x1, y1 = G.x0, G.y0, G.x1, G.y1
		local zk = S.zk
		local key = ZONES[S.zone + 1].key
		if S.zone ~= lastZone or key ~= lastKey then
			lastZone, lastKey = S.zone, key
			builtMain.ok, builtUp.ok, builtDown.ok = false, false, false
			for _, n in FLOORS do
				D.clear(L[n])
			end
			setScroll(5, 0)
			setScroll(6, 0)
			hideTiles()
		end
		-- 매 장면 그리는 층
		D.begin(L.f1)
		D.begin(L.f3)
		D.begin(L.f9)
		D.begin(L.overD)
		if zk ~= "esc" then
			D.begin(L.f5)
		end

		if zk == "train" then
			setTiles("floor/" .. key, x0 - 2, -OUT, x1 + 2, OUT, -OUT, OUT)
		elseif zk == "esc" then
			hideTiles()
		else
			setTiles("floor/" .. key, x0, y0, x1, y1)
		end

		if not inside(builtMain, x0, y0, x1, y1) then
			grow(builtMain, x0, y0, x1, y1)
			local bx0, by0, bx1, by1 = builtMain.x0, builtMain.y0, builtMain.x1, builtMain.y1
			D.begin(L.f4)
			D.begin(L.f7)
			D.begin(L.f8)
			D.begin(L.over)
			if zk == "street" then
				buildStreet(S, bx0, by0, bx1, by1)
			elseif zk == "gates" then
				buildGates(S, bx0, by0, bx1, by1)
			elseif zk == "train" then
				buildTrain(S, bx0, by0, bx1, by1)
			elseif zk == "esc" then
				buildEscStairs(bx0, by0, bx1, by1)
			elseif zk == "office" then
				buildOffice(S, bx0, by0, bx1, by1)
			else
				buildPlat(S, bx0, by0, bx1, by1)
			end
			D.finish(L.f4)
			D.finish(L.f7)
			D.finish(L.f8)
			D.finish(L.over)
		end

		if zk == "street" then
			hazardWarn(S, x0, y0, x1, y1)
		elseif zk == "gates" then
			gateFlaps(x0, y0, x1, y1)
		elseif zk == "train" then
			trainFrame(S, x0, y0, x1, y1, dt)
		elseif zk == "esc" then
			-- 발판 층을 민다: 위로(−1) · 아래로(+1). 7800 = 발판 104 · 화살표 300 · 손잡이 줄 60이 함께 맞는 주기
			for i = 5, 6 do
				local dir = if i == 5 then -1 else 1
				local off = (G.time * ESC_PUSH * dir) % 7800
				setScroll(i, off)
				local b = if i == 5 then builtUp else builtDown
				if not inside(b, x0, y0 - off, x1, y1 - off) then
					grow(b, x0, y0 - off, x1, y1 - off)
					D.begin(L["f" .. i])
					buildEscMoving(L["f" .. i], if i == 5 then 0 else 2, dir, b.x0, b.y0, b.x1, b.y1)
					D.finish(L["f" .. i])
				end
			end
		elseif zk == "plat" then
			updateLeds(S)
			hazardWarn(S, x0, y0, x1, y1)
		end

		D.finish(L.f1)
		D.finish(L.f3)
		D.finish(L.f9)
		D.finish(L.overD)
		if zk ~= "esc" then
			D.finish(L.f5)
		end
	end

	return W
end
