-- 무기와 효과 (원본 gfx.js render의 fxLayer): 배낭 철퇴 · 신사 우산 · 백팩 회전 · 셀카봉 · 킥보드 · 손잡이 · 던진 것 · 카드 · 적의 탄 ·
--  입자 · 노트북 광선 · 그때그때의 효과(fxs: 금 · 넥타이 · 어깨빵 · 조합 발동 · 보스 등장 · 물결 고리 · 찌르기 · 휘두르기 · 외침 · 레벨 업 · 번개)
return function(G, Parts)
	local D, Sim = G.D, G.Sim
	local L = G.L
	local rgb = D.rgb
	local lite = D.lite
	local rnd = math.random
	local cos, sin, atan2, floor, min, max, sqrt, pow, abs = math.cos, math.sin, math.atan2, math.floor, math.min, math.max, math.sqrt, math.pow, math.abs
	local TAU, PI = math.pi * 2, math.pi
	local WEAPONS, EVO = Sim.WEAPONS, Sim.EVO
	local WHITE = D.WHITE
	local C_INK = rgb("#1f262b")
	local inView = D.inView
	local trails = G.trails
	local wl = G.wl

	local Wp = {}

	local function hypot(x: number, y: number): number
		return sqrt(x * x + y * y)
	end
	-- (ox, oy)를 축으로 th만큼 돌린 틀 안의 점 (lx, ly) → 세계 좌표
	local function loc(ox: number, oy: number, th: number, lx: number, ly: number): (number, number)
		local c, s = cos(th), sin(th)
		return ox + lx * c - ly * s, oy + lx * s + ly * c
	end
	-- 점선: (x0,y0)→(x1,y1) 위에 on 길이의 토막을 per 간격으로 놓는다 (off = 흘러가는 만큼)
	local function dashes(Ly, z: number, x0: number, y0: number, x1: number, y1: number, lw: number, col: Color3, alpha: number, on: number, per: number, off: number)
		local dx, dy = x1 - x0, y1 - y0
		local len = hypot(dx, dy)
		if len < 1 then
			return
		end
		local ux, uy, rot = dx / len, dy / len, atan2(dy, dx)
		local t = off % per
		while t < len do
			local e = min(len, t + on)
			local m = (t + e) / 2
			D.box(Ly, z, x0 + ux * m, y0 + uy * m, e - t, lw, col, alpha, rot)
			t += per
		end
	end

	local C_MACE, C_STRAP1, C_STRAP2, C_STRAP3, C_SHADOW = rgb("255,150,70"), rgb("16,22,24"), rgb("#3a2a1c"), rgb("#e9c46a"), rgb("20,24,28")
	local C_SHAFT, C_PARRY = rgb("#b98654"), lite("255,236,170")
	local C_BULL, C_PEVO, C_PACK, C_BLADE, C_BLADEK, C_BSTRAP = lite("255,201,40"), lite("255,150,70"), lite("130,195,255"), rgb("#ffc928"), rgb("#17191a"), rgb("28,32,36")
	local C_SELF, C_SELFE, C_STICK1, C_STICK2, C_SGL, C_SGLE = lite("255,240,200"), lite("255,170,220"), rgb("#d7dde0"), rgb("#8b9599"), lite("190,240,255"), lite("255,150,220")
	local C_RIDE, C_RIDEE, C_HEAD = lite("120,240,255"), lite("255,170,80"), lite("255,240,170")
	local C_FP, C_RANGE, C_RANG = lite("255,205,70"), lite("255,214,110"), lite("200,225,255")
	local C_SHOTE, C_SHOT = lite("255,210,90"), lite("90,255,160")
	local C_FP_B, C_SHOTE_B, C_SHOT_B = D.bright("255,205,70"), D.bright("255,210,90"), D.bright("90,255,160")
	local BULGLOW = {}
	for i, c in { "255,120,90", "255,70,70", "255,110,160", "255,90,90", "255,80,200", "255,150,80", "255,90,200", "255,100,90", "255,90,150", "255,140,70", "255,150,70" } do
		BULGLOW[i - 1] = lite(c)
	end
	local BUL = {}
	for i = 0, 10 do
		BUL[i] = "st/bul/" .. i
	end
	local C_BPERM, C_BEVO, C_BEAM = rgb("255,205,50"), rgb("170,125,255"), rgb("90,175,255")
	local C_BPERM_L, C_BEVO_L, C_BEAM_L = lite("255,205,50"), lite("170,125,255"), lite("90,175,255")

	-- ---------- 무기 ----------
	local function weapons(S)
		local F = L.fx
		local p, M, time, gl = S.p, S.M, G.time, G.gl
		local fus = S.fus

		-- 배낭 철퇴 (조합)
		if fus and fus.bulldozer and S.mace then
			local Mc, z = S.mace, 78
			local slam = Mc.sl > 0
			local mx, my, lift, sc = Mc.x, Mc.y, 0, 1
			if slam then
				local u = 1 - Mc.sl / Mc.sd
				mx, my = Mc.x0 + (Mc.x - Mc.x0) * u, Mc.y0 + (Mc.y - Mc.y0) * u
				lift = sin(u * PI) * 70 + (1 - u) * 10
				sc = 1 + 0.35 * sin(u * PI)
				D.oval(F, 1, Mc.x, Mc.y + 10, 60 * (0.5 + 0.5 * u), 26 * (0.5 + 0.5 * u), C_SHADOW, 0.12 + 0.2 * u)
			else
				local R = hypot(Mc.x - p.x, Mc.y - p.y)
				for t = 0, 7 do
					D.arc(F, 2, p.x, p.y, R, Mc.a - 0.11 * (t + 1) - 0.14, Mc.a - 0.11 * t - 0.14, z * 0.62 * (1 - t / 9), C_MACE, min(1, 0.16 * (1 - t / 8) * gl), nil, 1)
				end
				D.img(F, 3, "st/shadow", mx, my + z * 0.57, z * 1.1, z * 0.42)
			end
			-- 손에서 배낭까지 팽팽한 끈
			local hx, hy = p.x + cos(Mc.a) * 10, p.y - 8 + sin(Mc.a) * 6
			D.line(F, 4, hx, hy, mx, my - lift, 6.5, C_STRAP1, 0.95, true)
			D.line(F, 5, hx, hy, mx, my - lift, 3.6, C_STRAP2, 1, true)
			dashes(F, 6, hx, hy, mx, my - lift, 3.6, C_STRAP3, 1, 3, 16, 0)
			D.img(F, 7, "fx/glow", mx, my - lift, z * 1.6, z * 1.6, min(1, 0.3 * gl), nil, nil, C_MACE)
			local rot = if slam then atan2(Mc.y - Mc.y0, Mc.x - Mc.x0) + PI / 2 else Mc.a + PI / 2
			D.img(F, 8, "st/pack/1", mx, my - lift, z * sc, z * 1.09 * sc, 1, rot)
		end

		-- 풀정장 신사의 우산 (조합)
		if fus and fus.gentleman and S.gent then
			local Gn, R = S.gent, 59
			local fl = max(0, Gn.fl) / 0.18
			local a = Gn.a
			local cx, cy = p.x + cos(a) * (R - 12 + fl * 5), p.y - 6 + sin(a) * (R - 12 + fl * 5)
			D.line(F, 9, p.x + cos(a) * 8, p.y - 6 + sin(a) * 8, cx, cy, 5, C_INK, 1, true)
			D.line(F, 10, p.x + cos(a) * 8, p.y - 6 + sin(a) * 8, cx, cy, 2.6, C_SHAFT, 1, true)
			D.img(F, 11, "st/shadow", cx, cy + 45, 74, 24)
			D.img(F, 12, "fx/gcan", cx, cy, 114 * 0.4, 114, 1, a)
			local tx, ty = loc(p.x, p.y - 6, a, R + 13 + fl * 5, 0)
			D.img(F, 13, "fx/gentip", tx, ty, 18, 10, 1, a)
			if fl > 0 then
				D.arc(F, 14, p.x, p.y - 6, R + 10, a - 1.05, a + 1.05, 5, C_PARRY, min(1, 0.85 * fl))
			end
		end

		-- 백팩 회전 (조합이면 불도저 날)
		local l = wl(S, "backpack")
		if l > 0 then
			local bull = fus and fus.bulldozer
			local fl = if G.bagFling > 0 then sin((1 - G.bagFling / 0.55) * PI) else 0
			local s = WEAPONS.backpack.stat(l)
			local rad = s.radius * M.area * (1 + (if bull then 1.25 else 0) * fl)
			local ev = l >= EVO
			local z = s.size * 1.8 * (if bull then 1.3 + 0.35 * fl else 1)
			local c = if bull then C_BULL elseif ev then C_PEVO else C_PACK
			if bull then
				local A = if S.bullA == nil then atan2(p.fy, p.fx) else S.bullA
				local R0 = s.radius * M.area * 0.8 * (1 + 0.45 * fl)
				local half = (s.n - 1) / 2 * 0.44 + 0.3
				local Rb = R0 + z * 0.42
				D.arc(F, 15, p.x, p.y, Rb, A - half, A + half, 13, C_STRAP1, 0.95)
				D.arc(F, 16, p.x, p.y, Rb, A - half, A + half, 9, C_BLADE, 1)
				-- 검은 줄무늬: 호를 따라 7 길이의 토막을 16 간격으로
				local da = 16 / Rb
				local an = A - half + 0.04
				while an < A + half - 0.04 do
					local e = min(A + half - 0.04, an + 7 / Rb)
					D.arc(F, 17, p.x, p.y, Rb, an, e, 9, C_BLADEK, 1, nil, 1)
					an += da
				end
				D.arc(F, 18, p.x, p.y, Rb + 3.2, A - half + 0.05, A + half - 0.05, 1.6, WHITE, 0.5)
				if fl > 0 then
					D.arc(F, 19, p.x, p.y, Rb + 8, A - half, A + half, 20, C_BULL, min(1, 0.5 * fl * gl))
				end
				for i = 0, s.n - 1 do
					local a = A + (i - (s.n - 1) / 2) * 0.44
					local ox, oy = p.x + cos(a) * R0, p.y + sin(a) * R0
					D.img(F, 20, "st/shadow", ox, oy + z * 0.75, z * 1.2, z * 0.5)
					D.line(F, 21, p.x + cos(a) * 16, p.y - 6 + sin(a) * 12, ox - cos(a) * z * 0.3, oy - sin(a) * z * 0.3, 3, C_BSTRAP, 0.9, true)
					D.img(F, 23, "st/pack/1", ox, oy, z, z * 1.09, 1, a + PI / 2)
				end
			else
				for i = 0, s.n - 1 do
					local a = S.orbA + i * TAU / s.n
					for t = 0, 6 do
						D.arc(F, 15, p.x, p.y, rad, a - 0.13 * (t + 1) - 0.02, a - 0.13 * t, z * 0.9 * (1 - t / 8), c, min(1, 0.2 * (1 - t / 7) * gl), nil, 1)
					end
				end
				local pack = if ev then "st/pack/1" else "st/pack/0"
				for i = 0, s.n - 1 do
					local a = S.orbA + i * TAU / s.n
					local ox, oy = p.x + cos(a) * rad, p.y + sin(a) * rad
					D.img(F, 20, "st/shadow", ox, oy + z * 0.75, z * 1.2, z * 0.5)
					D.img(F, 22, "fx/glow", ox, oy, z * 2.2, z * 2.2, min(1, 0.45 * gl), nil, nil, c)
					D.img(F, 23, pack, ox, oy, z, z * 1.09, 1, a + PI / 2 + sin(time * 9 + i) * 0.15)
				end
			end
		end

		-- 셀카봉
		l = wl(S, "selfie")
		if l > 0 then
			local s = WEAPONS.selfie.stat(l)
			local len = s.len * M.area
			local ev = l >= EVO
			local c = if ev then C_SELFE else C_SELF
			for i = 0, s.n - 1 do
				local a = S.selfA + i * TAU / s.n
				-- 지나간 자리의 부채꼴(폭 0.1 라디안짜리 일곱 장)
				for t = 0, 6 do
					local am = a - 0.1 * (t + 0.5)
					local vx, vy = cos(am), sin(am)
					local mid = (22 + len) / 2
					D.img(F, 24, "prim/tri", p.x + vx * mid, p.y + vy * mid, len * 0.1, len - 22, min(1, 0.13 * (1 - t / 7) * gl), atan2(-vx, vy), nil, c)
				end
				local ex, ey = p.x + cos(a) * len, p.y + sin(a) * len
				local sx, sy = p.x + cos(a) * 14, p.y - 6 + sin(a) * 14
				D.line(F, 25, sx, sy, ex, ey, 5, C_INK, 1, true)
				D.line(F, 26, sx, sy, ex, ey, 2.6, C_STICK1, 1, true)
				D.line(F, 27, sx, sy, p.x + cos(a) * len * 0.45, p.y - 3 + sin(a) * len * 0.45, 2.6, C_STICK2, 1, true)
				local gr = if ev then 30 else 22
				D.img(F, 28, "fx/glow", ex, ey, gr * 2, gr * 2, min(1, 0.6 * gl), nil, nil, if ev then C_SGLE else C_SGL)
				if ev then
					D.ring(F, 29, ex, ey, 17, 3, WHITE, 0.7 + 0.3 * sin(time * 20 + i))
				end
				D.img(F, 30, "fx/phone", ex, ey, 18, 28, 1, a + PI / 2)
			end
		end

		-- 킥보드
		for _, r in S.riders do
			local a = atan2(r.dy, r.dx)
			local c = if r.evo then C_RIDEE else C_RIDE
			local tl = min(150, r.dist)
			if tl > 1 then
				D.gline(F, 31, r.x, r.y, r.x - r.dx * tl, r.y - r.dy * tl, r.w * 1.5 * 2, c, min(1, 0.7 * gl), true)
				D.gline(F, 54, r.x, r.y, r.x - r.dx * tl, r.y - r.dy * tl, r.w * 1.1, WHITE, 0.7, true)
				for i = 1, 2 do
					local o = if i == 1 then -0.45 else 0.45
					local x0, y0 = r.x - r.dy * r.w * o, r.y + r.dx * r.w * o
					D.line(F, 32, x0, y0, x0 - r.dx * tl * 0.7, y0 - r.dy * tl * 0.7, 2, WHITE, 0.8, true)
				end
			end
			D.img(F, 33, "fx/glow", r.x + r.dx * 26, r.y + r.dy * 26, 52, 52, 1, nil, nil, C_HEAD)
			local sc = r.w / 22 * 1.25
			local x1, y1 = loc(r.x, r.y, a, 0, 2 + 8 * sc)
			D.img(F, 34, "st/shadow", x1, y1, 48 * sc, 16 * sc, 1, a)
			x1, y1 = loc(r.x, r.y, a, 4 * sc, 0)
			D.img(F, 35, "fx/scooter", x1, y1, 60 * sc, 26 * sc, 1, a)
		end

		-- 손잡이 (부메랑)
		local fp = fus and fus.freepass
		for _, b in S.rangs do
			local c = if fp then C_FP elseif b.evo then C_RANGE else C_RANG
			local tr = trails[b]
			local z = b.size * 2.6 * (if fp then 1.55 else 1)
			if tr and #tr >= 4 then
				-- 꼬리: 원본은 지난 10장의 길을 잇는다(머리 쪽이 굵고 진하다). 길이를 시간(10/60초에 가는 거리)으로 끊어, 장면이 느려도 길어지지 않게 한다
				local n = #tr / 2
				local limit = max(1, (b.sp or 300) * (10 / 60))
				local acc = 0
				for i = n - 1, 1, -1 do
					local f = 1 - acc / limit
					if f <= 0.02 then
						break
					end
					local x0, y0, x1, y1 = tr[i * 2 - 1], tr[i * 2], tr[i * 2 + 1], tr[i * 2 + 2]
					D.line(F, 36, x0, y0, x1, y1, max(0.5, z * 0.55 * f), c, min(1, f * 0.5 * gl), true)
					acc += hypot(x1 - x0, y1 - y0)
				end
			end
			D.img(F, 37, "fx/glow", b.x, b.y, z * 1.6, z * 1.6, min(1, 0.5 * gl), nil, nil, c)
			D.img(F, 38, if fp then "fx/handleG" else "fx/handle", b.x, b.y, z, z, 1, b.t * 18)
			if fp then
				for k = 0, 3 do
					local a = -b.t * 13 + k * TAU / 4
					D.img(F, 39, "st/card/1", b.x + cos(a) * z * 0.62, b.y + sin(a) * z * 0.62, 22, 16, 1, a + PI / 2)
				end
			end
		end

		-- 던진 것: 커피 · 알람 · 시한폭탄
		local routine = fus and fus.routine
		for _, b in S.lobs do
			local q = b.t / b.dur
			local x, y = b.x0 + (b.x1 - b.x0) * q, b.y0 + (b.y1 - b.y0) * q - sin(q * PI) * 60
			if b.r * q > 1 then
				D.oval(F, 40, b.x1, b.y1, b.r * 0.5 * q, b.r * 0.4 * q, C_SHADOW, 0.25 * q)
			end
			local sc = 1 + sin(q * PI) * 0.35
			if routine then
				local rot = sin(q * 14) * 0.35
				local cx, cy = loc(x, y, rot, 0, -2.5 * sc)
				D.img(F, 41, "fx/wake", cx, cy, 32 * sc, 37 * sc, 1, rot)
			elseif b.kind == "alarm" then
				local rot = q * 11
				local cx, cy = loc(x, y, rot, 0, -sc)
				D.img(F, 42, "fx/clock", cx, cy, 26 * sc, 28 * sc, 1, rot)
			else
				D.img(F, 43, "st/cup", x, y, 20 * sc, 24 * sc, 1, q * 11)
			end
		end

		-- 교통카드
		for _, s in S.shots do
			local c = if fp then C_FP elseif s.evo then C_SHOTE else C_SHOT
			local tr = trails[s]
			if tr and #tr >= 2 then
				-- 꼬리: 원본은 지난 8장(= 8/60초) 동안 지나온 길에, 머리 쪽이 굵고(11) 진하며(0.6) 꼬리 끝으로 가늘어지며 사라지는 토막을 잇는다.
				--  길이는 「장 수」가 아니라 시간으로 잡는다(8/60초에 가는 거리) — 장면이 느려도 꼬리가 길어지지 않게. 갓 던진 카드는 던진 자리까지만
				local dx, dy = tr[1] - s.x, tr[2] - s.y
				local dist = hypot(dx, dy)
				local len = min(dist, hypot(s.vx, s.vy) * (8 / 60))
				if len > 2 then
					local ux, uy = dx / dist, dy / dist
					local rot = atan2(uy, ux)
					D.img(F, 44, "prim/comet", s.x + ux * len / 2, s.y + uy * len / 2, len, 15, min(0.9, 0.6 * gl), rot, nil, if fp then C_FP_B elseif s.evo then C_SHOTE_B else C_SHOT_B)
					-- 머리 쪽의 흰 심(원본: 마지막 3장 길이의 흰 선 · 굵기 2 · 0.8)
					local wl2 = len * 3 / 8
					D.line(F, 45, s.x, s.y, s.x + ux * wl2, s.y + uy * wl2, 2, WHITE, 0.8, true)
				end
			end
			D.img(F, 46, "fx/glow", s.x, s.y, 38, 38, min(1, 0.7 * gl), nil, nil, c)
			D.img(F, if s.evo then 48 else 47, if s.evo then "st/card/1" else "st/card/0", s.x, s.y, 24, 18 * (0.55 + 0.45 * abs(cos(s.a * 0.7))), 1, s.a)
		end

		-- 적의 탄
		for _, b in S.bullets do
			if inView(b.x, b.y, 24) then
				local kind = b.kind
				D.img(F, 49, "fx/glow", b.x, b.y, b.r * 5.2, b.r * 5.2, min(1, 0.75 * gl), nil, nil, BULGLOW[kind] or WHITE)
				if kind == 2 or kind == 3 or kind == 5 then
					D.img(F, 51, BUL[kind], b.x, b.y, 20, 20, 1, b.a)
				elseif kind == 6 then
					D.img(F, 51, BUL[6], b.x, b.y + sin(b.a * 2) * 2, 24, 24)
				elseif kind == 8 then
					local s = b.r * 3.1
					local hop = abs(sin(b.a * 1.6)) * 3
					D.img(F, 50, "st/shadow", b.x, b.y + s * 0.42, s * 0.9, s * 0.4)
					D.img(F, 51, BUL[8], b.x, b.y - hop, s, s, 1, sin(b.a * 1.6) * 0.16)
					if rnd() < 0.25 then
						G.P({ k = "smoke", x = b.x - b.vx * 0.05, y = b.y + s * 0.3, vx = -b.vx * 0.1, vy = -12, life = 0.5, size = 10, col = "220,215,205", drag = 0.4 })
					end
				elseif kind >= 7 then
					local s = if kind == 7 then 26 else 22
					D.img(F, 51, BUL[kind], b.x, b.y, s, s, 1, if kind == 9 then atan2(b.vy, b.vx) + sin(b.a * 2) * 0.3 else b.a)
				else
					local s = b.r * 2.7
					D.img(F, 51, BUL[kind] or BUL[0], b.x, b.y, s, s)
				end
			end
		end
	end

	-- ---------- 노트북 광선 ----------
	local function beams(S)
		local F = L.fx
		local p, time, gl = S.p, G.time, G.gl
		local fine = G.fxLv == 2
		for _, b in S.beams do
			local c = if b.perm then C_BPERM elseif b.evo then C_BEVO else C_BEAM
			local al = min(1, b.life / 0.14, (b.dur - b.life) / 0.05 + 0.2) * (if b.perm then 0.5 else 1)
			local cx, cy = cos(b.a), sin(b.a)
			local ox, oy = p.x + cx * 28, p.y - 24 + cy * 18 + sin(time * 9 + b.j) * 2
			local ex, ey = ox + cx * b.len, oy + cy * b.len
			local nx, ny = -cy, cx
			-- 빛줄기: 원본은 세 겹을 더하기 섞기로 얹고 번짐까지 더해, 밝은 바닥에서는 굵고 하얀 띠 + 넓게 퍼지는 색 테두리로 보인다.
			--  가장자리가 부드러운 띠 그림을 겹쳐 흉내 낸다: 넓은 색 번짐 → 흰 몸통 → 꽉 찬 흰 심. 끝 쪽은 점점 사라지는 띠로 잇는다
			local bf = min(1, al * (if b.perm then 1.8 else 1))
			local function soft(z: number, col: Color3, a: number, knee: number, lw: number)
				local kx, ky = ox + cx * b.len * knee, oy + cy * b.len * knee
				D.sline(F, z, ox, oy, kx, ky, lw, col, a)
				D.gline(F, z + 1, kx, ky, ex, ey, lw, col, a, true)
			end
			-- 꽉 찬 흰 띠의 폭: 진할 때(al = 1)는 넓은 겹까지 하얗게 날아가고, 옅을 때(재택근무의 늘 켜진 광선 0.5)는 가운데 겹만 하얗다
			local wMid, wWide = b.w * (if b.evo then 0.9 else 1.3), b.w * (if b.evo then 2 else 2.8)
			local solid = max(2.5, (wMid + (wWide - wMid) * math.clamp((al - 0.5) * 2, 0, 1)) * 0.8)
			soft(70, c, min(1, (if b.perm then 0.85 else 0.6) * bf), 0.8, wWide * 1.9)
			soft(72, WHITE, min(1, 0.95 * bf), 0.85, solid * 1.9)
			do
				local kx, ky = ox + cx * b.len * 0.88, oy + cy * b.len * 0.88
				D.line(F, 74, ox, oy, kx, ky, solid, WHITE, min(1, 0.92 * bf))
				D.gline(F, 75, kx, ky, ex, ey, solid, WHITE, min(1, 0.92 * bf))
			end
			if fine and #S.beams <= 2 then
				for sd = -1, 1, 2 do
					dashes(F, 76, ox + nx * b.w * 0.7 * sd, oy + ny * b.w * 0.7 * sd, ex + nx * b.w * 0.7 * sd, ey + ny * b.w * 0.7 * sd, 2, WHITE, 0.55 * al, 12, 30, time * 700)
				end
			end
			local gr = b.w * 1.2 + 18
			D.img(F, 77, "fx/glow", ox, oy, gr * 2, gr * 2, min(1, al * 0.8 * gl), nil, nil, if b.perm then C_BPERM_L elseif b.evo then C_BEVO_L else C_BEAM_L)
			D.img(F, 78, "fx/lap", ox - cx * 10, oy - cy * 8, 34, 34, 1, math.asin(math.clamp(cy, -0.6, 0.6)) * 0.6, cx < 0)
			if rnd() < 0.5 then
				local u = 0.1 + rnd() * 0.85
				G.P({
					k = "text", x = ox + cx * b.len * u + nx * (rnd() - 0.5) * b.w * 2.4, y = oy + cy * b.len * u + ny * (rnd() - 0.5) * b.w * 2.4, vx = cx * 120, vy = cy * 120 - 20, life = 0.35, size = 12,
					col = if b.perm then "255,235,150" elseif b.evo then "215,195,255" else "190,225,255", txt = if rnd() < 0.5 then "0" else "1", drag = 0.3,
				})
			end
		end
	end

	-- ---------- 그때그때의 효과 ----------
	local C_LGOLD, C_BUMP, C_BUMPE, C_BUMPG = rgb("255,190,70"), rgb("255,180,80"), rgb("255,110,60"), rgb("255,220,120")
	local C_RT_RING, C_RT_HAND, C_FILL = rgb("120,70,30"), rgb("229,72,77"), lite("255,170,60")
	local C_GENT, C_BOSSIN, C_BOSSD, C_BOSSP = rgb("255,225,140"), rgb("235,50,60"), rgb("255,70,80"), lite("255,90,90")
	local C_LASH, C_LASHE = lite("255,90,110"), lite("255,190,70")
	local C_RING, C_RINGE, C_RING2, C_RING2E = rgb("70,255,200"), rgb("255,140,70"), rgb("150,220,255"), rgb("255,80,170")
	local C_RING_B, C_RINGE_B, C_RING2_B, C_RING2E_B = D.bright("70,255,200"), D.bright("255,140,70"), D.bright("150,220,255"), D.bright("255,80,170")
	local C_RINGE_L, C_RING2E_L = lite("255,140,70"), lite("255,80,170")
	local C_STABW, C_STABQ = lite("215,232,255"), lite("255,220,140")
	local C_SH1, C_SH2 = rgb("255,215,104"), lite("255,236,170")
	local C_LVL = rgb("255,250,225")
	local C_ZAP, C_ZAPE = lite("90,200,255"), lite("255,214,110")
	local C_REM1, C_REM2 = lite("90,200,255"), lite("150,110,255")
	local LASH_SHARDS = { "255,90,120", "90,220,160", "120,170,255", "255,220,90" }

	local function effects(S)
		local F = L.fx
		local p, time, gl = S.p, G.time, G.gl
		local fus = S.fus
		local fine = G.fxLv == 2
		-- 이번 장면에 그릴 번개 가닥 수(많으면 겹과 꺾임을 줄인다)
		local zapLinks = 0
		for _, f in G.fxs do
			if f.k == "zap" then
				zapLinks += #f.pts / 2 - 1
			end
		end
		for _, f in G.fxs do
			local q = f.t / f.dur
			local k = f.k
			if k == "crack" then
				local al = if q < 0.6 then 1 else 1 - (q - 0.6) / 0.4
				local g = min(1, q * 9)
				local s = f.r / 100 * g
				D.img(F, 80, "fx/crack", f.x, f.y + 8, 190 * s, 120 * s, al, nil, sin(f.rot) < 0)
			elseif k == "lashspin" then
				local e3 = 1 - pow(1 - min(1, q / 0.75), 3)
				local th = f.rot + e3 * TAU * 1.12
				local al = if q < 0.7 then 1 else max(0, 1 - (q - 0.7) / 0.3)
				local R = f.r
				local cx, cy = p.x, p.y - 12
				for j = 0, 8 do
					D.arc(F, 81, cx, cy, R * 0.72, th - 0.22 * (j + 1), th - 0.22 * j, R * 0.5, C_LGOLD, min(1, al * 0.2 * (1 - j / 9) * gl), 0.8, 1)
				end
				D.arc(F, 82, cx, cy, R, th - 1.5, th, 3, WHITE, al * 0.8, 0.8)
				-- 넥타이: 곧게 편 그림을 반지름 방향으로 놓는다 (세로 0.8 눌림)
				local vx, vy = cos(th), sin(th) * 0.8
				local len = sqrt(vx * vx + vy * vy)
				D.img(F, 83, "fx/tie/1", cx + vx * R * 0.52, cy + vy * R * 0.52, R * len, f.w * 1.1, al, atan2(vy, vx))
				if rnd() < 0.7 then
					G.shards(p.x + cos(th) * R, p.y - 12 + sin(th) * R * 0.8, 1, 160, if f.gent then "255,215,110" else LASH_SHARDS[floor(rnd() * 4) + 1], 0.5, 5)
				end
				if not f.cr and q > 0.72 then
					f.cr = true
					G.ringFx(p.x, p.y, R * 1.15, "255,190,70", 0.3, 7)
				end
			elseif k == "bag" then
				local sc = 1.5 - 0.5 * q
				local z = 44 * sc
				local a = min(1, (1 - q) * 2.5)
				D.img(F, 84, "fx/glow", f.x, f.y - 8, z * 1.8, z * 1.8, min(1, 0.5 * (1 - q) * a * gl), nil, nil, C_BULL)
				D.img(F, 85, "st/pack/1", f.x, f.y - 8, z, z * 1.09, a, f.a + PI / 2 + (1 - q) * 0.5)
			elseif k == "bump" then
				local e3 = 1 - pow(1 - q, 3)
				local al = 1 - q
				local c = if f.evo then C_BUMPE else C_BUMP
				local R = f.r * (0.3 + 0.74 * e3)
				local cx, cy, ys = p.x, p.y + 4, 0.72
				D.oval(F, 86, cx, cy, R, R * ys, c, min(1, 0.2 * al * al * gl))
				D.arc(F, 87, cx, cy, R * 0.6, 0, TAU, 4 * al + 1, c, al * 0.5, ys)
				D.arc(F, 88, cx, cy, R, 0, TAU, 9 * al + 2, c, al * 0.85, ys)
				D.arc(F, 89, cx, cy, R, 0, TAU, 2.5 * al + 1, WHITE, al, ys)
				-- 어깨 앞으로 밀려 나가는 충격파
				D.arc(F, 90, cx, cy, R * 1.08, f.a - 0.7, f.a + 0.7, 30 * al + 2, c, al * 0.55, ys)
				D.arc(F, 91, cx, cy, R * 1.04, f.a - 0.62, f.a + 0.62, 12 * al + 2, WHITE, al * 0.95, ys)
				local r2 = R * (1.16 + 0.3 * e3)
				for j = 0, 9 do
					local an = f.rot + j / 10 * TAU
					D.arc(F, 92, cx, cy, r2, an - 0.08, an + 0.08, 5 * al + 1, c, al * 0.9, ys, 1)
				end
				if f.evo then
					D.arc(F, 93, cx, cy, R * 0.82, -f.rot + q * 6, -f.rot + q * 6 + 1.5, 4 * al + 1, C_BUMPG, al * 0.8, ys)
					D.arc(F, 93, cx, cy, R * 0.82, -f.rot + q * 6 + PI, -f.rot + q * 6 + PI + 1.5, 4 * al + 1, C_BUMPG, al * 0.8, ys)
				end
				for j = -2, 2 do
					local an = f.a + PI + j * 0.2
					local r0 = 22 + q * 26
					local r1 = r0 + 44 * (1 - q)
					D.line(F, 94, p.x + cos(an) * r0, p.y - 8 + sin(an) * r0 * 0.8, p.x + cos(an) * r1, p.y - 8 + sin(an) * r1 * 0.8, 2.5, WHITE, al * 0.7, true)
				end
			elseif k == "fcast" then
				local e3 = 1 - pow(1 - q, 3)
				local al = 1 - q
				local T = f.ty
				if T == "routine" then
					local cx, cy = f.x or p.x, (f.y or p.y) - 10
					local R = f.r * 1.5 * e3
					if R > 2 then
						D.img(F, 95, "fx/routinerays", cx, cy, 242 * R / 120, 242 * R / 120, min(1, al * gl), f.rot + q * 0.8)
					end
					local rr = f.r * e3
					if rr > 4 then
						D.ring(F, 96, cx, cy + 10, rr, 5 * al + 1, C_RT_RING, al * 0.8)
					end
					for j = 0, 11 do
						local an = j / 12 * TAU
						local r0 = f.r * 0.52 * e3
						local r1 = r0 + (if j % 3 ~= 0 then 7 else 13)
						D.line(F, 97, cx + cos(an) * r0, cy + 10 + sin(an) * r0, cx + cos(an) * r1, cy + 10 + sin(an) * r1, 3, WHITE, al, true)
					end
					local ha = -PI / 2 + q * TAU
					D.line(F, 98, cx, cy + 10, cx + cos(ha) * f.r * 0.42 * e3, cy + 10 + sin(ha) * f.r * 0.42 * e3, 4, C_RT_HAND, al, true)
				elseif T == "bulldozer" then
					local R = f.r * e3
					D.oval(F, 99, p.x, p.y, R, R * 0.8, C_FILL, min(1, al * 0.18 * gl))
					D.img(F, 100, "fx/hazardring", p.x, p.y, 194 * R / 90, 194 * R / 90 * 0.8, al)
				elseif T == "gentleman" then
					local R = f.r * e3
					D.img(F, 100, "fx/gentspiral", p.x, p.y - 6, 220 * R / 100, 220 * R / 100 * 0.82, min(1, al / 0.75))
					D.ovalRing(F, 101, p.x, p.y - 6, R, R * 0.82, C_GENT, al)
				elseif T == "remote" and f.as then
					local n = #f.as
					for j = 1, n do
						local a = f.as[j]
						local ox, oy = p.x + cos(a) * 56, p.y - 12 + sin(a) * 42
						local ex, ey = p.x + cos(a) * f.len, p.y - 12 + sin(a) * f.len
						local w = f.w * (1 - q * 0.7)
						D.gline(F, 102, ox, oy, ex, ey, w * 1.3, if j % 2 == 0 then C_REM2 else C_REM1, min(1, al * 0.6 * gl))
						D.gline(F, 103, ox, oy, ex, ey, max(2, w * 0.3), WHITE, al)
						D.spr(F, 104, if j % 2 == 0 then "fx/remote/1" else "fx/remote/0", ox, oy, min(1, q * 6), min(1, al * 2))
					end
				end
			elseif k == "bossin" then
				local rr2 = 70 + 10 * sin(time * 20)
				local g = 0.4 + 0.6 * q
				D.oval(F, 105, f.x, f.y, rr2 * g, rr2 * g * 0.7, C_BOSSIN, 0.16 + 0.2 * q)
				D.img(F, 106, "fx/dashring", f.x, f.y, 198 * rr2 / 96, 198 * rr2 / 96 * 0.7, 0.95, nil, nil, C_BOSSD)
				D.gline(F, 107, f.x, f.y, f.x, f.y - 520, 68 + 40 * (1 - q), C_BOSSP, min(1, 0.5 * q * gl))
				D.text(F, 108, "!", f.x, f.y + 10 - 10.8, 30 * G.TS, WHITE, 0.6 + 0.4 * sin(time * 26))
			elseif k == "lash" then
				local ext = if q < 0.3 then 1 - pow(1 - q / 0.3, 3) else 1
				local al = if q < 0.62 then 1 else max(0, 1 - (q - 0.62) / 0.38)
				local amp = f.w * 1.25 * max(0, 1 - q / 0.42)
				local Ln = f.len * ext
				local name = if f.evo then "fx/tie/1" else "fx/tie/0"
				local base, bw = if f.evo then 178 else 130, if f.evo then 38 else 28 -- 구운 그림의 길이 · 폭
				local W0, H0 = base + 16, if f.evo then 42 else 32
				local kx, ky = (12 + Ln) / (12 + base), f.w / bw
				local hx, hy = p.x, p.y - 10
				local N = 6
				for _, a in f.as do
					-- 채찍이 가르는 공기
					local tx, ty = hx + cos(a) * (12 + Ln), hy + sin(a) * (12 + Ln)
					D.sline(F, 109, hx + cos(a) * 12, hy + sin(a) * 12, tx, ty, f.w * 1.5, if f.evo then C_LASHE else C_LASH, min(1, al * 0.35 * (1 - q) * gl))
					-- 넥타이: 그림을 여섯 토막으로 잘라 물결을 따라 놓는다
					for i = 0, N - 1 do
						local u0, u1 = i / N, (i + 1) / N
						local function wave(u: number): (number, number)
							local X = u * W0 * kx
							local t = max(0, (X - 12) / max(1, Ln))
							return X, sin(t * 6.2 - q * 17) * amp * t
						end
						local X0, Y0 = wave(u0)
						local X1, Y1 = wave(u1)
						local mx, my = loc(hx, hy, a, (X0 + X1) / 2, (Y0 + Y1) / 2)
						local seg = hypot(X1 - X0, Y1 - Y0)
						local o = D.img(F, 110, name, mx, my, seg + 0.6, H0 * ky, al, a + atan2(Y1 - Y0, X1 - X0))
						D.crop(o, u0, u1)
					end
					if not f.cr and q >= 0.3 then
						G.flare(tx, ty, if f.evo then 34 else 30, "255,255,255", 0.16)
						G.ringFx(tx, ty, f.w * 1.3, if f.evo then "255,190,70" else "255,90,110", 0.22, 4)
						G.sparks(tx, ty, if f.evo then 16 else 9, 300, if f.evo then "255,220,120" else "255,200,200", 0.3, 2.4)
						if f.evo then
							for _, c in LASH_SHARDS do
								G.shards(tx, ty, 3, 240, c, 0.7, 5)
							end
						end
					end
				end
				if q >= 0.3 then
					f.cr = true
				end
			elseif k == "ring" then
				-- 원본: 떨리는 고리 세 겹(더하기 섞기) — 밝은 바닥에서는 흰 심 + 색 번짐으로 보인다
				local c, c2 = if f.evo then C_RINGE else C_RING, if f.evo then C_RING2E else C_RING2
				local cb, c2b = if f.evo then C_RINGE_B else C_RING_B, if f.evo then C_RING2E_B else C_RING2_B
				if q < 0.3 then
					D.disc(F, 111, p.x, p.y, f.r * 0.9, c, (1 - q / 0.3) * 0.16)
				end
				for j = 0, 2 do
					local qq = max(0, min(1, (q - j * 0.11) / (1 - j * 0.11)))
					if qq > 0 then
						local R = f.r * (1 - pow(1 - qq, 3))
						local amp = (if f.evo then 9 else 6) * (1 - qq)
						local al = 1 - qq
						local col = if j == 1 then c2 else c
						if R > 8 then
							D.ring(F, 112, p.x, p.y, R, 14 * al + 3, if j == 1 then c2b else cb, al * 0.35)
							if fine then
								-- 떨리는 물결 테두리
								local lobes = if f.evo then 10 else 14
								local n = 28
								local px0, py0
								for s2 = 0, n do
									local an = s2 / n * TAU
									local rr2 = R + sin(an * lobes + time * 26 + j * 2) * amp
									local x, y = p.x + cos(an) * rr2, p.y + sin(an) * rr2
									if px0 then
										D.line(F, 113, px0, py0, x, y, (3.5 * al + 1) * 1.2, WHITE, min(1, al * 1.2), true)
									end
									px0, py0 = x, y
								end
							else
								D.ring(F, 114, p.x, p.y, R, (3.5 * al + 1) * 1.2, WHITE, min(1, al * 1.2))
							end
						end
					end
				end
				if f.evo then
					local R = f.r * (1 - pow(1 - q, 3))
					for j = 0, 27 do
						local an = j / 28 * TAU
						local h = (10 + 26 * abs(sin(j * 1.9 + time * 34))) * (1 - q)
						D.line(F, 115, p.x + cos(an) * (R + 6), p.y + sin(an) * (R + 6), p.x + cos(an) * (R + 6 + h), p.y + sin(an) * (R + 6 + h), 5, if j % 2 == 1 then C_RINGE_L else C_RING2E_L, (1 - q) * 0.9, true)
					end
				end
			elseif k == "stab" then
				local fin = f.n == 2
				local im = if fus and fus.gentleman then "fx/gstabT" elseif f.quad then "fx/gstab/1" else "fx/gstab/0"
				local Lg, Hh = if fin then 196 else 150, if fin then 34 else 30
				local wc = if f.quad then C_STABQ else C_STABW
				local out = if fin then 1 - pow(1 - min(1, q / 0.22), 3) else sin(min(1, q / 0.75) * PI)
				local al = if fin then (if q < 0.7 then 1 else max(0, (1 - q) / 0.3)) else min(1, (1 - q) * 3.5)
				local jit = if fin then 0 else (if f.n ~= 0 then -0.13 else 0.13)
				local ox, oy = p.x, p.y - 8
				local function side(a0: number)
					local a = a0 + jit
					local tip = 18 + (f.range - 18) * (if fin then out else 0.35 + 0.65 * out)
					local x0 = if fin then min(tip - Lg, 16 + (tip - Lg - 16) * 0.35) else tip - Lg
					local LL = tip - x0
					if fin then
						local sl = max(0, 1 - q / 0.5)
						if sl > 0 and tip > 34 then
							local ax, ay = loc(ox, oy, a, 20, 0)
							local bx, by = loc(ox, oy, a, tip - 10, 0)
							D.line(F, 116, ax, ay, bx, by, Hh * 0.7, wc, min(1, 0.5 * sl * gl), true)
							for i = 1, 2 do
								local o = if i == 1 then -12 else 12
								ax, ay = loc(ox, oy, a, 26, o)
								bx, by = loc(ox, oy, a, tip - 30, o * 0.5)
								D.line(F, 117, ax, ay, bx, by, 2, WHITE, 0.85 * sl, true)
							end
						end
					end
					local gx, gy = loc(ox, oy, a, x0 - (if fin then 30 else 22) + LL / 2, 0)
					D.img(F, 118, im, gx, gy, LL, Hh, al * 0.3, a)
					gx, gy = loc(ox, oy, a, x0 + LL / 2, 0)
					D.img(F, 119, im, gx, gy, LL, Hh, al, a)
					if q < 0.3 then
						local fs = (if fin then 24 else 13) * (1 - q / 0.3)
						gx, gy = loc(ox, oy, a, tip, 0)
						D.img(F, 120, "fx/flare", gx, gy, fs * 2, fs * 2, 1)
					end
				end
				side(f.a)
				side(f.a + PI)
				if f.quad then
					side(f.a + PI / 2)
					side(f.a - PI / 2)
				end
			elseif k == "swipe" then
				local al = 1 - q
				local lunge = 1 - pow(1 - min(1, q / 0.2), 3)
				local reach = f.range
				local hold = if q < 0.72 then 1 else max(0, (1 - q) / 0.28)
				local ox, oy = p.x, p.y - 8
				local function side(a: number)
					local sa = al * min(1, q * 8)
					local la = sa * 0.45 * max(0, 1 - q * 2.2)
					if la > 0.01 then
						for i = -1, 1 do
							local o = i * 9
							local ax, ay = loc(ox, oy, a, reach * 0.2 * lunge, o)
							local bx, by = loc(ox, oy, a, reach * (0.55 + 0.3 * lunge), o * 0.4)
							D.line(F, 121, ax, ay, bx, by, 1.6, WHITE, la, true)
						end
					end
					local ux = reach - 104
					local pos = 14 + ux * lunge + (if q > 0.2 then -(q - 0.2) * 14 else 0)
					local gh = max(0, 1 - q / 0.3)
					local gx, gy
					if gh > 0 then
						gx, gy = loc(ox, oy, a, pos - 34 + 56, 0)
						D.img(F, 122, "fx/umb", gx, gy, 112, 26, hold * 0.22 * gh, a)
						gx, gy = loc(ox, oy, a, pos - 16 + 56, 0)
						D.img(F, 123, "fx/umb", gx, gy, 112, 26, hold * 0.45 * gh, a)
					end
					gx, gy = loc(ox, oy, a, pos + 56, 0)
					D.img(F, 124, "fx/umb", gx, gy, 112, 26, hold, a)
					if q < 0.22 then
						local fs = 18 * (1 - q / 0.22)
						gx, gy = loc(ox, oy, a, pos + 108, 0)
						D.img(F, 125, "fx/flare", gx, gy, fs * 2, fs * 2, 1)
					end
				end
				side(f.a)
				if f.both then
					side(f.a + PI)
				end
			elseif k == "shout" then
				local R = f.r * (1 - pow(1 - min(1, q * 1.5), 3))
				if R > 30 then
					D.ring(F, 126, p.x, p.y, R, 46 * (1 - q) + 4, C_SH1, min(1, (1 - q) * 0.45))
					D.ring(F, 127, p.x, p.y, R, 10 * (1 - q) + 2, C_SH2, (1 - q) * 0.9)
					D.ring(F, 128, p.x, p.y, R * 0.8, 3, WHITE, (1 - q) * 0.7)
				end
				for j = 0, 21 do
					local a = j / 22 * TAU + 0.2
					local r0 = 50 + q * 320 + (j % 3) * 26
					local r1 = r0 + 60 + (j % 2) * 50
					D.line(F, 129, p.x + cos(a) * r0, p.y + sin(a) * r0, p.x + cos(a) * r1, p.y + sin(a) * r1, if j % 2 == 1 then 2 else 4, WHITE, (1 - q) * 0.55, true)
				end
				local pop = min(1, q * 8)
				local sc = (0.4 + 0.6 * pop) * (1 + (if q < 0.25 then sin(q * 40) * 0.07 else 0))
				local rot = sin(q * 50) * 0.04 * (1 - q) - 0.05
				local a = min(1, (1 - q) * 3.5)
				D.spr(F, 130, if f.evo then "fx/shoutburst/1" else "fx/shoutburst/0", p.x, p.y - 80, sc, a, rot)
				D.text(F, 131, if f.evo then "저 내려요!!!" else "내릴게요!", p.x, p.y - 80, (if f.evo then 30 else 26) * sc * G.TS, C_INK, a, nil, nil, rot)
			elseif k == "level" then
				local w = 64 * (1 - q * 0.5)
				D.gline(F, 132, p.x, p.y + 10, p.x, p.y - 300, w * 1.7, C_LVL, min(1, (1 - q) * 1.2 * gl), true)
				D.gline(F, 133, p.x, p.y + 10, p.x, p.y - 330, w * 0.7, WHITE, min(1, (1 - q) * 0.9 * gl), true)
			elseif k == "zap" then
				local P_ = f.pts
				local c = if f.evo then C_ZAPE else C_ZAP
				local fr = floor(f.t / 0.045)
				local al = 1 - q * q
				local rs = G.srand(f.seed + fr * 977)
				local w1, w2 = if f.evo then 9 else 7, if f.evo then 3.4 else 2.6
				-- 이어지는 적이 많으면 가운데 겹을 빼고 꺾임을 줄인다(물건 수)
				local detail = fine and zapLinks <= 8
				local function stroke(x0: number, y0: number, x1: number, y1: number)
					if detail then
						D.line(F, 135, x0, y0, x1, y1, w1, c, al * 0.55, true)
					end
					D.line(F, 136, x0, y0, x1, y1, w2, WHITE, al, true)
				end
				for j = 1, #P_ - 3, 2 do
					local x0, y0, x1, y1 = P_[j], P_[j + 1], P_[j + 2], P_[j + 3]
					local len = hypot(x1 - x0, y1 - y0)
					local ln = if len == 0 then 1 else len
					local nx, ny = -(y1 - y0) / ln, (x1 - x0) / ln
					local seg = max(3, min(if detail then 9 elseif zapLinks > 20 then 3 else 5, floor(len / 16 + 0.5)))
					D.sline(F, 134, x0, y0, x1, y1, (if f.evo then 22 else 16) * 1.6, c, min(1, al * 0.3 * gl))
					local px0, py0 = x0, y0
					local bm = 0
					local bxs, bys = {}, {}
					bxs[0], bys[0] = x0, y0
					for s2 = 1, seg - 1 do
						local t = s2 / seg
						local o = (rs() - 0.5) * len * 0.26 * sin(t * PI) + (rs() - 0.5) * 8
						local x, y = x0 + (x1 - x0) * t + nx * o, y0 + (y1 - y0) * t + ny * o
						stroke(px0, py0, x, y)
						px0, py0 = x, y
						bxs[s2], bys[s2] = x, y
					end
					stroke(px0, py0, x1, y1)
					-- 곁가지
					if rs() < (if f.evo then 0.9 else 0.55) then
						bm = 1 + floor(rs() * (seg - 1))
						local bx, by = bxs[bm] or x0, bys[bm] or y0
						local ba = atan2(y1 - y0, x1 - x0) + (if rs() < 0.5 then 1 else -1) * (0.5 + rs() * 0.7)
						local bl = 22 + rs() * (if f.evo then 50 else 32)
						local mx, my = bx + cos(ba) * bl * 0.5 + (rs() - 0.5) * 10, by + sin(ba) * bl * 0.5 + (rs() - 0.5) * 10
						stroke(bx, by, mx, my)
						stroke(mx, my, bx + cos(ba) * bl, by + sin(ba) * bl)
					end
				end
			end
		end
	end

	function Wp.draw(S)
		weapons(S)
		Parts.draw(0)
		beams(S)
		effects(S)
		Parts.draw(1)
	end

	return Wp
end
