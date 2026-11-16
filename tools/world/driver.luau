-- 장면 시험의 몸통 (tools/world/run.mjs가 맨 앞에 `local SPEC = {…}`를 붙여 시나리오로 만든다)
--  SPEC = { name, seed, diff, mode, offX, build = { w = {{이름, 레벨}…}, p = {…} }, steps = { {op=…}… } }
--  op: run{ticks,input,dashEvery,hold,keepHp,stepEvery} · enterZone{i} · boss{type} · spawn{type,n,r,ry,hp,elite} · set{obj,key,value} · setAll{key,value}
--      bossHp{frac} · build{w,p,fus} · item{kind,dx,dy} · xp{v} · opts{…} · shot{name} · celebrate · steady{ticks,expectNoCreate}
--  원본 쪽(tools/world/orig/driver.js)이 같은 SPEC을 같은 뜻으로 읽는다 — 같은 씨앗이면 같은 판이 된다.
local h = harness
local RS = game:GetService("ReplicatedStorage")
local Sim = h.require(RS.shared.Sim)
local client = h.player().PlayerScripts.client
local Art = h.require(client.Art)
local Gfx = h.require(client.Gfx)

-- 씨앗 난수 (mulberry32 — tools/parity의 것과 같다)
local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift
local function imul(a, b)
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	return (lshift((ah * bl + al * bh) % 4294967296, 16) + al * bl) % 4294967296
end
local function makeRng(seed)
	local a = seed % 4294967296
	return function()
		a = (a + 0x6D2B79F5) % 4294967296
		local t = imul(bxor(a, rshift(a, 15)), bor(1, a))
		t = bxor((t + imul(bxor(t, rshift(t, 7)), bor(61, t))) % 4294967296, t)
		return bxor(t, rshift(t, 14)) / 4294967296
	end
end

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
end, 30, "Art.ready")
h.eq(#Art.failed, 0, "판을 모두 만들었다")
Gfx.init(world, overlay)
h.step(1)
math.randomseed(SPEC.seed + 7)

local R0 = makeRng(SPEC.seed)
local calls = 0
local function R()
	calls += 1
	return R0()
end
local host = {
	sfx = function() end,
	banner = function() end,
	shake = function(a)
		Gfx.shake(a)
	end,
	levelUp = function() end,
	finish = function() end,
}
local function pairsOf(list)
	local map, order = {}, {}
	for _, kv in list or {} do
		map[kv[1]] = kv[2]
		table.insert(order, kv[1])
	end
	return map, order
end
local opts = {
	diff = SPEC.diff or 2,
	rng = R,
	autoPick = function(ch)
		return ch[math.floor(R() * #ch) + 1]
	end,
}
if SPEC.build then
	local w, wo = pairsOf(SPEC.build.w)
	local p, po = pairsOf(SPEC.build.p)
	opts.build = { weapons = w, passives = p, wOrder = wo, pOrder = po }
end
local sim = Sim.create(host, opts)
local S = sim.S
local mode = SPEC.mode or "play"
local dt = 1 / 60
local tick = 0
local maxVisible, maxWrites, maxEnemies, sumMs, nMs, maxMs = 0, 0, 0, 0, 0, 0
local peakInfo = ""

local function frame(st, doStep)
	local p = S.p
	local input = st.input or "bot"
	if input == "bot" then
		local b = sim.bot()
		S.input = b
		if b.dash then
			sim.dash()
		end
	elseif type(input) == "table" then
		S.input = { x = input.x, y = input.y }
	else
		S.input = { x = 0, y = 0 }
	end
	if st.dashEvery and tick % st.dashEvery == 0 then
		sim.dash()
	end
	if st.hold ~= nil and (S.phase == "crowd" or S.phase == "ride") and S.zt > st.hold then
		S.zt = st.hold
	end
	if st.keepHp then
		p.hp = p.maxhp
	end
	if not Gfx.frozen() then
		sim.update(dt, Gfx.view())
	end
	local t0 = h.wallClock()
	Gfx.render(S, { mode = mode, dt = dt, running = true, fx = false, offX = SPEC.offX or 0, offY = 0 })
	local ms = (h.wallClock() - t0) * 1000
	sumMs += ms
	nMs += 1
	maxMs = math.max(maxMs, ms)
	local stt = Gfx.stats()
	if stt.visible > maxVisible then
		peakInfo = ("tick %d: %s"):format(tick, Gfx.G.D.breakdown(12))
	end
	maxVisible = math.max(maxVisible, stt.visible)
	maxWrites = math.max(maxWrites, stt.writes)
	maxEnemies = math.max(maxEnemies, #S.enemies)
	tick += 1
	if doStep then
		h.step(1)
	end
end

for _, st in SPEC.steps do
	local op = st.op
	local p = S.p
	if op == "run" then
		local every = st.stepEvery or 1
		for i = 1, st.ticks do
			if S.state ~= "run" then
				break
			end
			frame(st, i % every == 0)
		end
	elseif op == "enterZone" then
		S.zone = st.i
		sim.dbg.enterZone(st.i)
	elseif op == "boss" then
		sim.dbg.boss(st.type)
	elseif op == "spawn" then
		for _ = 1, st.n do
			local x = p.x + (R() * 2 - 1) * st.r
			local y = p.y + (R() * 2 - 1) * (if st.ry == nil then st.r else st.ry)
			local e = sim.dbg.spawn(st.type, x, y)
			if st.hp ~= nil then
				e.maxhp = st.hp
				e.hp = st.hp
			end
			if st.elite then
				e.elite = true
			end
		end
	elseif op == "set" then
		local o = if st.obj == "S" then S elseif st.obj == "p" then S.p elseif st.obj == "M" then S.M elseif st.obj == "train" then S.train else nil
		if o then
			o[st.key] = st.value
		end
	elseif op == "setAll" then
		for _, e in S.enemies do
			e[st.key] = st.value
		end
	elseif op == "bossHp" then
		for _, e in S.bosses do
			e.hp = e.maxhp * st.frac
		end
	elseif op == "build" then
		local fsrc, fus = {}, {}
		for _, k in st.fus or {} do
			fus[k] = 1
			fsrc[Sim.FUSIONS[k].a] = 1
			fsrc[Sim.FUSIONS[k].b] = 1
		end
		local w, wo = pairsOf(st.w)
		local pp, po = pairsOf(st.p)
		S.weapons, S.passives, S.fus, S.fsrc = w, pp, fus, fsrc
		S.wOrder, S.pOrder, S.fOrder = wo, po, table.clone(st.fus or {})
		table.clear(S.beams)
		S.umbQ = nil
		sim.dbg.recalc()
	elseif op == "item" then
		table.insert(S.items, { kind = st.kind, x = p.x + st.dx, y = p.y + st.dy, t = 0 })
	elseif op == "xp" then
		p.xp += st.v
	elseif op == "opts" then
		Gfx.opts(st)
	elseif op == "celebrate" then
		Gfx.celebrate()
	elseif op == "shot" then
		h.step(1)
		h.shot(SPEC.name .. "." .. st.name .. ".png")
		local stt = Gfx.stats()
		print(("  [%s] t=%.1f 장소 %d(%s) 적 %d · 보이는 것 %d · 입자 %d"):format(st.name, S.t, S.zone, S.zk, #S.enemies, stt.visible, stt.parts))
		local vv, zz = Gfx.view(), Gfx.size()
		print(("  화면 %dx%d · 보이는 세계 %.1fx%.1f"):format(zz.W, zz.H, vv.w, vv.h))
		print(("  견줌: %s tick %d t=%.4f p=(%.3f,%.3f) enemies %d kills %d lv %d rng %d"):format(st.name, tick, S.t, S.p.x, S.p.y, #S.enemies, S.kills, S.p.level, calls))
	elseif op == "steady" then
		-- 같은 상황을 한참 돌린 뒤에는 새로 만드는 것이 없어야 한다
		local c0 = Gfx.stats().created
		local sizes0 = {}
		for _, Ly in Gfx.G.D.layers do
			for key, pool in Ly.pools do
				sizes0[Ly.name .. ":" .. (key // 8) .. ":" .. (key % 8)] = #pool.items
			end
		end
		local m0, n0 = sumMs, nMs
		local wr, vis = 0, 0
		for _ = 1, st.ticks do
			if S.state ~= "run" then
				break
			end
			frame(st, false)
			local stt = Gfx.stats()
			wr += stt.writes
			vis = math.max(vis, stt.visible)
		end
		local c1 = Gfx.stats().created
		local n = nMs - n0
		print(("  [steady %s] %d장 · 적 %d · 보이는 것 최대 %d · 속성 쓰기 평균 %.0f/장 · Gfx.render 평균 %.2f ms(luau.exe) · 새로 만든 것 %d"):format(st.name or "", n, #S.enemies, vis, wr / math.max(1, n), (sumMs - m0) / math.max(1, n), c1 - c0))
		local grown = {}
		for _, Ly in Gfx.G.D.layers do
			for key, pool in Ly.pools do
				local nm = Ly.name .. ":" .. (key // 8) .. ":" .. (key % 8)
				local d = #pool.items - (sizes0[nm] or 0)
				if d > 0 then
					table.insert(grown, { nm = nm, d = d })
				end
			end
		end
		table.sort(grown, function(a, b)
			return a.d > b.d
		end)
		local parts = {}
		for i = 1, math.min(10, #grown) do
			parts[i] = grown[i].nm .. "+" .. grown[i].d
		end
		if #parts > 0 then
			print("    늘어난 풀: " .. table.concat(parts, " "))
		end
		if st.expectNoCreate then
			h.eq(c1 - c0, 0, "한참 돌린 뒤에는 새로 만들지 않는다 (" .. (st.name or "") .. ")")
		end
	else
		error("모르는 op: " .. tostring(op))
	end
end

local stt = Gfx.stats()
print("  가장 많이 보일 때 — " .. peakInfo)
h.eq(stt.errors, 0, "Gfx.render 안에서 난 오류가 없다" .. (if Gfx.lastError then ": " .. tostring(Gfx.lastError) else ""))
print(("끝 [%s] tick %d · t=%.1f · 상태 %s · 장소 %d · 레벨 %d · 처치 %d · 적 최대 %d · 보이는 것 최대 %d · 한 장면 속성 쓰기 최대 %d · 만든 것 %d · Gfx.render 평균 %.2f ms 최대 %.1f ms"):format(
	SPEC.name, tick, S.t, tostring(S.state), S.zone, S.p.level, S.kills, maxEnemies, maxVisible, maxWrites, stt.created, sumMs / math.max(1, nMs), maxMs))
