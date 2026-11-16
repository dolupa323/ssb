-- 입자 · 숫자 · 이벤트 처리 (원본 gfx.js의 P · sparks · ringFx · flare · light · puff · shards · addNum · consume · stepFx · drawParts)
return function(G)
	local D, Sim = G.D, G.Sim
	local L = G.L
	local rgb = D.rgb
	local rnd = math.random
	local cos, sin, atan2, sqrt, floor, min, max, abs, pow = math.cos, math.sin, math.atan2, math.sqrt, math.floor, math.min, math.max, math.abs, math.pow
	local TAU, PI = math.pi * 2, math.pi
	local WEAPONS, EVO, TRAIN_LEN = Sim.WEAPONS, Sim.EVO, Sim.TRAIN_LEN
	local WHITE = D.WHITE
	local C_INK = rgb("#1f262b")

	local Pm = {}
	local parts, nums, fxs, corpses, ghosts, decals, says, pk = G.parts, G.nums, G.fxs, G.corpses, G.ghosts, G.decals, G.says, G.pk
	-- 카드 · 손잡이가 지나온 자리(꼬리). 규칙 쪽 표를 건드리지 않게 따로 든다
	local trails = setmetatable({} :: any, { __mode = "k" }) :: any
	G.trails = trails

	local function round(v: number): number
		return floor(v + 0.5)
	end
	local function hypot(x: number, y: number): number
		return sqrt(x * x + y * y)
	end

	-- 합친 무기는 재료 둘의 모습이 그대로 보인다 (원본 wl)
	local REPL = { backpack = true, shoulder = true, coffee = true, alarm = true, umbrella = true, tie = true }
	local function wl(S, k: string): number
		local l = S.weapons[k]
		if l then
			return l
		end
		if S.fsrc and S.fsrc[k] and not REPL[k] then
			return EVO
		end
		return 0
	end
	G.wl = wl

	-- ---------- 입자 만들기 ----------
	local function P(o)
		local fxLv = G.fxLv
		if fxLv < 2 and o.k ~= "text" and rnd() < (if fxLv ~= 0 then 0.45 else 0.78) then
			return
		end
		if #parts > (if fxLv == 2 then 700 elseif fxLv ~= 0 then 420 else 220) then
			table.remove(parts, 1)
		end
		o.t = 0
		if o.k == "text" then
			if o.rot == nil then
				o.rot = (rnd() - 0.5) * 0.3
			end
			if o.vr == nil then
				o.vr = 0
			end
		end
		if o.rot == nil then
			o.rot = rnd() * TAU
		end
		if o.vr == nil then
			o.vr = (rnd() - 0.5) * 10
		end
		o.vx = o.vx or 0
		o.vy = o.vy or 0
		o.g = o.g or 0
		if o.drag == nil then
			o.drag = 0.06
		end
		if type(o.col) == "string" then
			o.white = o.col == "255,255,255"
			if o.k == "glow" or o.k == "star" or o.soft then
				o.lcol = D.lite(o.col)
				o.hcol = D.hot(o.col)
			elseif o.k == "ring" then
				o.rcol = D.bright(o.col)
			end
			o.col = rgb(o.col)
		end
		parts[#parts + 1] = o
	end
	local function sparks(x: number, y: number, n: number, spd: number, col: string, life: number, w: number?, dir: number?, spread: number?)
		for _ = 1, n do
			local a = if dir == nil then rnd() * TAU else dir + (rnd() - 0.5) * (spread or 1)
			local s = spd * (0.4 + rnd() * 0.6)
			P({ k = "spark", x = x, y = y, vx = cos(a) * s, vy = sin(a) * s, life = life * (0.6 + rnd() * 0.4), size = w or 2.2, col = col })
		end
	end
	local function ringFx(x: number, y: number, r: number, col: string, life: number, w: number?)
		P({ k = "ring", x = x, y = y, life = life, size = r, col = col, w = w or 5, drag = 1 })
	end
	local function flare(x: number, y: number, size: number, col: string, life: number)
		P({ k = "star", x = x, y = y, life = life, size = size, col = col, vr = (rnd() - 0.5) * 5, drag = 1 })
	end
	local function light(x: number, y: number, r: number, col: string, life: number)
		P({ k = "glow", x = x, y = y, life = life, size = r, col = col, drag = 1 })
	end
	local function puff(x: number, y: number, n: number, spd: number, col: string, life: number, size: number)
		for _ = 1, n do
			local a, s = rnd() * TAU, spd * rnd()
			P({ k = "smoke", x = x + (rnd() - 0.5) * 8, y = y + (rnd() - 0.5) * 8, vx = cos(a) * s, vy = sin(a) * s - 14, life = life * (0.7 + rnd() * 0.5), size = size * (0.7 + rnd() * 0.6), col = col, drag = 0.2, vr = (rnd() - 0.5) * 2 })
		end
	end
	local function shards(x: number, y: number, n: number, spd: number, col: string, life: number, size: number)
		for _ = 1, n do
			local a, s = rnd() * TAU, spd * (0.4 + rnd() * 0.6)
			P({ k = "shard", x = x, y = y, vx = cos(a) * s, vy = sin(a) * s - spd * 0.5, g = spd * 2.2, life = life * (0.7 + rnd() * 0.4), size = size * (0.6 + rnd() * 0.8), col = col, drag = 0.5 })
		end
	end
	local function addNum(x: number, y: number, v: any, c: number)
		if #nums > 70 then
			table.remove(nums, 1)
		end
		nums[#nums + 1] = { x = x + (rnd() - 0.5) * 12, y = y, v = tostring(v), c = c, t = 0, vx = (rnd() - 0.5) * 46, vy = if c >= 2 then -70 else -95 }
	end
	Pm.P, Pm.sparks, Pm.ringFx, Pm.flare, Pm.light, Pm.puff, Pm.shards, Pm.addNum = P, sparks, ringFx, flare, light, puff, shards, addNum
	G.P, G.sparks, G.ringFx, G.flare, G.light, G.puff, G.shards = P, sparks, ringFx, flare, light, puff, shards

	local SRC = {
		scooter = "120,240,255", selfie = "255,240,200", handle = "225,235,245", alarm = "255,214,90", card = "90,255,160", battery = "120,220,255",
		coffee = "214,150,96", hotpack = "255,170,80", umbrella = "200,225,255", backpack = "150,200,255", anc = "90,255,200", shout = "255,226,120", train = "255,226,120",
	}
	local FUSE_COL = { "255,90,120", "255,200,60", "90,220,160", "120,150,255" }
	local NAG_TXT = { "!", "?!", "...", "말이야" }

	-- ---------- 이벤트 → 효과 (원본 consume) ----------
	function Pm.consume(S)
		local p, E = S.p, S.ev
		local time = G.time
		for i = 1, #E do
			local e = E[i]
			local k = e.k
			if k == "num" then
				addNum(e.x, e.y, round(e.v), if e.crit then 1 else 0)
				if e.crit then
					flare(e.x, e.y + 8, 22, "255,214,90", 0.2)
				end
			elseif k == "hit" then
				local c = SRC[e.src] or "255,255,255"
				local a = atan2(e.y - p.y, e.x - p.x)
				flare(e.x, e.y - 8, if e.src == "backpack" or e.src == "umbrella" then 16 else 10, c, 0.14)
				sparks(e.x, e.y - 8, 3, 230, c, 0.22, 2, a, 1.3)
				if rnd() < 0.4 then
					ringFx(e.x, e.y - 8, 16, c, 0.16, 3)
				end
				if e.src == "card" then
					P({ k = "tag", x = e.x, y = e.y - 8, life = 0.26, size = 19, col = c, rot = PI / 4, vr = 0 })
				end
			elseif k == "kill" then
				local c = SRC[e.src] or "255,255,255"
				if e.boss then
					flare(e.x, e.y, 150, "255,236,170", 0.6)
					light(e.x, e.y, 260, "255,220,140", 0.7)
					for j = 0, 2 do
						ringFx(e.x, e.y, 150 + j * 90, "255,215,104", 0.5 + j * 0.2, 9)
					end
					sparks(e.x, e.y, 60, 560, "255,226,140", 0.9, 3)
					shards(e.x, e.y, 22, 260, "255,255,255", 1, 6)
					puff(e.x, e.y, 12, 120, "235,230,220", 1, 34)
					for _ = 1, 26 do
						local a, s = rnd() * TAU, 120 + rnd() * 320
						P({ k = "star", x = e.x, y = e.y, vx = cos(a) * s, vy = sin(a) * s, life = 0.7 + rnd() * 0.5, size = 9 + rnd() * 8, col = "255,215,104", drag = 0.12 })
					end
					G.flash = max(G.flash, 0.6)
					G.stopT = max(G.stopT, 0.14)
					G.zoomKick = max(G.zoomKick, 0.08)
				else
					if #corpses > 90 then
						table.remove(corpses, 1)
					end
					local vx, vy = e.vx or 0, e.vy or 0
					local m = hypot(vx, vy)
					if m < 140 then
						local dx, dy = e.x - p.x, e.y - p.y
						local d = hypot(dx, dy)
						if d == 0 then
							d = 1
						end
						vx, vy = dx / d * 190, dy / d * 190
					end
					local tr = e.src == "train"
					local ch = G.chars[e.type]
					if ch then
						corpses[#corpses + 1] = {
							type = e.type, v = e.seed % ch.nv, sc = e.sc or 1, dir = if vx >= 0 then -1 else 1, x = e.x, y = e.y, vx = vx, vy = vy, t = 0,
							life = if tr then 0.7 else 0.44, up = if tr then 70 else 24, vr = (if rnd() < 0.5 then -1 else 1) * (7 + rnd() * 8),
						}
					end
					puff(e.x, e.y + 4, 2, 40, "236,232,222", 0.38, 13)
					ringFx(e.x, e.y - 6, if e.elite then 70 else 24, "255,255,255", if e.elite then 0.34 else 0.2, if e.elite then 6 else 3)
					sparks(e.x, e.y - 6, 3, 220, c, 0.24, 2.2, atan2(vy, vx), 1.5)
					if e.elite then
						flare(e.x, e.y - 8, 70, "255,214,90", 0.36)
						light(e.x, e.y, 130, "255,200,110", 0.4)
						sparks(e.x, e.y - 8, 18, 340, "255,214,90", 0.5, 2.8)
						for _ = 1, 8 do
							local a, s = rnd() * TAU, 80 + rnd() * 160
							P({ k = "star", x = e.x, y = e.y, vx = cos(a) * s, vy = sin(a) * s, life = 0.6, size = 9, col = "255,215,104", drag = 0.1 })
						end
						G.stopT = max(G.stopT, 0.05)
					end
					if tr then
						shards(e.x, e.y, 2, 200, "255,240,180", 0.5, 4)
					end
				end
			elseif k == "pick" then
				if time - G.lastPick > 0.04 then
					G.lastPick = time
					P({ k = "star", x = p.x + (rnd() - 0.5) * 16, y = p.y - 16 - rnd() * 10, vy = -50, life = 0.3, size = if e.v >= 3 then 11 else 7, col = "255,215,104", drag = 0.2 })
				end
			elseif k == "heal" then
				G.healFlash = 0.5
				addNum(p.x, p.y - 34, "+" .. round(e.v), 2)
				ringFx(p.x, p.y, 46, "110,255,170", 0.45, 5)
				light(p.x, p.y - 10, 80, "90,255,150", 0.5)
				for j = 0, 11 do
					local a = j / 12 * TAU
					P({ k = "star", x = p.x + cos(a) * 20, y = p.y + sin(a) * 9, vx = cos(a) * 18, vy = -70 - rnd() * 50, life = 0.7, size = 8, col = "110,255,170", drag = 0.3 })
				end
			elseif k == "hurt" then
				G.hurtFlash = 0.55
				addNum(p.x, p.y - 34, "-" .. round(e.v), 3)
				flare(p.x, p.y - 12, 44, "255,90,96", 0.2)
				ringFx(p.x, p.y - 8, 40, "255,90,96", 0.26, 5)
				sparks(p.x, p.y - 12, 10, 260, "255,110,116", 0.34, 2.6)
				G.stopT = max(G.stopT, 0.035)
			elseif k == "stab" then
				pk.t = 0.14
				pk.x = cos(e.a) * (if e.n == 2 then 11 else 6)
				pk.y = sin(e.a) * (if e.n == 2 then 8 else 4)
				fxs[#fxs + 1] = { k = "stab", a = e.a, range = e.range, n = e.n, quad = e.quad, t = 0, dur = if e.n == 2 then 0.5 else 0.2 }
			elseif k == "swipe" then
				pk.t = 0.16
				pk.x = cos(e.a) * 7
				pk.y = sin(e.a) * 5
				fxs[#fxs + 1] = { k = "swipe", a = e.a, range = e.range, half = e.half, both = e.both, evo = e.evo, quad = e.quad, t = 0, dur = if e.evo then 0.62 else 0.46 }
				if e.evo then
					for _ = 1, 14 do
						local a = rnd() * TAU
						P({ k = "spark", x = p.x + cos(a) * e.range * 0.8, y = p.y + sin(a) * e.range * 0.8, vx = -sin(a) * 300 + cos(a) * 80, vy = cos(a) * 300 + sin(a) * 80, life = 0.35, size = 2.4, col = "200,225,255" })
					end
					G.zoomKick = max(G.zoomKick, 0.015)
				end
			elseif k == "lash" then
				pk.t = 0.18
				pk.x = cos(e.as[1]) * 8
				pk.y = sin(e.as[1]) * 6
				fxs[#fxs + 1] = { k = "lash", as = e.as, len = e.len, w = e.w, evo = e.evo, t = 0, dur = if e.evo then 0.42 else 0.36, cr = false }
			elseif k == "lashspin" then
				pk.t = 0.3
				pk.x = 0
				pk.y = -6
				fxs[#fxs + 1] = { k = "lashspin", r = e.r, w = e.w, gent = e.gent, t = 0, dur = 0.5, rot = atan2(p.fy, p.fx) - 0.6, cr = false }
			elseif k == "deflect" then
				sparks(e.x, e.y, 6, 260, "210,255,230", 0.25, 2.2)
				ringFx(e.x, e.y, 16, "255,255,255", 0.16, 3)
			elseif k == "transfer" then
				ringFx(e.x, e.y, 22, "255,205,70", 0.22, 4)
				flare(e.x, e.y, 24, "255,240,190", 0.12)
			elseif k == "laptop" then
				light(p.x, p.y - 20, 90, if e.evo then "180,130,255" else "110,180,255", 0.3)
				pk.t = 0.14
				pk.x = 0
				pk.y = 3
			elseif k == "nudge" then
				local c = if e.evo then "255,110,60" else "255,180,80"
				if e.bag then
					fxs[#fxs + 1] = { k = "bag", x = e.x + cos(e.a) * 14, y = e.y + sin(e.a) * 14, a = e.a, t = 0, dur = 0.22 }
				end
				pk.t = 0.12
				pk.x = cos(e.a) * 5
				pk.y = sin(e.a) * 4
				sparks(e.x, e.y - 8, 5, 240, c, 0.2, 2.2, e.a, 1.1)
				ringFx(e.x, e.y - 8, if e.evo then 24 else 17, c, 0.16, 3)
				flare(e.x, e.y - 8, if e.evo then 26 else 18, "255,240,210", 0.12)
			elseif k == "bump" then
				pk.t = 0.22
				pk.x = cos(e.a) * 11
				pk.y = sin(e.a) * 8
				local c = if e.evo then "255,110,60" else "255,180,80"
				local dir = if p.fx >= 0 then 1 else -1
				fxs[#fxs + 1] = { k = "bump", r = e.r, evo = e.evo, a = e.a, t = 0, dur = if e.evo then 0.46 else 0.38, rot = rnd() * TAU }
				for j = 1, 3 do
					ghosts[#ghosts + 1] = { x = p.x - cos(e.a) * 15 * j, y = p.y - sin(e.a) * 12 * j, t = 0.04 * j, f = 1, dir = dir }
				end
				sparks(p.x, p.y - 6, if e.evo then 22 else 14, e.r * 3.2, c, 0.32, 2.6)
				light(p.x, p.y - 6, e.r * 0.9, c, 0.28)
				puff(p.x, p.y + 8, 6, e.r * 1.2, "235,228,215", 0.5, 20)
			elseif k == "fcast" then
				if e.t ~= "freepass" then
					local dur = if e.t == "remote" then 0.7 elseif e.t == "routine" then 0.9 else 0.6
					fxs[#fxs + 1] = { k = "fcast", ty = e.t, r = e.r, as = e.as, len = e.len, w = e.w, x = e.x, y = e.y, t = 0, dur = dur, rot = rnd() * TAU }
					if e.x == nil then
						pk.t = 0.2
						pk.x = 0
						pk.y = -7
						G.zoomKick = max(G.zoomKick, 0.03)
					end
					if e.t == "bulldozer" then
						G.bagFling = 0.55
						puff(p.x, p.y + 6, 16, e.r * 1.9, "230,220,200", 0.8, 34)
						shards(p.x, p.y, 12, 300, "150,140,125", 0.8, 6)
						flare(p.x, p.y, e.r * 0.9, "255,190,90", 0.3)
					elseif e.t == "gentleman" then
						for _ = 1, 14 do
							local a = rnd() * TAU
							P({ k = "star", x = p.x + cos(a) * e.r * 0.6, y = p.y + sin(a) * e.r * 0.5, vx = cos(a) * 90, vy = sin(a) * 90 - 30, life = 0.7, size = 16, col = "255,215,110", vr = 4, drag = 0.5 })
						end
					elseif e.t == "routine" then
						local fx0, fy0 = e.x or p.x, e.y or p.y
						flare(fx0, fy0 - 10, 150, "255,220,120", 0.35)
						for _ = 1, 6 do
							P({ k = "smoke", x = fx0 + (rnd() - 0.5) * 40, y = fy0 - 10, vx = (rnd() - 0.5) * 50, vy = -70 - rnd() * 50, life = 0.9, size = 20, col = "250,240,225", drag = 0.5 })
						end
					elseif e.t == "remote" then
						light(p.x, p.y - 10, 110, "150,190,255", 0.3)
					end
				end
			elseif k == "beam" then
				pk.t = 0.2
				pk.x = -cos(e.as[1]) * 6
				pk.y = -sin(e.as[1]) * 4
				fxs[#fxs + 1] = { k = "beam", as = e.as, len = e.len, w = e.w, evo = e.evo, t = 0, dur = if e.evo then 0.36 else 0.28 }
				light(p.x, p.y, 120, if e.evo then "180,130,255" else "110,180,255", 0.3)
			elseif k == "bossin" then
				fxs[#fxs + 1] = { k = "bossin", x = e.x, y = e.y, t = 0, dur = 1.3 }
			elseif k == "bossland" then
				flare(e.x, e.y - 20, 220, "255,90,90", 0.5)
				for j = 0, 2 do
					ringFx(e.x, e.y, 120 + j * 80, if j % 2 == 1 then "255,255,255" else "255,80,90", 0.45 + j * 0.15, 10 - j * 2)
				end
				puff(e.x, e.y, 12, 150, "235,225,215", 0.9, 36)
				sparks(e.x, e.y, 26, 460, "255,200,150", 0.55, 3)
				G.zoomKick = max(G.zoomKick, 0.05)
			elseif k == "fuse" then
				fxs[#fxs + 1] = { k = "level", t = 0, dur = 0.9 }
				for j = 0, 3 do
					ringFx(p.x, p.y, 90 + j * 70, FUSE_COL[j + 1], 0.6 + j * 0.15, 9)
				end
				flare(p.x, p.y - 10, 260, "255,255,255", 0.5)
			elseif k == "say" then
				says[e.id] = { txt = e.txt, till = time + 2.8, at = time }
			elseif k == "ring" then
				pk.t = 0.18
				pk.x = 0
				pk.y = -6
				fxs[#fxs + 1] = { k = "ring", r = e.r, evo = e.evo, t = 0, dur = if e.evo then 0.55 else 0.45 }
				light(p.x, p.y, e.r * 0.8, if e.evo then "255,130,70" else "70,255,190", 0.25)
				if e.evo then
					G.zoomKick = max(G.zoomKick, 0.02)
				end
			elseif k == "shout" then
				fxs[#fxs + 1] = { k = "shout", r = e.r, evo = e.evo, t = 0, dur = 0.95 }
				G.flash = max(G.flash, if e.evo then 0.45 else 0.3)
				G.zoomKick = max(G.zoomKick, if e.evo then 0.06 else 0.04)
				G.stopT = max(G.stopT, if e.evo then 0.08 else 0.05)
				G.speedT = 1
				for _ = 1, if e.evo then 10 else 6 do
					local a, s = rnd() * TAU, 260 + rnd() * 200
					P({ k = "text", x = p.x, y = p.y - 30, vx = cos(a) * s, vy = sin(a) * s, life = 0.6, size = 20 + rnd() * 10, col = "255,214,90", txt = "!", drag = 0.03, vr = (rnd() - 0.5) * 8 })
				end
			elseif k == "zap" then
				local c = if e.evo then "255,224,130" else "120,220,255"
				local pts = e.pts
				fxs[#fxs + 1] = { k = "zap", pts = pts, evo = e.evo, t = 0, dur = if e.evo then 0.24 else 0.18, seed = floor(rnd() * 1e6) }
				if e.gold then
					for j = 1, #pts, 2 do
						ringFx(pts[j], pts[j + 1], 26, "255,214,90", 0.22, 4)
						flare(pts[j], pts[j + 1], 30, "255,245,190", 0.16)
						sparks(pts[j], pts[j + 1], 4, 260, "255,225,120", 0.25, 2.2)
					end
				end
				for j = 3, #pts, 2 do
					flare(pts[j], pts[j + 1], if e.evo then 34 else 24, c, 0.2)
					light(pts[j], pts[j + 1], if e.evo then 70 else 50, c, 0.22)
					sparks(pts[j], pts[j + 1], 3, 210, c, 0.24, 2)
				end
			elseif k == "splash" then
				local c = if e.evo then "70,40,90" else "150,96,54"
				ringFx(e.x, e.y, e.r * 1.15, if e.evo then "190,120,255" else "255,210,160", 0.34, 5)
				puff(e.x, e.y - 6, 5, 50, "255,255,255", 0.9, 22)
				for j = 0, 15 do
					local a, s = j / 16 * TAU + rnd() * 0.3, 70 + rnd() * 90
					P({ k = "drop", x = e.x + cos(a) * e.r * 0.35, y = e.y + sin(a) * e.r * 0.3, vx = cos(a) * s, vy = sin(a) * s * 0.6 - 150 - rnd() * 90, g = 620, life = 0.5 + rnd() * 0.15, size = 3 + rnd() * 2.4, col = c, drag = 0.6 })
				end
			elseif k == "dash" then
				puff(e.x, e.y + 8, 5, 70, "236,232,222", 0.4, 16)
				ringFx(e.x, e.y + 6, 34, "255,255,255", 0.22, 4)
				G.speedT = max(G.speedT, 0.7)
				fxs[#fxs + 1] = { k = "dash", x = e.x, y = e.y, t = 0, dur = 0.3 }
			elseif k == "level" then
				fxs[#fxs + 1] = { k = "level", t = 0, dur = 0.9 }
				light(p.x, p.y - 20, 170, "255,220,120", 0.6)
				for _ = 1, 26 do
					local a, d = rnd() * TAU, rnd() * 26
					P({ k = "star", x = p.x + cos(a) * d, y = p.y + sin(a) * d * 0.5, vx = cos(a) * 40, vy = -120 - rnd() * 200, life = 0.7 + rnd() * 0.4, size = 7 + rnd() * 7, col = "255,215,104", drag = 0.25 })
				end
				G.flash = max(G.flash, 0.2)
				G.zoomKick = max(G.zoomKick, 0.045)
			elseif k == "maceslam" then
				fxs[#fxs + 1] = { k = "crack", x = e.x, y = e.y, r = e.r, t = 0, dur = 1.3, rot = rnd() * TAU }
				ringFx(e.x, e.y, e.r * 1.05, "255,150,70", 0.38, 9)
				ringFx(e.x, e.y, e.r * 0.6, "255,240,210", 0.26, 5)
				puff(e.x, e.y + 6, 14, e.r * 1.7, "225,215,200", 0.8, 30)
				shards(e.x, e.y, 12, 300, "150,140,125", 0.8, 6)
				flare(e.x, e.y, e.r * 0.4, "255,190,110", 0.2)
				G.zoomKick = max(G.zoomKick, 0.035)
			elseif k == "macedash" then
				local bx, by = -cos(e.a), -sin(e.a)
				ringFx(p.x, p.y + 6, 58, "255,190,110", 0.26, 5)
				for _ = 1, 9 do
					local sp, v = (rnd() - 0.5) * 1.5, 120 + rnd() * 160
					P({ k = "smoke", x = p.x + bx * 8, y = p.y + 10, vx = (bx * cos(sp) - by * sin(sp)) * v, vy = (by * cos(sp) + bx * sin(sp)) * v * 0.7 - 20, life = 0.5 + rnd() * 0.3, size = 16 + rnd() * 12, col = "225,215,200", drag = 2.4 })
				end
				sparks(p.x, p.y + 8, 8, 260, "255,200,120", 0.3, 2.4)
				pk.t = 0.2
				pk.x = cos(e.a) * 9
				pk.y = sin(e.a) * 7
			elseif k == "macehit" then
				flare(e.x, e.y, 30, "255,200,130", 0.14)
				shards(e.x, e.y, 3, 200, "255,170,90", 0.4, 4)
			elseif k == "parry" then
				flare(e.x, e.y, 26, "255,236,170", 0.16)
				ringFx(e.x, e.y, 20, "255,220,140", 0.2, 3)
				sparks(e.x, e.y, 6, 220, "255,230,160", 0.3, 2.2)
			elseif k == "alarmboom" then
				flare(e.x, e.y, e.r * 1.3, "255,226,120", 0.28)
				light(e.x, e.y, e.r * 1.5, "255,210,90", 0.3)
				ringFx(e.x, e.y, e.r * 1.1, "255,214,90", 0.36, 7)
				ringFx(e.x, e.y, e.r * 0.6, "255,255,255", 0.24, 4)
				sparks(e.x, e.y, 14, 300, "255,226,120", 0.36, 2.6)
				for j = 0, 3 do
					local a = -PI / 2 + (j - 1.5) * 0.5
					P({ k = "text", x = e.x, y = e.y - 14, vx = cos(a) * 90, vy = sin(a) * 90, life = 0.5, size = 17, col = "255,214,90", txt = "♪", rot = (j - 1.5) * 0.3, vr = 0, drag = 0.1 })
				end
				P({ k = "text", x = e.x, y = e.y - e.r * 0.5, vy = -26, life = 0.55, size = if e.evo then 22 else 18, col = "229,72,77", txt = "따르릉!", rot = -0.12, vr = 0, drag = 0.3, pop = 1 })
			elseif k == "zone" then
				G.wipeT = 0.6
				table.clear(parts)
				table.clear(fxs)
				table.clear(corpses)
				table.clear(ghosts)
				table.clear(nums)
				G.cam.init = false
			elseif k == "trainhit" then
				flare(e.x, e.y, 130, "255,236,170", 0.4)
				ringFx(e.x, e.y, 120, "255,226,120", 0.4, 9)
				sparks(e.x, e.y, 34, 520, "255,226,120", 0.55, 3)
				shards(e.x, e.y, 10, 240, "255,255,255", 0.7, 5)
				G.flash = max(G.flash, 0.5)
				G.stopT = max(G.stopT, 0.1)
				G.zoomKick = max(G.zoomKick, 0.05)
			elseif k == "crash" then
				ringFx(e.x, e.y, 90, "255,200,120", 0.4, 7)
				puff(e.x, e.y, 8, 90, "230,220,205", 0.8, 30)
				shards(e.x, e.y, 10, 240, "224,80,140", 0.8, 6)
			elseif k == "boom" then
				local K = e.kind
				if K == "stamp" then
					decals[#decals + 1] = { x = e.x, y = e.y, r = e.r, kind = "stamp", t = 0, life = 2.2, rot = (rnd() - 0.5) * 0.5 }
					for _ = 1, 5 do
						P({ k = "paper", x = e.x + (rnd() - 0.5) * e.r, y = e.y - 10, vx = (rnd() - 0.5) * 300, vy = -140 - rnd() * 140, g = 420, life = 1, size = 16, col = "251,250,245", drag = 0.5 })
					end
					ringFx(e.x, e.y, e.r * 1.2, "230,60,66", 0.35, 8)
					puff(e.x, e.y, 5, 70, "235,225,215", 0.6, 24)
				elseif K == "door" then
					decals[#decals + 1] = { x = e.x, y = e.y, r = e.r, kind = "crack", t = 0, life = 1.6, rot = rnd() * TAU }
					sparks(e.x, e.y, 22, 420, "255,230,150", 0.4, 3)
					ringFx(e.x, e.y, e.r * 1.25, "255,120,110", 0.35, 9)
					puff(e.x, e.y, 6, 80, "225,230,232", 0.7, 28)
					flare(e.x, e.y, e.r * 1.3, "255,150,130", 0.22)
				elseif K == "bass" then
					for j = 0, 2 do
						ringFx(e.x, e.y, e.r * (1 + j * 0.45), if j % 2 == 1 then "225,50,200" else "255,120,215", 0.35 + j * 0.12, 8 - j * 2)
					end
					flare(e.x, e.y, e.r * 1.4, "255,90,190", 0.25)
					sparks(e.x, e.y, 14, 300, "255,180,230", 0.4, 2.6)
				elseif K == "nag" then
					for j = 0, 6 do
						local a = rnd() * TAU
						P({ k = "text", x = e.x + cos(a) * e.r * 0.4, y = e.y + sin(a) * e.r * 0.3, vx = cos(a) * 120, vy = -90 - rnd() * 90, life = 0.9, size = 18, col = "255,170,60", txt = NAG_TXT[j % 4 + 1], drag = 0.4 })
					end
					ringFx(e.x, e.y, e.r * 1.2, "255,160,60", 0.35, 8)
					flare(e.x, e.y, e.r * 1.2, "255,170,80", 0.22)
				elseif K == "meet" then
					for _ = 1, 6 do
						P({ k = "paper", x = e.x + (rnd() - 0.5) * e.r, y = e.y - 10, vx = (rnd() - 0.5) * 340, vy = -160 - rnd() * 150, g = 420, life = 1.1, size = 18, col = "251,250,245", drag = 0.5 })
					end
					shards(e.x, e.y, 8, 220, "185,134,84", 0.8, 6)
					ringFx(e.x, e.y, e.r * 1.2, "255,110,100", 0.35, 8)
				else
					flare(e.x, e.y, e.r * 1.5, "255,120,120", 0.3)
					light(e.x, e.y, e.r * 1.6, "255,80,80", 0.35)
					ringFx(e.x, e.y, e.r * 1.3, "255,110,116", 0.4, 8)
					sparks(e.x, e.y, 16, 330, "255,130,130", 0.4, 2.8)
					shards(e.x, e.y, 8, 190, "255,230,230", 0.7, 5)
					puff(e.x, e.y, 5, 60, "240,220,220", 0.7, 26)
					for _ = 1, 5 do
						P({ k = "paper", x = e.x + (rnd() - 0.5) * e.r, y = e.y + (rnd() - 0.5) * e.r, vx = (rnd() - 0.5) * 140, vy = -90 - rnd() * 90, g = 170, life = 0.9, size = 7, col = "255,255,255", drag = 0.4 })
					end
					P({ k = "text", x = e.x, y = e.y, vy = -20, life = 0.75, size = 30, col = "229,72,77", txt = if e.txt and e.txt ~= "" then e.txt else "쿵", rot = -0.2, vr = 0, drag = 0.3, pop = 1 })
				end
			elseif k == "page" then
				for _ = 1, 3 do
					P({ k = "paper", x = e.x + (rnd() - 0.5) * 40, y = e.y - 20, vx = (rnd() - 0.5) * 380, vy = -160 - rnd() * 160, g = 420, life = 1.3, size = 24, col = "251,250,245", drag = 0.5 })
				end
				sparks(e.x, e.y, 28, 380, "255,255,255", 0.6, 3)
				ringFx(e.x, e.y, 170, "255,255,255", 0.5, 8)
				flare(e.x, e.y, 120, "255,255,255", 0.35)
				G.flash = max(G.flash, 0.4)
				G.stopT = max(G.stopT, 0.06)
			end
		end
		table.clear(E)
	end

	-- 목록에서 keep(o)가 거짓인 것을 뺀다 (차례는 그대로)
	local function compact(list, keep)
		local n, j = #list, 1
		for i = 1, n do
			local o = list[i]
			if keep(o) then
				if i ~= j then
					list[j] = o
				end
				j += 1
			end
		end
		for i = j, n do
			list[i] = nil
		end
	end

	-- ---------- 시간 흐름 (원본 stepFx) ----------
	function Pm.step(dt: number, S)
		if G.bagFling > 0 then
			G.bagFling = max(0, G.bagFling - dt)
		end
		compact(decals, function(d)
			d.t += dt
			return d.t < d.life
		end)
		if pk.t > 0 then
			pk.t -= dt
		end
		compact(parts, function(q)
			q.t += dt
			if q.t >= q.life then
				return false
			end
			q.x += q.vx * dt
			q.y += q.vy * dt
			q.vy += q.g * dt
			if q.drag < 1 then
				local dr = pow(q.drag, dt)
				q.vx *= dr
				if q.g == 0 then
					q.vy *= dr
				end
			end
			q.rot += q.vr * dt
			return true
		end)
		compact(nums, function(n)
			n.t += dt
			n.x += n.vx * dt
			n.y += n.vy * dt
			n.vy += 190 * dt
			n.vx *= pow(0.1, dt)
			return n.t <= 0.8
		end)
		compact(fxs, function(f)
			f.t += dt
			return f.t < f.dur
		end)
		local ended = nil
		compact(corpses, function(c)
			c.t += dt
			if c.t >= c.life then
				ended = ended or {}
				table.insert(ended, c)
				return false
			end
			c.x += c.vx * dt
			c.y += c.vy * dt
			c.vx *= pow(0.05, dt)
			c.vy *= pow(0.05, dt)
			return true
		end)
		if ended then
			for _, c in ended do
				puff(c.x, c.y, 1, 20, "236,232,222", 0.3, 12)
			end
		end
		compact(ghosts, function(g)
			g.t += dt
			return g.t <= 0.3
		end)
		if dt > 0 then
			local p, M = S.p, S.M
			if p.dashT > 0 and #ghosts < 12 then
				ghosts[#ghosts + 1] = { x = p.x, y = p.y, f = floor(p.anim * 12) % 4, dir = if p.fx >= 0 then 1 else -1, t = 0 }
			end
			for _, s in S.shots do
				local tr = trails[s]
				if not tr then
					tr = {}
					trails[s] = tr
				end
				tr[#tr + 1] = s.x
				tr[#tr + 1] = s.y
				if #tr > 16 then
					table.remove(tr, 1)
					table.remove(tr, 1)
				end
			end
			for _, s in S.rangs do
				local tr = trails[s]
				if not tr then
					tr = {}
					trails[s] = tr
				end
				tr[#tr + 1] = s.x
				tr[#tr + 1] = s.y
				if #tr > 20 then
					table.remove(tr, 1)
					table.remove(tr, 1)
				end
			end
			for _, r in S.riders do
				if rnd() < dt * 50 then
					P({ k = "smoke", x = r.x - r.dx * 20 + (rnd() - 0.5) * r.w, y = r.y - r.dy * 20 + (rnd() - 0.5) * r.w, vx = -r.dx * 60, vy = -r.dy * 60, life = 0.4, size = 11, col = "236,232,222", drag = 0.2 })
				end
			end
			for _, b in S.lobs do
				if b.kind ~= "alarm" and rnd() < dt * 40 then
					local q = b.t / b.dur
					P({ k = "drop", x = b.x0 + (b.x1 - b.x0) * q, y = b.y0 + (b.y1 - b.y0) * q - sin(q * PI) * 60, vx = (rnd() - 0.5) * 30, vy = 20, g = 300, life = 0.3, size = 2.2, col = if b.evo then "70,40,90" else "150,96,54", drag = 0.6 })
				end
			end
			for _, u in S.puddles do
				if not u.gum and rnd() < dt * 6 then
					local a, d = rnd() * TAU, rnd() * u.r * 0.75
					P({ k = "smoke", x = u.x + cos(a) * d, y = u.y + sin(a) * d * 0.8, vx = (rnd() - 0.5) * 14, vy = -30 - rnd() * 22, life = 1 + rnd() * 0.6, size = 13 + rnd() * 9, col = if u.evo then "200,170,255" else "255,255,255", drag = 0.5, soft = 1 })
				end
			end
			local l = wl(S, "hotpack")
			if l > 0 then
				local r = WEAPONS.hotpack.stat(l).r * M.area
				if rnd() < dt * (if l >= EVO then 34 else 18) then
					local a, d = rnd() * TAU, sqrt(rnd()) * r
					P({ k = "spark", x = p.x + cos(a) * d, y = p.y + sin(a) * d, vx = (rnd() - 0.5) * 20, vy = -60 - rnd() * 70, life = 0.55, size = 2, col = if l >= EVO then "255,120,70" else "255,180,90", drag = 0.4 })
				end
			end
			l = wl(S, "backpack")
			if l >= EVO and rnd() < dt * 30 then
				local s = WEAPONS.backpack.stat(l)
				local a, rad = S.orbA + floor(rnd() * s.n) * TAU / s.n, s.radius * M.area
				P({ k = "spark", x = p.x + cos(a) * rad, y = p.y + sin(a) * rad, vx = (rnd() - 0.5) * 60, vy = -40 - rnd() * 50, life = 0.4, size = 2.2, col = "255,150,70", drag = 0.3 })
			end
			local T = S.train
			if T and T.on and T.kind ~= "bus" then
				for _ = 1, 4 do
					P({ k = "spark", x = T.x - T.dir * rnd() * TRAIN_LEN, y = T.y + (if rnd() < 0.5 then -44 else 44), vx = -T.dir * (200 + rnd() * 300), vy = (rnd() - 0.5) * 140, life = 0.3, size = 2.6, col = "255,226,120" })
				end
				if rnd() < dt * 30 then
					puff(T.x - T.dir * rnd() * TRAIN_LEN, T.y + (if rnd() < 0.5 then -58 else 58), 1, 30, "236,232,222", 0.5, 20)
				end
			end
			for _, e in S.enemies do
				if e.elite and not e.dead and rnd() < dt * 9 then
					P({ k = "flame", x = e.x + (rnd() - 0.5) * e.r * 1.6, y = e.y + e.r * 0.7, vy = -46 - rnd() * 30, life = 0.5, size = 15 + rnd() * 8, col = "255,90,110", drag = 0.6, vr = 0, rot = 0 })
				end
			end
		end
		local rdt = if dt > 0 then dt else 0.016
		G.shakeAmt *= pow(0.015, rdt)
		G.flash = max(0, G.flash - rdt * 2.2)
		G.hurtFlash = max(0, G.hurtFlash - rdt * 1.6)
		G.healFlash = max(0, G.healFlash - rdt * 1.6)
	end

	-- ---------- 입자 그리기 (원본 drawParts) ----------
	-- pass 0 = 무기보다 위 · 광선보다 아래(연기 · 방울 · 종이 · 파편 · 글자), pass 1 = 맨 위(불똥 · 빛 · 고리 · 별 · 불꽃 · 꼬리표)
	local C_PAPEREDGE = D.BLACK
	function Pm.draw(pass: number)
		local F = L.fx
		local gl = G.gl
		-- 불똥 · 방울의 작은 흰 점은 입자가 많을 때는 뺀다(그리는 물건 수를 줄인다)
		local dot = G.fxLv == 2 and #parts < 200
		local vx0, vy0, vx1, vy1 = D.vx0, D.vy0, D.vx1, D.vy1
		for i = 1, #parts do
			local q = parts[i]
			local k = q.k
			local x, y, size = q.x, q.y, q.size
			local m = size * 2 + 30
			if x > vx0 - m and x < vx1 + m and y > vy0 - m and y < vy1 + m then
				local a = 1 - q.t / q.life
				if pass == 0 then
					if k == "smoke" then
						local s = size * (1.9 - a)
						if q.soft and not q.white then
							D.img(F, 61, "fx/glow", x, y, s * 2, s * 2, min(1, 0.2 * a * gl), nil, nil, q.lcol)
						else
							D.img(F, 60, "fx/puff", x, y, s * 2, s * 2, (if q.soft then 0.2 else 0.42) * a)
						end
					elseif k == "dot" then
						local r = size * (0.5 + a * 0.5) * 1.03
						D.img(F, 62, "prim/disc", x, y, r * 2, r * 2, a, nil, nil, q.col)
					elseif k == "drop" then
						local al = min(1, a * 3)
						D.img(F, 63, "prim/disc", x, y, size * 2.06, size * 2.06, al, nil, nil, q.col)
						if dot then
							D.img(F, 64, "prim/disc", x - size * 0.3, y - size * 0.3, size * 0.72, size * 0.72, al * 0.55)
						end
					elseif k == "paper" then
						local al = min(1, a * 2)
						local hh = size * 1.6 * abs(cos(q.rot * 1.7) * 0.6 + 0.4)
						D.shape(F, 65, x, y, size * 1.2, max(0.5, hh), q.col, al, C_PAPEREDGE, al * 0.4, 0.75, 0, q.rot)
					elseif k == "shard" then
						D.spr(F, 66, "fx/shard", x, y, size / 8, min(1, a * 2.5), q.rot, false, q.col)
					elseif k == "text" then
						local s = if q.pop then 1 + (1 - a) * 0.35 else 1
						D.text(F, 67, q.txt, x, y - size * 0.06 * s, size * s * G.TS, q.col, min(1, a * 2.2), if q.pop then WHITE else C_INK, 2.5 * s, q.rot)
					end
				else
					if k == "spark" then
						local vx, vy = q.vx, q.vy
						local sp = sqrt(vx * vx + vy * vy)
						local len = max(3, sp * 0.045)
						local ux, uy = 1, 0
						if sp > 0 then
							ux, uy = vx / sp, vy / sp
						end
						local w = size * (0.5 + a * 0.7)
						local kx = (len * 1.5 + w * 1.4) / 31.03
						D.img(F, 140, "fx/spark", x - ux * 11.5 * kx, y - uy * 11.5 * kx, 34 * kx, 8 * w / 2.88, a, atan2(uy, ux), false, q.col)
						if dot then
							D.img(F, 141, "prim/disc", x, y, w * 1.14, w * 1.14, a * 0.9)
						end
					elseif k == "glow" then
						local s = size * (1.15 - a * 0.15)
						-- 원본: 제 색의 둥근 빛을 a²·0.8로(보통 섞기) — 비쳐 보인다. 번짐 층 때문에 한가운데만 하얗게 탄다
						D.img(F, 139, "fx/glow", x, y, s * 2, s * 2, min(1, a * a * 0.9), nil, nil, q.hcol)
						if size >= 40 then
							D.img(F, 142, "fx/glow", x, y, s * 0.55, s * 0.55, min(1, a * a * 0.8 * gl), nil, nil, q.lcol)
						end
					elseif k == "ring" then
						local r = size * (1 - a * a * a)
						if r > 0.5 then
							-- 넓고 옅은 테 + 또렷한 밝은 테(원본은 번짐이 더해져 밝게 뜬다 → 밝은 색 · 조금 굵게)
							D.ring(F, 143, x, y, r, q.w * 2.6, q.col, a * 0.45)
							D.ring(F, 144, x, y, r, (q.w * a + 1) * 1.3, q.rcol, a)
						end
					elseif k == "star" then
						local s = size * (0.35 + a * 0.65)
						local al = min(1, a * 1.6)
						D.img(F, 139, "fx/glow", x, y, s * 1.6, s * 1.6, al, nil, nil, q.hcol)
						if size >= 40 then
							D.img(F, 145, "fx/glow", x, y, s * 0.5, s * 0.5, min(1, al * 0.9), nil, nil, q.lcol)
						end
						D.img(F, 146, "fx/flare", x, y, s * 2, s * 2, al, q.rot)
					elseif k == "flame" then
						local s = size * (0.4 + a * 0.6)
						D.img(F, 147, "fx/flame", x, y - s * 0.65, s, s * 1.5, a * 0.85)
					elseif k == "tag" then
						local s = size * (1 - a * a)
						local lw = 3 * a + 1
						if s * 2 > lw then
							D.shape(F, 148, x, y, s * 2 - lw, s * 2 - lw, nil, nil, q.col, a, lw, s * 0.3, q.rot)
						end
					end
				end
			end
		end
	end

	-- ---------- 숫자 ----------
	local C_NUMEDGE = rgb("16,20,24")
	local NUMCOL = { [0] = WHITE, rgb("#ffd23f"), rgb("#6dffa5"), rgb("#ff6b6f") }
	function Pm.drawNums()
		local N = L.num
		for i = 1, #nums do
			local n = nums[i]
			if D.inView(n.x, n.y, 30) then
				local pop = 1 + 0.8 * max(0, 1 - n.t / 0.1)
				local c = n.c
				local sz = (if c == 1 then 21 elseif c >= 2 then 18 else 13.5) * pop
				local al = 1 - max(0, n.t - 0.55) / 0.25
				D.text(N, 1, n.v, n.x, n.y - sz * 0.36, sz * G.TS, NUMCOL[c], al, C_NUMEDGE, if c ~= 0 then 2.25 else 1.5, nil, if c ~= 0 then D.FD else D.FB)
			end
		end
	end

	return Pm
end
