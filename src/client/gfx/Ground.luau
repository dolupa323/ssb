-- 바닥에 깔리는 것 · 줍는 것 (원본 gfx.js render의 「ground layer」 「pickups」)
--  기름 · 웅덩이 · 알람/시한폭탄 · 핫팩 · 자국 · 공격 예고 · 음파 고리 · 보스 예고 · 레벨 업/대시 자국 · 원두 · 아이템
return function(G)
	local D, Sim = G.D, G.Sim
	local L = G.L
	local rgb = D.rgb
	local lite = D.lite
	local rnd = math.random
	local cos, sin, atan2, floor, min, max, sqrt, pow = math.cos, math.sin, math.atan2, math.floor, math.min, math.max, math.sqrt, math.pow
	local TAU, PI = math.pi * 2, math.pi
	local WEAPONS, EVO, SPIN_R = Sim.WEAPONS, Sim.EVO, Sim.SPIN_R
	local WHITE = D.WHITE
	local C_INK = rgb("#1f262b")
	local inView = D.inView

	local Gr = {}

	local C_PUD_E, C_PUD = lite("150,90,220"), lite("255,150,70")
	local C_TB, C_TBD, C_TBR = rgb("150,96,54"), rgb("120,70,36"), rgb("255,200,60")
	local C_AL, C_ALR = rgb("255,214,90"), rgb("255,226,120")
	local C_FLAMEW = lite("255,236,190")
	local C_HOT, C_HOTE = lite("255,180,90"), lite("255,110,60")
	local C_STAMP = rgb("#d23338")
	local ZCOL = { bass = rgb("255,50,170"), nag = rgb("255,130,30") }
	local C_ZONE = rgb("235,50,60")
	local C_DOORTXT, C_BASSR, C_BASSD, C_BASSP, C_SWAT = rgb("255,201,40"), rgb("255,150,210"), rgb("#232b2e"), rgb("#ff5fb8"), rgb("255,120,100")
	local NAGW = { "말이야", "라떼는", "자네", "요즘", "...", "근데" }
	local WAVE_TXT = { "잔", "소", "리", "!" }
	local C_NAGEDGE, C_GAP = rgb("120,50,0"), rgb("109,255,165")
	local C_SPINZ, C_SPINR, C_DASHL = rgb("229,60,66"), rgb("255,90,96"), rgb("#e5484d")
	local C_GOLD, C_DASH = lite("255,215,104"), lite("160,255,220")
	local C_BEAN2, C_BEAN1, C_PASS, C_PILLAR = lite("255,215,104"), lite("230,160,90"), lite("90,255,160"), lite("255,225,140")

	-- 점선 고리(구운 그림: 반지름 96 · 굵기 3) — 반지름 r에 맞춰 늘이고 돌린다
	local function dashRing(Ly, z: number, x: number, y: number, r: number, col: Color3, alpha: number, rot: number)
		local s = 198 * r / 96
		D.img(Ly, z, "fx/dashring", x, y, s, s, alpha, rot, nil, col)
	end

	function Gr.draw(S)
		local Gd = L.ground
		local p, time, gl = S.p, G.time, G.gl

		-- 미끄러운 기름
		for _, s in S.slicks do
			if inView(s.x, s.y, s.r) then
				local k = s.r / 38
				D.img(Gd, 1, "fx/slick", s.x, s.y, 88 * k, 72 * k, min(1, s.life / 0.6))
			end
		end
		-- 커피 웅덩이 · 껌
		for _, u in S.puddles do
			if inView(u.x, u.y, u.r) then
				local age = u.dur - u.life
				local grow = min(1, age / 0.18)
				local ease = 1 - pow(1 - grow, 3) + sin(grow * PI) * 0.12
				local a = min(1, u.life / 0.5)
				local R = u.r * ease
				local name, base
				if u.gum then
					name, base = if u.evo then "fx/puddle/gum/evo" else "fx/puddle/gum", 40
				else
					name, base = if u.evo then "fx/puddle/coffee/evo" else "fx/puddle/coffee", 54
				end
				local k = R / base
				D.img(Gd, 2, name, u.x, u.y, base * 2.24 * k, base * 1.92 * k, a)
				if u.gum then
					-- 풍선이 터질 때 튀는 방울
					local cyc = (time * 0.8 + u.ph) % 1
					if cyc > 0.94 and rnd() < 0.35 then
						local br = R * (if u.evo then 0.5 else 0.38) * pow(cyc, 0.6)
						for _ = 1, 5 do
							local an = rnd() * TAU
							G.P({ k = "dot", x = u.x + R * 0.08 + cos(an) * br, y = u.y - br * 0.5 + sin(an) * br, vx = cos(an) * 80, vy = sin(an) * 80, life = 0.3, size = 4, col = "255,170,210", drag = 0.4 })
						end
					end
				end
				D.img(Gd, 3, "fx/glow", u.x, u.y, R * 2.4, R * 2.4, min(1, 0.1 * a * gl), nil, nil, if u.evo then C_PUD_E else C_PUD)
			end
		end
		-- 알람 · 커피 시한폭탄
		for _, m in S.mines do
			if inView(m.x, m.y, m.r) then
				local q = 1 - m.fuse / m.dur
				if m.tb then
					local pop = if m.again then 1 else min(1, q * 6)
					local late = if m.again then 1 elseif q > 0.7 then (q - 0.7) / 0.3 else 0
					D.disc(Gd, 10, m.x, m.y, m.r, C_TB, 0.07 + 0.07 * q)
					dashRing(Gd, 11, m.x, m.y, m.r, C_TBD, 0.7, 0)
					-- 남은 시간: 테두리가 시곗바늘처럼 차오른다
					D.arc(Gd, 12, m.x, m.y, m.r, -PI / 2, -PI / 2 + TAU * q, 4, C_TBR, 0.9)
					D.img(Gd, 13, "st/shadow", m.x, m.y + 16.5, 34, 15)
					local sc = pop * (1 + late * 0.18)
					local rot = sin(time * 60) * 0.12 * late
					local cx, cy = m.x + sin(time * 80) * 2.2 * late, m.y - 6
					if sc > 0.02 then
						D.spr(Gd, 14, "fx/tbcup", cx, cy, sc, 1, rot)
						local ha = -PI / 2 + TAU * q
						local cr, sr = cos(rot), sin(rot)
						local function pt(lx: number, ly: number): (number, number)
							return cx + (lx * cr - ly * sr) * sc, cy + (lx * sr + ly * cr) * sc
						end
						local x0, y0 = pt(0, 2)
						local x1, y1 = pt(cos(ha) * 5.6, 2 + sin(ha) * 5.6)
						D.line(Gd, 15, x0, y0, x1, y1, 1.8 * sc, C_INK, 1, true)
						D.img(Gd, 16, "prim/disc", x0, y0, 2.9 * sc, 2.9 * sc, 1, nil, nil, C_INK)
					end
					for sd = -1, 1, 2 do
						local sy = m.y - 30 - ((time * 22 + sd * 5) % 10)
						D.line(Gd, 17, m.x + sd * 5, sy, m.x + sd * 6.5, sy - 4, 1.8, WHITE, 0.7, true)
						D.line(Gd, 17, m.x + sd * 6.5, sy - 4, m.x + sd * 5, sy - 8, 1.8, WHITE, 0.7, true)
					end
				else
					D.disc(Gd, 10, m.x, m.y, m.r, C_AL, 0.1 + 0.08 * q)
					if m.r * q > 1 then
						D.disc(Gd, 18, m.x, m.y, m.r * q, C_AL, 0.16)
					end
					dashRing(Gd, 11, m.x, m.y, m.r, C_TBR, 0.85, time * 50 / m.r)
					D.img(Gd, 13, "st/shadow", m.x, m.y + 13, 30, 14)
					local sh = sin(time * 70) * (0.08 + 0.3 * q)
					local cs = 1 + q * 0.25
					local cx, cy = m.x + sin(time * 90) * 2 * q, m.y - 4
					D.img(Gd, 14, "fx/clock", cx + 2 * cs * sin(sh), cy - 2 * cs * cos(sh), 34 * cs, 36 * cs, 1, sh)
					local ra = 0.5 + 0.4 * sin(time * 40)
					D.arc(Gd, 19, m.x + 8, m.y - 18, 9 + q * 5, -1.3, -0.5, 2, C_ALR, ra, nil, 2)
					D.arc(Gd, 19, m.x - 8, m.y - 18, 9 + q * 5, PI + 0.5, PI + 1.3, 2, C_ALR, ra, nil, 2)
				end
			end
		end
		-- 핫팩
		local l = G.wl(S, "hotpack")
		if l > 0 then
			local s = WEAPONS.hotpack.stat(l)
			local ev = l >= EVO
			local r = s.r * S.M.area * (1 + sin(time * 7) * 0.025)
			if ev then
				D.img(Gd, 20, "fx/heatring/1", p.x, p.y, 324 * r / 160, 324 * r / 160)
			else
				D.img(Gd, 20, "fx/heatring/0", p.x, p.y, 176 * r / 86, 176 * r / 86)
			end
			for j = 0, 1 do
				local q = (time * 0.9 + j * 0.5) % 1
				D.ring(Gd, 21, p.x, p.y, r * (0.3 + 0.7 * q), 3, if ev then C_HOTE else C_HOT, min(1, (1 - q) * 0.35 * gl))
			end
			local n = max(10, floor(TAU * r / (if ev then 24 else 28)))
			for j = 0, n - 1 do
				local an = j / n * TAU + time * 0.35
				local fl = 0.75 + 0.35 * sin(time * 11 + j * 2.3) + 0.2 * sin(time * 17 + j * 5.1)
				local sz = (if ev then 26 else 19) * fl * 1.15
				local fx, fy = p.x + cos(an) * r * 0.96, p.y + sin(an) * r * 0.96 - sz * 0.5
				D.img(Gd, 22, "fx/flame", fx, fy, sz, sz * 1.5, 1)
				-- 원본의 불꽃은 더하기 섞기라 속이 하얗게 탄다
				D.img(Gd, 23, "fx/glow", fx, fy + sz * 0.12, sz * 1.05, sz * 1.4, min(1, 0.8 * gl), nil, nil, C_FLAMEW)
			end
		end
		-- 바닥에 남는 자국
		for _, d in G.decals do
			local a = min(1, (d.life - d.t) / 0.6) * 0.75
			if d.kind == "stamp" then
				D.shape(Gd, 30, d.x, d.y, d.r * 1.56 - 5, (d.r - 5) * 0.86, nil, nil, C_STAMP, a, 5, 8, d.rot)
				D.shape(Gd, 31, d.x, d.y, d.r * 1.36 - 2, (d.r * 0.8 - 2) * 0.86, nil, nil, C_STAMP, a, 2, 5, d.rot)
				D.text(Gd, 32, "결재", d.x, d.y + 2, d.r * 0.62 * G.TS, C_STAMP, a, nil, nil, d.rot)
			else
				D.img(Gd, 33, "fx/crackdecal", d.x, d.y, 1.6 * d.r, 1.6 * d.r * 0.86, a, d.rot * 2)
			end
		end
		-- 공격 예고 (범위 · 차오르는 속 · 무엇이 떨어지는지)
		for _, z in S.zones do
			if inView(z.x, z.y, z.r + 160) then
				local q = 1 - z.warn / z.dur
				local K = z.kind
				local pulse = 0.25 + 0.25 * sin(time * 24)
				local col = ZCOL[K] or C_ZONE
				D.disc(Gd, 40, z.x, z.y, z.r, col, 0.15)
				if z.r * q > 1 then
					D.disc(Gd, 41, z.x, z.y, z.r * q, col, 0.3)
				end
				dashRing(Gd, 42, z.x, z.y, z.r, col, 0.95, -time * 60 / z.r)
				D.ring(Gd, 43, z.x, z.y, z.r, 10, col, pulse)
				if K == "stamp" then
					local h, sc = (1 - q * q) * 150, z.r / 46
					local g = 0.5 + q * 0.4
					D.img(Gd, 44, "st/shadow", z.x - z.r * g + z.r * (1 + q * 0.8) / 2, z.y - z.r * 0.2 * g + z.r * 0.5 * (1 + q * 0.8) / 2, z.r * (1 + q * 0.8), z.r * 0.5 * (1 + q * 0.8), 0.25 + 0.3 * q)
					D.img(Gd, 45, "st/stamp", z.x, z.y - 29 * sc - h, 96 * sc, 110 * sc, min(1, q * 3))
				elseif K == "door" then
					-- 양옆에서 닫히는 문짝: 원 밖에 있는 부분은 잘라 낸다
					local w, hh, off = z.r * 0.62, z.r * 1.5, (1 - q * q) * z.r * 1.1
					local f = math.clamp((z.r - off) / w, 0, 1)
					if f > 0.02 then
						local a = 0.55 + 0.4 * q
						local o = D.img(Gd, 44, "st/doorp", z.x + off + w * f / 2, z.y, w * f, hh, a)
						D.crop(o, 0, f)
						o = D.img(Gd, 44, "st/doorp", z.x - off - w * f / 2, z.y, w * f, hh, a)
						D.crop(o, 1 - f, 1)
					end
					D.text(Gd, 49, "출입문 닫습니다", z.x, z.y - z.r - 8 - 5.8, 16 * G.TS, C_DOORTXT, 0.6 + 0.4 * sin(time * 20))
				elseif K == "bass" then
					for k = 0, 2 do
						local rr2 = z.r * ((time * 2.4 + k / 3) % 1)
						if rr2 > 2.5 then
							D.ring(Gd, 46, z.x, z.y, rr2, 4, C_BASSR, (1 - rr2 / z.r) * 0.9)
						end
					end
					local b = 1 + 0.18 * sin(time * 30)
					D.shape(Gd, 47, z.x, z.y, z.r * 0.44 * b - 3, z.r * 0.44 * b - 3, C_BASSD, 1, C_BASSP, 1, 3)
					D.disc(Gd, 48, z.x, z.y, z.r * 0.08 * b, C_BASSP, 1)
				elseif K == "nag" then
					local a = 0.5 + 0.5 * q
					for k = 0, 5 do
						local an = k / 6 * TAU + time * 0.8
						local d = z.r * (0.3 + 0.5 * ((k * 37 % 10) / 10)) * (0.5 + 0.5 * q)
						local bx, by = z.x + cos(an) * d, z.y + sin(an) * d * 0.8 - ((time * 30 + k * 17) % 22)
						D.shape(Gd, 46, bx, by - 2, 52, 20, WHITE, 0.85 * a, C_INK, a, 2, 8)
						D.text(Gd, 47, NAGW[k + 1], bx, by + 3 - 5.4, 15 * G.TS, C_INK, a)
					end
				elseif K == "meet" then
					local sc = z.r / 70 * (0.6 + 0.4 * q)
					D.img(Gd, 45, "st/table", z.x, z.y, 160 * sc, 120 * sc, 0.45 + 0.5 * q)
				elseif K == "swat" then
					local a = -2.4 + q * 3.2
					D.arc(Gd, 44, z.x, z.y, z.r * 0.6, a - 0.7, a, 14, C_SWAT, 0.5)
					D.img(Gd, 45, "st/pack/0", z.x + cos(a) * z.r * 0.6, z.y + sin(a) * z.r * 0.6, 54, 59, 0.6 + 0.4 * q, a + 1.6)
				end
				if K ~= "nag" and K ~= "door" then
					local sz = 24 + q * 8
					local ty = z.y + (if K == "stamp" or K == "meet" or K == "bass" then z.r * 0.78 else 10)
					D.text(Gd, 49, if z.txt and z.txt ~= "" then z.txt else "쿵", z.x, ty - sz * 0.36, sz * G.TS, col, 0.75)
				end
			end
		end
		-- 퍼지는 음파 고리: 틈(gap ± gw)으로 빠져나가야 한다
		for _, w in S.waves do
			local a = min(1, (w.max - w.r) / 120)
			local g0, g1 = w.gap + w.gw, w.gap - w.gw + TAU
			local K = w.kind
			D.arcImg(Gd, 50, if K == "nag" then "prim/wave/nag" elseif K == "push" then "prim/wave/push" else "prim/wave/bass", w.x, w.y, w.r, g0, g1, 28, -3.5, a)
			if K == "nag" and w.r > 60 then
				local step = 34 / w.r
				local an, k = g0 + step, 0
				while an < g1 - step do
					local tx, ty = w.x + cos(an) * (w.r + 16), w.y + sin(an) * (w.r + 16)
					if inView(tx, ty, 20) then
						D.text(Gd, 51, WAVE_TXT[k % 4 + 1], tx, ty, 17 * G.TS, WHITE, a, C_NAGEDGE, 1.5)
					end
					an += step
					k += 1
				end
			end
			if K == "push" and w.r > 40 then
				local step = 44 / w.r
				local an = g0 + step
				while an < g1 - step do
					local tx, ty = w.x + cos(an) * (w.r + 12), w.y + sin(an) * (w.r + 12)
					if inView(tx, ty, 20) then
						D.img(Gd, 52, "prim/tri", tx, ty, 12, 10, 0.8 * a, an + PI / 2)
					end
					an += step
				end
			end
			for i = 1, 2 do
				local ga = if i == 1 then g0 else g1
				local tx, ty = w.x + cos(ga) * w.r, w.y + sin(ga) * w.r
				if inView(tx, ty, 10) then
					D.img(Gd, 53, "prim/disc", tx, ty, 12.4, 12.4, 0.9 * a, nil, nil, C_GAP)
				end
			end
		end
		-- 보스 예고: 백팩 빌런의 회전 범위 · 돌진 길
		for _, e in S.bosses do
			if not e.dead then
				local st = e.st
				if e.type == "bagman" and (st == 3 or st == 4) then
					local q = if st == 3 then 1 - e.tm / 0.75 else 1
					D.disc(Gd, 60, e.x, e.y, SPIN_R, C_SPINZ, if st == 3 then 0.14 + 0.1 * sin(time * 26) else 0.12)
					if SPIN_R * q > 1 then
						D.disc(Gd, 61, e.x, e.y, SPIN_R * q, C_SPINZ, 0.25)
					end
					dashRing(Gd, 62, e.x, e.y, SPIN_R, C_SPINR, 0.95, -time * 60 / SPIN_R)
				end
				if (e.type == "lead" or e.type == "bagman" or e.type == "carrierboss") and st == 1 then
					local len = if e.type == "lead" then 480 else 380
					D.line(Gd, 63, e.x, e.y, e.x + e.dx * len, e.y + e.dy * len, e.r * 2, C_DASHL, 0.3 + 0.2 * sin(time * 30))
				end
			end
		end
		-- 레벨 업 고리와 빛살 · 대시 자국
		for _, f in G.fxs do
			local q = f.t / f.dur
			if f.k == "level" then
				for j = 0, 1 do
					local qq = max(0, min(1, q * 1.3 - j * 0.18))
					if qq > 0.02 and qq < 1 then
						D.arc(Gd, 70, p.x, p.y + 8, 190 * qq, 0, TAU, (10 * (1 - qq) + 1.5) * 1.6, C_GOLD, min(1, (1 - qq) * 0.9 * gl), 84 / 190)
					end
				end
				local ra = (1 - q) * 0.22 * gl
				for j = 1, 8 do
					local ph = time * 1.6 + j * TAU / 8
					-- 세로로 0.45 눌린 빛살: 꼭짓점이 발밑, 밑변이 150 밖
					local vx, vy = sin(ph) * 150, -cos(ph) * 150 * 0.45
					local len = sqrt(vx * vx + vy * vy)
					local wd = 28 * sqrt(cos(ph) ^ 2 + (0.45 * sin(ph)) ^ 2)
					D.img(Gd, 71, "prim/tri", p.x + vx / 2, p.y + 8 + vy / 2, wd, len, ra, atan2(-vx, vy), nil, C_GOLD)
				end
			elseif f.k == "dash" then
				local dx, dy = p.x - f.x, p.y - f.y
				if dx * dx + dy * dy > 4 then
					D.gline(Gd, 72, p.x, p.y - 10, f.x, f.y - 10, 22 * (1 - q), C_DASH, min(1, (1 - q) * 0.75 * gl), true)
					D.line(Gd, 73, f.x + dx * 0.3, f.y + dy * 0.3 - 10, p.x, p.y - 10, max(0.5, 5 * (1 - q)), WHITE, (1 - q) * 0.9, true)
				end
			end
		end

		-- ---------- 줍는 것 ----------
		local Pk = L.pick
		local vx0, vy0, vx1, vy1 = D.vx0 - 12, D.vy0 - 12, D.vx1 + 12, D.vy1 + 12
		for _, b in S.beans do
			local bx, by0 = b.x, b.y
			if bx > vx0 and bx < vx1 and by0 > vy0 and by0 < vy1 then
				local v = b.v
				local by = by0 + sin(time * 4 + b.ph) * 1.6
				if v >= 8 then
					D.img(Pk, 1, "fx/glow", bx, by, 30, 30, min(1, 0.55 * gl), nil, nil, C_BEAN2)
					D.img(Pk, 4, "st/bean/2", bx, by, 20, 16)
				elseif v >= 3 then
					D.img(Pk, 1, "fx/glow", bx, by, 20, 20, min(1, 0.55 * gl), nil, nil, C_BEAN1)
					D.img(Pk, 3, "st/bean/1", bx, by, 20, 16)
				else
					D.img(Pk, 2, "st/bean/0", bx, by, 20, 16)
				end
			end
		end
		for _, it in S.items do
			if inView(it.x, it.y, 60) then
				local by = it.y + sin(it.t * 4) * 3
				D.img(Pk, 5, "st/shadow", it.x, it.y + 14, 28, 12)
				if it.kind == "chest" then
					for k = 1, 6 do
						local ph = it.t * 0.8 + k * TAU / 6
						local vx, vy = sin(ph) * 62, -cos(ph) * 62
						D.img(Pk, 6, "prim/tri", it.x + vx / 2, by + vy / 2, 18, 62, min(1, 0.22 * gl), atan2(-vx, vy), nil, C_GOLD)
					end
					D.gline(Pk, 7, it.x, by, it.x, by - 190, 40, C_PILLAR, min(1, (0.3 + 0.1 * sin(it.t * 5)) * gl))
					D.img(Pk, 8, "fx/glow", it.x, by, 76, 76, min(1, 0.7 * gl), nil, nil, C_GOLD)
					D.img(Pk, 9, "st/chest", it.x, by - 1, 44, 40)
				else
					D.img(Pk, 8, "fx/glow", it.x, by, 48, 48, min(1, 0.5 * gl), nil, nil, if it.kind == "pass" then C_PASS else WHITE)
					D.img(Pk, 9, if it.kind == "pass" then "st/pass" else "st/kimbap", it.x, by, 36, 36)
				end
			end
		end
	end

	return Gr
end
