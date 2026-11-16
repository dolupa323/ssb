--!optimize 2
-- Sim.luau 를 시나리오대로 돌리고 요약 줄(digest)을 찍는다. js/driver.cjs 와 한 줄씩 짝이 맞는다.
-- 쓰는 법(run.mjs 가 만든 main_*.luau 에서): driver.run(jobs, Sim)
local P = require("./prng")
local hex = P.hex

local M32 = 4294967296
local function mix(h: number, v: number): number
	return (h * 31 + v) % M32
end
local strCache: { [string]: number } = {}
local function strHash(s: any): number
	s = tostring(s)
	local h = strCache[s]
	if h == nil then
		h = 7
		for i = 1, #s do
			h = mix(h, string.byte(s, i))
		end
		h = mix(h, #s)
		strCache[s] = h
	end
	return h
end
local nb = buffer.create(8)
local function numHash(x: number): number
	if x ~= x then
		return 29
	end
	buffer.writef64(nb, 0, x)
	return mix(mix(11, buffer.readu32(nb, 4)), buffer.readu32(nb, 0))
end
local function valHash(v: any): number
	local t = type(v)
	if t == "number" then
		return numHash(v)
	elseif t == "string" then
		return mix(13, strHash(v))
	elseif t == "boolean" then
		return if v then 17 else 19
	elseif t == "table" then
		local h = 23
		for i = 1, #v do
			h = mix(h, valHash(v[i]))
		end
		return mix(h, #v)
	end
	error("해시할 수 없는 값: " .. t)
end
-- 이벤트 하나: 칸의 순서와 무관하게 (열쇠, 값) 해시의 합
local function evHash(e: any): number
	local s = 0
	for k, v in e do
		s = (s + mix(strHash(k), valHash(v))) % M32
	end
	return s
end
local out: { string } = {}
local function flush()
	if #out > 0 then
		print(table.concat(out, "\n"))
		table.clear(out)
	end
end
local function emit(s: string)
	out[#out + 1] = s
	if #out >= 2000 then
		flush()
	end
end
local function copy(t: any): any
	local o = {}
	if t then
		for k, v in t do
			o[k] = v
		end
	end
	return o
end
local function deepcopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in t do
		o[k] = deepcopy(v)
	end
	return o
end
local function sortedKeys(t: any): { string }
	local ks = {}
	for k in t do
		ks[#ks + 1] = k
	end
	table.sort(ks)
	return ks
end
-- 숫자를 JS 의 String(n) 처럼 (여기서는 정수만 나온다)
local function nstr(v: any): string
	return tostring(v)
end

local Sim: any = nil
local constsDump

local function runJob(spec: any)
	local rng = P.makeRng(spec.seed)
	local R = rng.next
	local HA, HD, evCount, hostCount, tick, ended = 0, 0, 0, 0, 0, nil :: any
	local CF = { "kind", "key", "name", "desc", "tag", "hint" }
	local function choicesHash(ch, mode)
		HD = mix(HD, strHash(mode))
		for _, c in ipairs(ch) do
			for _, f in ipairs(CF) do
				HD = mix(HD, strHash(c[f]))
			end
			HD = mix(HD, valHash(c.to))
			if c.wt ~= nil then
				HA = mix(HA, numHash(c.wt))
			end
		end
	end
	local host = {
		sfx = function(name, x, arg)
			hostCount += 1
			local n = strHash(name)
			HA = mix(HA, n)
			HD = mix(HD, n)
			HA = mix(HA, if x == nil then 3 else numHash(x))
			if arg == nil then
				HA = mix(HA, 5)
			else
				HA = mix(HA, valHash(arg))
				if type(arg) ~= "number" then
					HD = mix(HD, valHash(arg))
				end
			end
		end,
		banner = function(a, b, kind)
			hostCount += 1
			local v = if a == nil then 3 else strHash(a)
			HA = mix(HA, v)
			HD = mix(HD, v)
			v = if b == nil then 3 else strHash(b)
			HA = mix(HA, v)
			HD = mix(HD, v)
			v = if kind == nil then 3 else strHash(kind)
			HA = mix(HA, v)
			HD = mix(HD, v)
		end,
		shake = function(a)
			hostCount += 1
			HA = mix(HA, numHash(a))
			HD = mix(HD, 37)
		end,
		levelUp = function(ch, mode)
			hostCount += 1
			HD = mix(HD, 47)
			choicesHash(ch, mode)
		end,
		finish = function(won)
			hostCount += 1
			HD = mix(HD, if won then 41 else 43)
			ended = won
		end,
	}
	local function mkOpts(extra: any?, dropBuild: boolean?)
		local o = copy(spec.opts)
		if extra then
			for k, v in extra do
				o[k] = v
			end
		end
		if dropBuild then
			o.build = nil
		end
		if spec.pick == "auto" then
			o.autoPick = function(ch, S)
				HD = mix(HD, 53)
				choicesHash(ch, S.pickMode)
				return ch[math.floor(R() * #ch) + 1]
			end
		end
		o.rng = R
		return o
	end
	local view = spec.view or { w = 1280, h = 720 }
	local dt, every, dense = 1 / (spec.dtDiv or 60), spec.digestEvery or 60, spec.denseUntil or 0
	local sim = Sim.create(host, mkOpts())
	local function kv(o, order)
		local t = {}
		for i, k in ipairs(order) do
			t[i] = k .. ":" .. nstr(o[k])
		end
		return table.concat(t, ",")
	end
	local function buildStr()
		local S = sim.S
		return "w=" .. kv(S.weapons, S.wOrder) .. ";p=" .. kv(S.passives, S.pOrder) .. ";f=" .. kv(S.fus, S.fOrder) .. ";fs=" .. table.concat(sortedKeys(S.fsrc), ",")
	end
	local LISTS = { "beans", "bullets", "shots", "items", "zones", "waves", "puddles", "mines", "riders", "rangs", "slicks" }
	local function digest(tag: string)
		local S = sim.S
		local p = S.p
		local sx, sy, sh, eh, oh = 0, 0, 0, 0, 0
		for _, e in ipairs(S.enemies) do
			sx += e.x
			sy += e.y
			sh += e.hp
			eh = mix(mix(mix(mix(mix(eh, e.id), strHash(e.type)), numHash(e.x)), numHash(e.y)), numHash(e.hp))
		end
		for _, L in ipairs(LISTS) do
			for _, o in ipairs(S[L]) do
				oh = mix(mix(oh, numHash(o.x)), numHash(o.y))
			end
		end
		for _, o in ipairs(S.lobs) do
			oh = mix(mix(mix(oh, numHash(o.x1)), numHash(o.y1)), numHash(o.t))
		end
		for _, o in ipairs(S.beams) do
			oh = mix(mix(oh, numHash(o.a)), numHash(o.life))
		end
		local ints = { tick, S.state, S.zone, S.phase, S.rage, p.level, S.kills, S.pending, S.pickMode, #S.enemies, #S.beans, #S.bullets, #S.shots, #S.items, #S.zones, #S.waves, #S.puddles, #S.mines, #S.bosses, rng.calls, evCount, hostCount }
		local fl = { S.t, p.x, p.y, p.hp, p.maxhp, p.xp, p.inv, sx, sy, sh, S.zt, S.spawnAcc }
		local hs = { HA, HD, eh, oh, strHash(buildStr()) }
		for i, v in ipairs(ints) do
			ints[i] = nstr(v)
		end
		for i, v in ipairs(fl) do
			fl[i] = hex(v)
		end
		for i, v in ipairs(hs) do
			hs[i] = nstr(v)
		end
		emit(tag .. " " .. table.concat(ints :: any, " ") .. " | " .. table.concat(fl :: any, " ") .. " | " .. table.concat(hs :: any, " "))
	end
	local function drain()
		local S = sim.S
		for _, e in ipairs(S.ev) do
			HA = mix(HA, evHash(e))
			HD = mix(HD, strHash(e.k))
			evCount += 1
		end
		table.clear(S.ev)
	end
	local function manualPick()
		local S = sim.S
		local guard = 0
		while S.state == "levelup" and guard < 50 do
			guard += 1
			local pol = spec.manual or "first"
			if pol == "reroll" then
				local g = 0
				while sim.reroll() and g < 20 do
					g += 1
				end
			end
			local n = #S.choices
			sim.choose(if pol == "rng" then math.floor(R() * n) + 1 elseif pol == "last" then n else 1)
		end
	end
	local function obj(name: string): any
		local S = sim.S
		if name == "S" then
			return S
		elseif name == "p" then
			return S.p
		elseif name == "boss" then
			return S.boss
		elseif name == "gate" then
			return S.gate
		elseif name == "M" then
			return S.M
		elseif name == "train" then
			return S.train
		elseif name == "input" then
			return S.input
		end
		return nil
	end
	emit("# " .. spec.name)
	for _, st in ipairs(spec.steps) do
		local S = sim.S
		local p = S.p
		local op = st.op
		if op == "run" then
			for _ = 1, st.ticks do
				if S.state == "over" or S.state == "won" then
					break
				end
				if S.state == "levelup" then
					manualPick()
				end
				if st.input == "bot" then
					local b = sim.bot()
					S.input = b
					if b.dash then
						sim.dash()
					end
				elseif type(st.input) == "table" then
					S.input = { x = st.input.x, y = st.input.y }
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
				sim.update(dt, view)
				drain()
				tick += 1
				if tick % every == 0 or tick < dense then
					digest("D")
				end
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
				if st.spd ~= nil then
					e.spd = st.spd
				end
				if st.dmg ~= nil then
					e.dmg = st.dmg
				end
				if st.elite then
					e.elite = true
				end
			end
		elseif op == "killAll" then
			for _, e in ipairs(table.clone(S.enemies)) do
				if not e.dead then
					sim.dbg.kill(e, st.src)
					if st.twice then
						sim.dbg.kill(e, st.src)
					end
				end
			end
		elseif op == "set" then
			local o = obj(st.obj)
			if o then
				o[st.key] = st.value
			end
		elseif op == "setAll" then
			for _, e in ipairs(S.enemies) do
				e[st.key] = st.value
			end
		elseif op == "bossHp" then
			for _, e in ipairs(S.bosses) do
				e.hp = e.maxhp * st.frac
			end
		elseif op == "dash" then
			HD = mix(HD, if sim.dash() then 59 else 61)
		elseif op == "reroll" then
			HD = mix(HD, if sim.reroll() then 67 else 71)
		elseif op == "choose" then
			sim.choose(st.i)
		elseif op == "pending" then
			S.pending += st.n
			S.pickMode = st.mode
		elseif op == "item" then
			table.insert(S.items, { kind = st.kind, x = p.x + st.dx, y = p.y + st.dy, t = 0 })
		elseif op == "xp" then
			p.xp += st.v
		elseif op == "setDiff" then
			sim.dbg.setDiff(st.i)
		elseif op == "build" then
			local fsrc, fus = {}, {}
			for _, k in ipairs(st.fOrder or {}) do
				fus[k] = 1
				fsrc[Sim.FUSIONS[k].a] = 1
				fsrc[Sim.FUSIONS[k].b] = 1
			end
			S.weapons = copy(st.weapons)
			S.passives = copy(st.passives)
			S.fus = fus
			S.fsrc = fsrc
			-- Lua 쪽에서는 순서 목록도 같이 갈아 끼운다
			S.wOrder = table.clone(st.wOrder or {})
			S.pOrder = table.clone(st.pOrder or {})
			S.fOrder = table.clone(st.fOrder or {})
			table.clear(S.beams)
			S.umbQ = nil
			sim.dbg.recalc()
		elseif op == "roundtrip" then
			local ser = deepcopy(sim.serialize())
			local h = 0
			for _, k in ipairs({ "diff", "zone", "t", "hp", "level", "xp", "kills", "rerolls", "x", "y" }) do
				h = mix(h, numHash(ser[k]))
			end
			local orders = { weapons = ser.wOrder, passives = ser.pOrder, dmg = ser.dmgOrder, fus = ser.fOrder, fsrc = sortedKeys(ser.fsrc) }
			for _, m in ipairs({ "weapons", "passives", "dmg", "fus", "fsrc" }) do
				for _, k in ipairs(orders[m]) do
					h = mix(mix(h, strHash(k)), numHash(ser[m][k]))
				end
				h = mix(h, 73)
			end
			emit("R " .. nstr(h))
			sim = Sim.create(host, mkOpts({ restore = ser }, true))
		elseif op == "digest" then
			digest("D")
		elseif op == "update" then
			sim.update(dt, view)
			drain()
		elseif op == "fus" then
			local F = Sim.FUSIONS[st.key]
			if st.on then
				S.fus[st.key] = 1
				S.fsrc[F.a] = 1
				S.fsrc[F.b] = 1
			else
				S.fus[st.key] = nil
				S.fsrc[F.a] = nil
				S.fsrc[F.b] = nil
			end
			sim.dbg.recalc()
		elseif op == "consts" then
			constsDump()
		else
			error("모르는 op: " .. tostring(op))
		end
	end
	drain()
	digest("E")
	do
		local S = sim.S
		local p = S.p
		local dm = {}
		for i, k in ipairs(S.dmgOrder) do
			dm[i] = k .. ":" .. hex(S.dmg[k])
		end
		local tb = {}
		for i, k in ipairs(sortedKeys(S.takenBy)) do
			tb[i] = k .. ":" .. hex(S.takenBy[k])
		end
		emit(table.concat({
			"F", spec.name, S.state, nstr(S.zone), nstr(tick), hex(S.t), nstr(p.level), nstr(S.kills), if S.late then "1" else "0", nstr(S.rerolls), nstr(S.dashes),
			hex(p.hp), hex(S.taken), if ended == nil then "-" elseif ended then "won" else "lost", buildStr(), "dmg=" .. table.concat(dm, ","), "by=" .. table.concat(tb, ","),
		}, "|"))
	end
end

-- 바뀌지 않는 자료: 표 · 수치 · 글을 한 줄씩 찍는다 (원본 sim.js 가 내보내는 것만)
local function fieldsStr(d: any, fmt: (any) -> string): string
	local t = {}
	for i, f in ipairs(sortedKeys(d)) do
		t[i] = f .. "=" .. fmt(d[f])
	end
	return table.concat(t, ",")
end
function constsDump()
	local W, PS, F, E = Sim.WEAPONS, Sim.PASSIVES, Sim.FUSIONS, Sim.ENEMIES
	local xs = {}
	for i = 1, 150 do
		xs[i] = nstr(Sim.xpNeed(i))
	end
	emit("C xp " .. table.concat(xs, ","))
	local cs = {}
	for i, t in ipairs({ 0, 1, 8.9, 9, 59.9, 60, 269.5, 539.99, 540, 541, 600, 1079, 5400 }) do
		cs[i] = Sim.clockText(t)
	end
	emit("C clock " .. table.concat(cs, ","))
	emit("C nums " .. nstr(Sim.EVO) .. "," .. nstr(Sim.GAME_LEN))
	emit("C worder " .. table.concat(Sim.WEAPON_ORDER, ","))
	for _, k in ipairs(Sim.WEAPON_ORDER) do
		local w = W[k]
		emit("C w " .. k .. " " .. nstr(strHash(table.concat({ w.name, w.evoName, w.pair, w.evoDesc }, "|"))) .. " " .. nstr(#w.lv) .. " " .. nstr(strHash(table.concat(w.lv, "|"))))
		for l = 1, 8 do
			emit("C stat " .. k .. " " .. nstr(l) .. " " .. fieldsStr(w.stat(l), function(v)
				return if type(v) == "number" then hex(v) else tostring(v)
			end))
		end
	end
	emit("C porder " .. table.concat(Sim.PASSIVE_ORDER, ","))
	for _, k in ipairs(Sim.PASSIVE_ORDER) do
		emit("C p " .. k .. " " .. nstr(strHash(PS[k].name .. "|" .. PS[k].desc)))
	end
	emit("C forder " .. table.concat(Sim.FUSION_ORDER, ","))
	for _, k in ipairs(Sim.FUSION_ORDER) do
		emit("C f " .. k .. " " .. F[k].a .. " " .. F[k].b .. " " .. nstr(strHash(F[k].name .. "|" .. F[k].desc)))
	end
	emit("C eorder " .. table.concat(Sim.ENEMY_ORDER, ","))
	for _, k in ipairs(Sim.ENEMY_ORDER) do
		emit("C e " .. k .. " " .. fieldsStr(E[k], function(v)
			return if type(v) == "number" then hex(v) elseif type(v) == "string" then nstr(strHash(v)) else tostring(v)
		end))
	end
	for i, d in ipairs(Sim.DIFFS) do
		emit("C diff " .. nstr(i - 1) .. " " .. fieldsStr(d, function(v)
			return if type(v) == "number" then hex(v) else nstr(strHash(v))
		end))
	end
	for i, z in ipairs(Sim.ZONES) do
		emit("C zone " .. nstr(i - 1) .. " " .. fieldsStr(z, function(v)
			return if type(v) == "number" then hex(v) elseif type(v) == "table" then table.concat(v, "/") else nstr(strHash(v))
		end))
	end
	for _, k in ipairs(sortedKeys(Sim.GATE)) do
		emit("C gate " .. k .. " " .. fieldsStr(Sim.GATE[k], function(v)
			return tostring(v)
		end))
	end
end

local M = {}
function M.run(jobs: { any }, sim: any)
	Sim = sim
	local t0 = os.clock()
	for _, spec in ipairs(jobs) do
		local ok, err = pcall(runJob, spec)
		if not ok then
			emit("X " .. spec.name .. " " .. string.gsub(tostring(err), "%s+", " "))
		end
	end
	flush()
	print(string.format("T %.3f", os.clock() - t0))
end
return M
