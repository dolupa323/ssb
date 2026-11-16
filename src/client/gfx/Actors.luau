-- 캐릭터: 적 · 보스 · 플레이어 · 쓰러지는 모습 · 보스 말풍선 · 버스/열차 · 화면 밖 표시
-- (원본 gfx.js의 drawEnemy · drawCrowd · drawPlayer · corpses · says · drawBus · drawTrain · edgeArrow)
--  적은 「발밑 그림자(부모) + 몸(아이)」 한 벌을 적마다 붙들어 두고, 움직일 때 그림자의 자리만 쓴다.
--  겹치는 순서(ZIndex)는 y를 8단위로 끊은 칸이 바뀔 때만 쓴다.
local TextService = game:GetService("TextService")

return function(G)
	local D, Sim, Art = G.D, G.Sim, G.Art
	local L = G.L
	local rgb = D.rgb
	local lite = D.lite
	local rnd = math.random
	local cos, sin, atan2, floor, min, max, abs = math.cos, math.sin, math.atan2, math.floor, math.min, math.max, math.abs
	local TAU, PI = math.pi * 2, math.pi
	local INV = 1 / D.U
	local fromScale = UDim2.fromScale
	local SPIN_R = Sim.SPIN_R
	local chars = G.chars
	local says, ghosts, corpses, pk = G.says, G.ghosts, G.corpses, G.pk
	local WHITE = D.WHITE

	local A = {}
	local C_INK = rgb("#1f262b")
	local ZBASE = 1000000
	local function zOf(y: number): number
		return ZBASE + 8 * floor(y / 8)
	end
	local function setZ(o, z: number)
		if o.z ~= z then
			o.z = z
			o.g.ZIndex = z
			D.writes += 1
		end
	end

	-- 그림 이름 표: names[가면인가][종류][변형*4+걸음] (매 장면 글을 잇지 않게)
	local names = { [false] = {}, [true] = {} }
	local function charName(fl: boolean, type: string, v: number, frame: number): string
		local t = names[fl][type]
		if not t then
			t = {}
			names[fl][type] = t
		end
		local key = v * 4 + frame
		local n = t[key]
		if not n then
			n = (if fl then "mask/" else "char/") .. type .. "/" .. v .. "/" .. chars[type].frames[frame + 1]
			t[key] = n
		end
		return n
	end
	-- 원본 drawChar: 발이 (x, feetY)에 오게 그린다
	function G.char(Ly, z: number, type: string, v: number, frame: number, dir: number, fl: boolean, x: number, feetY: number, sc: number, alpha: number?)
		return D.spr(Ly, z, charName(fl, type, v, frame), x, feetY, sc, alpha, nil, dir < 0)
	end

	-- ---------- 적 한 벌(그림자 + 몸) ----------
	local map = {} :: { [any]: any }
	local free = {} :: { any }
	local stamp = 0
	A.active = 0
	A.shadows = true
	local shadowInfo
	local function newRec()
		local sh = Instance.new("ImageLabel")
		sh.Name = "E"
		sh.BackgroundTransparency = 1
		sh.BorderSizePixel = 0
		sh.AnchorPoint = Vector2.new(0.5, 0.5)
		shadowInfo = shadowInfo or Art.info("st/shadow")
		Art.setPage(sh, shadowInfo.page)
		Art.setRect(sh, shadowInfo, false)
		local sp = Instance.new("ImageLabel")
		sp.Name = "Body"
		sp.BackgroundTransparency = 1
		sp.BorderSizePixel = 0
		sp.Parent = sh
		sh.Parent = L.ent.frame
		D.created += 2
		return { sh = sh, sp = sp, a = 1, flip = false, shadow = true }
	end
	local function getRec(e)
		local rec = map[e]
		if not rec then
			rec = table.remove(free)
			if rec then
				rec.sh.Visible = true
				D.writes += 1
			else
				rec = newRec()
			end
			map[e] = rec
			A.active += 1
		end
		rec.stamp = stamp
		return rec
	end
	local function release(e, rec)
		map[e] = nil
		rec.sh.Visible = false
		D.writes += 1
		free[#free + 1] = rec
		A.active -= 1
	end
	function A.reset()
		for e, rec in map do
			release(e, rec)
		end
	end

	-- 한 벌을 놓는다: 그림자 가운데 (x, sy) · 반폭 sw, 몸은 발이 (bx, feet)에 오게 bsc배
	local function place(rec, name: string, flip: boolean, x: number, sy: number, sw: number, bx: number, feet: number, bsc: number, alpha: number, z: number, shadow: boolean)
		local sh, sp = rec.sh, rec.sp
		if rec.shadow ~= shadow then
			rec.shadow = shadow
			sh.ImageTransparency = if shadow then 0 else 1
			D.writes += 1
		end
		if rec.x ~= x or rec.y ~= sy then
			rec.x, rec.y = x, sy
			sh.Position = fromScale(x * INV, sy * INV)
			D.writes += 1
		end
		if rec.sw ~= sw then
			rec.sw = sw
			rec.gsc = nil
			sh.Size = fromScale(sw * 2 * INV, sw * INV)
			D.writes += 1
		end
		if rec.z ~= z then
			rec.z = z
			sh.ZIndex = z
			D.writes += 1
		end
		if rec.name ~= name or rec.flip ~= flip then
			local e = Art.info(name)
			if rec.page ~= e.page then
				rec.page = e.page
				Art.setPage(sp, e.page)
				D.writes += 1
			end
			Art.setRect(sp, e, flip)
			D.writes += 2
			if rec.info ~= e or rec.flip ~= flip then
				-- 같은 종류의 그림은 자른 네모가 같다(굽는 도구가 맞춰 두었다) → 종류나 방향이 바뀔 때만 자리를 다시 잡는다
				if not rec.info or rec.info.w ~= e.w or rec.info.h ~= e.h or rec.info.ox ~= e.ox or rec.info.oy ~= e.oy or rec.flip ~= flip then
					rec.gsc = nil
				end
				rec.info = e
			end
			rec.name = name
			rec.flip = flip
		end
		local dx, dy = bx - x, feet - sy
		if rec.gsc ~= bsc or rec.gdx ~= dx or rec.gdy ~= dy then
			rec.gsc, rec.gdx, rec.gdy = bsc, dx, dy
			local e = rec.info
			local w0, h0 = e.w / e.s, e.h / e.s
			local left = dx + sw - (if flip then w0 - e.ox else e.ox) * bsc
			local top = dy + sw / 2 - e.oy * bsc
			sp.Position = fromScale(left / (sw * 2), top / sw)
			sp.Size = fromScale(w0 * bsc / (sw * 2), h0 * bsc / sw)
			D.writes += 2
		end
		if rec.a ~= alpha then
			rec.a = alpha
			sp.ImageTransparency = 1 - alpha
			D.writes += 1
		end
	end

	-- 스마트폰 좀비의 화면 빛: 몸 그림의 아이로 붙인다(따로 옮길 일이 없다)
	local C_PHONE = lite("150,230,255")
	local function phoneGlow(rec, on: boolean, flip: boolean, sc: number)
		local g = rec.glow
		if not on then
			if g and rec.glowOn then
				rec.glowOn = false
				g.Visible = false
				D.writes += 1
			end
			return
		end
		if not g then
			g = Instance.new("ImageLabel")
			g.Name = "Phone"
			g.BackgroundTransparency = 1
			g.BorderSizePixel = 0
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			Art.set(g, "fx/glow")
			g.ImageColor3 = D.lit(C_PHONE)
			g.ImageTransparency = 1 - min(1, 0.55 * G.gl)
			g.Parent = rec.sp
			D.created += 1
			rec.glow = g
			rec.glowOn = true
			rec.glowKey = nil
		elseif not rec.glowOn then
			rec.glowOn = true
			g.Visible = true
			D.writes += 1
		end
		local key = (if flip then -1 else 1) * sc
		if rec.glowKey ~= key then
			rec.glowKey = key
			local e = rec.info
			local w0, h0 = e.w / e.s, e.h / e.s
			local dir = if flip then -1 else 1
			-- 몸 그림 안에서의 자리: 발에서 (dir·10, −22)·sc
			local gx = ((if flip then w0 - e.ox else e.ox) + dir * 10) / w0
			local gy = (e.oy - 22) / h0
			g.Position = fromScale(gx, gy)
			g.Size = fromScale(26 / (w0 * sc), 26 / (h0 * sc))
			D.writes += 2
		end
	end

	-- ---------- 하차 인파 (보스) ----------
	local CROWD = { { -24, -16, 0 }, { 0, -22, 1 }, { 24, -16, 2 }, { -34, 0, 3 }, { -12, -4, 1 }, { 12, -4, 0 }, { 34, 0, 2 }, { -22, 14, 2 }, { 0, 12, 3 }, { 22, 14, 1 }, { -8, 26, 0 }, { 10, 27, 3 } }
	local C_CROWDSH = rgb("15,20,24")
	local function drawCrowd(e, px: number)
		local E = L.ent
		local fl = e.flash > 0
		local dir = if px >= e.x then 1 else -1
		local zb = zOf(e.y)
		setZ(D.oval(E, 10, e.x, e.y + 22, e.r * 1.25, e.r * 0.62, C_CROWDSH, 0.4), zb - 24)
		for i, m in CROWD do
			local fr = floor(e.anim * 7 + (i - 1) * 1.7) % 4
			local o = G.char(E, 11, "pass", m[3], fr, dir, fl, e.x + m[1], e.y + m[2] + 22, 1.12)
			setZ(o, zOf(e.y + m[2] + 22) + 4)
		end
		local sy = e.y - 58 + sin(e.anim * 5) * 2
		setZ(D.spr(E, 12, "fx/exitsign/blank", e.x, sy, 1), zb + 30)
		setZ(D.text(E, 13, "출구", e.x - 9, sy + 11 - 6.1, 17 * G.TS, WHITE, 1), zb + 31)
	end

	-- ---------- 적 ----------
	local C_ELITE, C_RAGE, C_STUN, C_HPBG, C_HP = lite("255,70,90"), lite("255,60,70"), rgb("#ffd768"), rgb("20,24,28"), rgb("#ff4d6a")
	local C_ALERT, C_LEADG, C_LEADG2, C_LABEL = rgb("#e5484d"), lite("255,120,120"), lite("255,70,70"), rgb("#d23338")
	local C_SPK, C_SPKG, C_SPIN = rgb("53,224,194"), lite("160,80,255"), rgb("255,120,100")
	local DASHERS = { lead = true, bagman = true, carrierboss = true }

	local function drawEnemy(S, e, p)
		local E = L.ent
		local time = G.time
		local x, y = e.x, e.y
		local fl = e.flash > 0
		local def = e.def
		local sc = def.sc or e.sc or 1
		local etype = e.type
		if etype == "crowd" then
			drawCrowd(e, p.x)
			return
		end
		local stype = def.spr or etype
		local d = chars[stype]
		local feet0 = y + e.r * 0.85
		local feet = feet0
		local st = e.st
		local dir
		if etype == "zomb" then
			dir = if e.vx >= 0 then 1 else -1
		else
			dir = if p.x >= x then 1 else -1
		end
		if etype == "runner" and st == 2 then
			dir = if e.dx >= 0 then 1 else -1
		end
		if etype == "bagman" and st == 4 then
			dir = if floor(e.anim * 12) % 2 ~= 0 then 1 else -1
		end
		local fr = if e.mv then floor(e.anim * (if etype == "runner" and st == 2 then 16 else 8)) % 4 else 0
		local zb = zOf(y)
		local special = e.elite or e.boss
		if e.elite then
			setZ(D.img(E, 1, "fx/glow", x, y, (e.r * 2.6 + sin(time * 6) * 3) * 2, (e.r * 2.6 + sin(time * 6) * 3) * 2, min(1, 0.5 * G.gl), nil, nil, C_ELITE), zb)
		end
		local sw = e.r * (if e.boss then 1.6 else 1.25)
		if etype == "runner" and st == 2 then
			for k = -1, 1 do
				local o = D.line(E, 2, x - e.dx * 14 - e.dy * k * 7, y - 10 - e.dy * 14 + e.dx * k * 7, x - e.dx * 40 - e.dy * k * 7, y - 10 - e.dy * 40 + e.dx * k * 7, 2.5, WHITE, 0.7, true)
				setZ(o, zb + 3)
			end
		end
		if e.boss and G.S_rage > 0 then
			local r = e.r * 3.2 + sin(time * 9) * 5
			setZ(D.img(E, 1, "fx/glow", x, y - 10, r * 2, r * 2, min(1, (0.3 + 0.1 * min(3, G.S_rage)) * G.gl), nil, nil, C_RAGE), zb)
		end
		local bsc, bx, alpha = sc, x, 1
		local intro = e.intro > 0
		if intro then
			local u = e.intro / 1.3
			feet -= u * u * 520
			alpha = min(1, (1 - u) * 3)
		end
		local v = e.seed % d.nv
		if e.boss then
			local sy = says[e.id]
			local ct = if sy then time - sy.at else 9
			if ct < 0.35 then
				bsc = sc * (1 + 0.13 * sin(ct / 0.35 * PI))
			end
			if st == 1 and DASHERS[etype] then
				bx = x + (rnd() - 0.5) * 5
				bsc = sc * (0.94 + 0.04 * sin(time * 40))
			end
			if st == 2 and DASHERS[etype] then
				-- 돌진 잔상
				for k = 3, 1, -1 do
					local o = G.char(E, 3, stype, v, (fr + k) % 4, dir, true, x - e.dx * k * 26, feet - e.dy * k * 26, sc, 0.16 * (4 - k) / 1.6)
					setZ(o, zb + 2)
				end
				if rnd() < 0.6 then
					G.P({ k = "smoke", x = x - e.dx * 20 + (rnd() - 0.5) * 14, y = feet - 4, vx = -e.dx * 60, vy = -20, life = 0.5, size = 16, col = "230,225,215", drag = 0.4 })
				end
			end
		end
		local rec = getRec(e)
		local flip = dir < 0
		place(rec, charName(fl, stype, v, fr), flip, x, feet0, sw, bx, feet, bsc, alpha, zb + 4, special or A.shadows)
		phoneGlow(rec, etype == "zomb" and not intro, flip, sc)
		if intro then
			return
		end
		if not special and etype ~= "runner" and e.stun <= 0 then
			return
		end
		local top = feet - (d.oy - 4) * sc
		if etype == "runner" and st == 1 then
			setZ(D.text(E, 4, "!", x, top - 2 - 8, 22 * G.TS, C_ALERT, 1, WHITE, 1.5), zb + 6)
		end
		if e.stun > 0 and not e.boss then
			for k = 0, 2 do
				local a = time * 7 + k * TAU / 3
				setZ(D.img(E, 5, "prim/disc", x + cos(a) * 9, top + 2 + sin(a) * 3.5, 4.5, 4.5, 1, nil, nil, C_STUN), zb + 6)
			end
		end
		if e.elite then
			local bw = 34
			setZ(D.shape(E, 6, x, top - 6, bw + 2, 6, C_HPBG, 0.8, nil, nil, nil, 3), zb + 5)
			local w = max(2, bw * e.hp / e.maxhp)
			setZ(D.shape(E, 7, x - bw / 2 + w / 2, top - 6, w, 4, C_HP, 1, nil, nil, nil, 2), zb + 6)
			setZ(D.spr(E, 8, "fx/anger/0", x + dir * -12 * sc, top + 4, 1), zb + 6)
		end
		if etype == "lead" then
			local day = e.day
			if day ~= day or day == nil then
				day = 0
			end
			local mid = top + (feet - top) * 0.56
			if st == 1 or st == 2 then
				local a = atan2(e.dy, e.dx)
				setZ(D.img(E, 9, "fx/glow", x + cos(a) * 150, y - 20 + sin(a) * 150, 300, 160, min(1, (if st == 2 then 0.5 else 0.25) * G.gl), a, nil, C_LEADG), zb + 5)
			end
			if day >= 4 then
				local r = 86 + sin(time * 8) * 6
				setZ(D.img(E, 9, "fx/glow", x, y - 30, r * 2, r * 2, min(1, 0.3 * G.gl), nil, nil, C_LEADG2), zb + 5)
			end
			setZ(D.spr(E, 14, "fx/leadtie", x, mid, 1), zb + 6)
			setZ(D.spr(E, 15, "fx/leadclip", x + dir * 30, mid + 6 + sin(e.anim * 6) * 2, 1, 1, dir * 0.18, dir < 0), zb + 6)
			local ga = 0.35 + 0.25 * sin(time * 3)
			setZ(D.img(E, 5, "prim/disc", x + dir * 5 - 7, top + 25, 13.4, 13.4, ga), zb + 6)
			setZ(D.img(E, 5, "prim/disc", x + dir * 5 + 7, top + 25, 13.4, 13.4, ga), zb + 6)
			setZ(D.shape(E, 6, x, top - 12.5, 42, 19, if day >= 4 then C_LABEL else C_INK, 1, nil, nil, nil, 6), zb + 6)
			setZ(D.text(E, 4, "팀장", x, top - 8 - 5, 14 * G.TS, WHITE, 1), zb + 7)
			if day >= 2 then
				setZ(D.spr(E, 8, "fx/anger/1", x - dir * 24, top + 12, 1), zb + 6)
			end
		end
		if etype == "speaker" then
			local rage = e.hp < e.maxhp * 0.5
			if rage then
				local r = 74 + sin(time * 10) * 8
				setZ(D.img(E, 9, "fx/glow", x, y - 20, r * 2, r * 2, min(1, 0.2 * G.gl), nil, nil, C_SPKG), zb + 5)
			end
			-- 스피커에서 퍼지는 소리 물결
			local wx, wy = x + dir * 34, feet - 84
			local c0 = if dir > 0 then 0 else PI
			local n0 = L.ent.pools[16 * 8 + 2] and L.ent.pools[16 * 8 + 2].n or 0
			for k = 0, (if rage then 4 else 3) - 1 do
				local q = (time * 2.2 + k / 3) % 1
				D.arc(E, 16, wx, wy, 10 + q * (if rage then 46 else 32), c0 - 0.8, c0 + 0.8, 3.5 - q * 2, C_SPK, (1 - q) * 0.9, nil, 4)
			end
			local pool = L.ent.pools[16 * 8 + 2]
			if pool then
				for i = n0 + 1, pool.n do
					setZ(pool.items[i], zb + 6)
				end
			end
		end
		if etype == "bagman" and st == 4 then
			local a = e.anim * 15
			local n0 = L.ent.pools[17 * 8 + 2] and L.ent.pools[17 * 8 + 2].n or 0
			for t = 0, 3 do
				D.arc(E, 17, x, y, SPIN_R - 18, a - t * 0.3 - 0.35, a - t * 0.3, 26 - t * 5, C_SPIN, 0.5 - t * 0.11, nil, 2)
			end
			local pool = L.ent.pools[17 * 8 + 2]
			if pool then
				for i = n0 + 1, pool.n do
					setZ(pool.items[i], zb + 5)
				end
			end
			setZ(D.img(E, 18, "st/pack/1", x + cos(a) * (SPIN_R - 18), y + sin(a) * (SPIN_R - 18), 54, 59, 1, a + 1.6), zb + 6)
		end
	end

	-- ---------- 플레이어 ----------
	local C_GHOST, C_SLIP = lite("120,255,200"), rgb("120,200,255")
	local prec = nil :: any -- 플레이어 한 벌: 그림자(부모) + 고리 둘 + 몸
	local function drawPlayer(S)
		local E = L.ent
		local p = S.p
		local time = G.time
		local feet = p.y + p.r * 0.85
		local dir = if p.fx >= 0 then 1 else -1
		local fr = if p.moving or p.dashT > 0 then floor(p.anim * 11) % 4 else 0
		for _, g in ghosts do
			local ga = 1 - g.t / 0.3
			if ga > 0 then
				local zg = zOf(g.y)
				setZ(G.char(E, 20, "player", 0, g.f, g.dir, true, g.x, g.y + p.r * 0.85, 1, 0.5 * ga), zg)
				setZ(D.img(E, 21, "fx/glow", g.x, g.y - 10, 52, 52, min(1, 0.35 * ga * G.gl), nil, nil, C_GHOST), zg)
			end
		end
		local zb = zOf(p.y)
		if not prec then
			prec = newRec()
			prec.sh.Name = "Player"
			local function child(name: string, z: number)
				local g = Instance.new("ImageLabel")
				g.Name = name
				g.BackgroundTransparency = 1
				g.BorderSizePixel = 0
				g.AnchorPoint = Vector2.new(0.5, 0.5)
				g.ZIndex = z
				g.Parent = prec.sh
				D.created += 1
				return g
			end
			-- 그림자 30×15 안에서의 자리: 고리(40×20)의 가운데는 그림자 가운데에서 0.5 위
			prec.ring0 = child("Ring", 1)
			Art.set(prec.ring0, "fx/pring/0")
			prec.ring0.Position = fromScale(0.5, 0.5 - 0.5 / 15)
			prec.ring0.Size = fromScale(40 / 30, 20 / 15)
			prec.ring1 = child("Dash", 2)
			prec.ring1.Position = prec.ring0.Position
			prec.ring1.Size = prec.ring0.Size
			prec.ringK = -1
			prec.sp.ZIndex = 3
		end
		-- 발밑 고리: 대시가 다시 찰 때까지 1/8씩 차오른다 (다 차면 밝은 초록)
		local rdy = if p.dashCd <= 0 then 1 else 1 - p.dashCd / S.M.dashCd
		local rk = if rdy >= 1 then 8 else max(0, floor(rdy * 8))
		if prec.ringK ~= rk then
			prec.ringK = rk
			if rk == 0 then
				prec.ring1.Visible = false
			else
				Art.set(prec.ring1, "fx/pring/" .. rk)
				prec.ring1.Visible = true
			end
			D.writes += 3
		end
		if p.slow > 0 then
			setZ(D.text(E, 22, "미끌!", p.x, p.y - 48 - 4, 11 * G.TS, C_SLIP, 0.9, nil, nil, nil, D.FB), zb + 6)
		end
		local alpha = 1
		if p.inv > 0 and p.dashT <= 0 and floor(time * 24) % 2 == 0 then
			alpha = 0.45
		end
		local kq = if pk.t > 0 then sin(min(1, pk.t / 0.18) * PI) else 0
		local name = charName(G.hurtFlash > 0.42, "player", 0, if kq > 0.3 then 1 else fr)
		place(prec, name, dir < 0, p.x, feet - 0.5, 15, p.x + pk.x * kq, feet + pk.y * kq, 1 + kq * 0.06, alpha, zb + 4, true)
	end

	-- ---------- 적 · 플레이어 (y 순서) ----------
	function A.draw(S)
		stamp += 1
		-- 화면에 적이 아주 많으면(260 넘게) 보통 적의 발밑 그림자는 그리지 않는다(그리는 물건 수를 줄인다 — 빽빽하면 어차피 가려진다)
		if A.active > 260 then
			A.shadows = false
		elseif A.active < 200 then
			A.shadows = true
		end
		local p = S.p
		local vx0, vy0, vx1, vy1 = D.vx0, D.vy0, D.vx1, D.vy1
		-- 원본은 그릴 때마다 S.enemies를 y 순서로 정렬해 둔다(E.sort) — 규칙이 적을 도는 차례가 거기에 달려 있어 그대로 따른다.
		-- 거의 정렬된 채로 오므로 끼워 넣기 정렬이 싸다(같은 y끼리는 차례가 그대로 — 원본의 정렬과 같은 결과)
		local E = S.enemies
		for i = 2, #E do
			local e = E[i]
			local y = e.y
			local j = i - 1
			while j >= 1 and E[j].y > y do
				E[j + 1] = E[j]
				j -= 1
			end
			E[j + 1] = e
		end
		for _, e in E do
			if not e.dead then
				local m = if e.boss then 140 else 70
				local x, y = e.x, e.y
				if x > vx0 - m and x < vx1 + m and y > vy0 - m and y < vy1 + m then
					drawEnemy(S, e, p)
				end
			end
		end
		drawPlayer(S)
		-- 이번 장면에 그리지 않은 것은 놓아 준다
		for e, rec in map do
			if rec.stamp ~= stamp then
				release(e, rec)
			end
		end
	end

	-- ---------- 쓰러지는 모습 ----------
	function A.drawCorpses()
		local Cl = L.corpse
		for _, c in corpses do
			local d = chars[c.type]
			if d and D.inView(c.x, c.y, 80) then
				local q = c.t / c.life
				local s = c.sc * (1 - q * 0.25)
				local name = charName(q < 0.25, c.type, c.v, 0)
				local e = Art.info(name)
				local w0, h0 = e.w / e.s, e.h / e.s
				local rot = c.vr * c.t
				-- 발에서 16 위의 점을 축으로 돈다
				local ox = (w0 / 2 - (if c.dir > 0 then e.ox else w0 - e.ox)) * s
				local oy = (h0 / 2 - (e.oy - 16)) * s
				local cr, sr = cos(rot), sin(rot)
				D.img(Cl, 1, name, c.x + ox * cr - oy * sr, c.y - 14 - sin(q * PI) * (c.up or 22) + ox * sr + oy * cr, w0 * s, h0 * s, 1 - q * q, rot, c.dir < 0)
			end
		end
	end

	-- ---------- 보스의 말 ----------
	local C_BUBBLE = rgb("#fbfaf5")
	function A.drawSays(S)
		local Sy = L.say
		local time = G.time
		for _, e in S.bosses do
			local sy = says[e.id]
			if not e.dead and sy and sy.till >= time then
				local left = sy.till - time
				local al = min(1, left * 4, (2.8 - left) * 8)
				local sc = e.def.sc or 1
				local ts = floor(15 * G.TS + 0.5)
				if not sy.tw then
					local ok, size = pcall(function()
						return TextService:GetTextSize(sy.txt, ts, D.FD, Vector2.new(4000, 100))
					end)
					sy.tw = if ok and size then size.X else #sy.txt * 5
				end
				local bw, bh = sy.tw + 20, 27
				local bx = max(G.x0 + 6, min(G.x1 - bw - 6, e.x - bw / 2))
				local by = e.y - e.r - 42 * sc - bh - (if e.type == "crowd" then 40 else 0) + sin(time * 5) * 1.5
				-- 테두리(굵기 2)는 틀 바깥에 그려지므로 1씩 줄인다
				D.shape(Sy, 1, bx + bw / 2, by + bh / 2, bw - 2, bh - 2, C_BUBBLE, al, C_INK, al, 2, 8)
				local tx = max(bx + 12, min(bx + bw - 12, e.x))
				D.spr(Sy, 2, "ui/bubbletail", tx, by + bh, 1, al)
				D.text(Sy, 3, sy.txt, bx + 10, by + bh / 2 + 1, ts, C_INK, al, nil, nil, nil, D.FD, true)
			end
		end
	end

	-- ---------- 버스 · 열차 ----------
	local C_HEAD = lite("255,240,170")
	function A.drawVehicle(S)
		local T = S.train
		if not T or not T.on then
			return
		end
		local V = L.veh
		local dir, flip = T.dir, T.dir < 0
		if T.kind == "bus" then
			D.img(V, 1, "fx/glow", T.x + dir * 140, T.y, 360, 200, min(1, 0.4 * G.gl), nil, nil, C_HEAD)
			for i = 1, 0, -1 do
				D.img(V, 2, "ws/bus", T.x + dir * (-128 - i * 290), T.y, 256, 92, 1, nil, flip)
			end
		else
			D.img(V, 1, "fx/glow", T.x + dir * 170, T.y, 420, 220, min(1, 0.55 * G.gl), nil, nil, C_HEAD)
			for i = 4, 0, -1 do
				D.img(V, 2, if i == 0 then "st/cab" else "st/car", T.x + dir * (-216 * i - 106), T.y, 216, 84, 1, nil, flip)
			end
			D.img(V, 3, "fx/glow", T.x + dir, T.y - 29, 46, 46, 0.9, nil, nil, C_HEAD)
			D.img(V, 3, "fx/glow", T.x + dir, T.y + 29, 46, 46, 0.9, nil, nil, C_HEAD)
		end
	end

	-- ---------- 화면 밖 표시 ----------
	local function edgeArrow(tx: number, ty: number, name: string)
		local cx, cy, vw, vh = G.cx, G.cy, G.vw, G.vh
		local dx, dy = tx - cx, ty - cy
		if abs(dx) < vw / 2 - 20 and abs(dy) < vh / 2 - 20 then
			return
		end
		local a = atan2(dy, dx)
		local m = 36
		local ca, sa = abs(cos(a)), abs(sin(a))
		if ca == 0 then
			ca = 1e-6
		end
		if sa == 0 then
			sa = 1e-6
		end
		local k = min((vw / 2 - m) / ca, (vh / 2 - m) / sa)
		D.spr(L.ind, 1, name, cx + cos(a) * k, cy + sin(a) * k, 1, 1, a)
	end
	function A.drawIndicators(S)
		for _, e in S.bosses do
			if not e.dead then
				edgeArrow(e.x, e.y, "ui/edgearrow/boss")
			end
		end
		for _, it in S.items do
			if it.kind == "chest" then
				edgeArrow(it.x, it.y, "ui/edgearrow/chest")
			end
		end
		local T = S.train
		if T and not T.on then
			local cx, cy, vw, vh = G.cx, G.cy, G.vw, G.vh
			local yy = max(cy - vh / 2 + 60, min(cy + vh / 2 - 60, T.y))
			local xx = cx - T.dir * (vw / 2 - 46)
			local b = sin(G.time * 22) > 0
			D.spr(L.ind, 2, if b then "ui/warn/1" else "ui/warn/0", xx, yy, 1)
			D.text(L.ind, 3, "!", xx, yy + 14 - 9.4, 26 * G.TS, C_INK, 1)
			D.text(L.ind, 4, if T.kind == "bus" then "버스 진입" else "열차 진입", xx, yy + 40 - 5, 14 * G.TS, C_INK, 1, WHITE, 2)
		end
	end

	return A
end
