--!optimize 2
-- Lua 쪽에만 있는 것의 검사: 순서 목록, 순서 목록 없는 복원, syncOrder, math.random 기본값, 1부터 세는 choose.
local P = require("./prng")
return function(Sim: any)
	local function check(name: string, cond: any, detail: string?)
		print((if cond then "ok   " else "FAIL ") .. name .. (if detail then "  " .. detail else ""))
	end
	local function join(t)
		return table.concat(t, ",")
	end
	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end
	local function mkHost(log)
		return {
			sfx = function() end,
			banner = function() end,
			shake = function() end,
			levelUp = function(ch, mode)
				log.levelUp = (log.levelUp or 0) + 1
				log.mode = mode
				log.n = #ch
			end,
			finish = function(won)
				log.finish = won
			end,
		}
	end

	-- 1. 기본 시작
	do
		local log = {}
		local sim = Sim.create(mkHost(log), { rng = P.makeRng(1).next })
		check("기본: 교통카드 1 · 운동화 1, 순서 목록", join(sim.S.wOrder) == "card" and join(sim.S.pOrder) == "shoes" and #sim.S.fOrder == 0)
		check("기본: 난이도 2(혼잡) · 멘탈 100", sim.S.diff == 2 and sim.S.p.hp == 100 and sim.S.p.maxhp == 100)
	end

	-- 2. 손으로 고르며 넣은 순서를 따로 적어 두고 순서 목록과 견준다 (조합이 생기면 재료가 빠지고 fOrder 에 붙는다)
	do
		local log = {}
		local rng = P.makeRng(77)
		local sim = Sim.create(mkHost(log), { rng = rng.next, diff = 0, xpMul = 30, build = { weapons = { handle = 5, card = 5 }, passives = { energy = 1, shoes = 1 }, wOrder = { "handle", "card" }, pOrder = { "energy", "shoes" } } })
		local S = sim.S
		local wo, po, fo = { "handle", "card" }, { "energy", "shoes" }, {}
		local okOrder, picks, sawFuse = true, 0, false
		local view = { w = 1280, h = 720 }
		for _ = 1, 60 * 400 do
			if S.state == "levelup" then
				local n = #S.choices
				local i = math.floor(rng.next() * n) + 1
				-- 프리패스(교통카드 + 손잡이) 조합 쪽으로 몬다: 조합 > 진화 > 재료와 짝 장비 > 새 무기가 아닌 것 > 무작위
				local want = { card = 3, handle = 3, shoes = 3, energy = 3 }
				local best = 0
				for j, c in ipairs(S.choices) do
					local sc = if c.kind == "fuse" then 5 elseif c.kind == "evo" then 4 elseif want[c.key] then 3 elseif c.tag ~= "새 무기" then 1 else 0
					if sc > best then
						best = sc
						i = j
					end
				end
				local c = S.choices[i]
				if c.kind == "fuse" then
					sawFuse = true
					local f = Sim.FUSIONS[c.key]
					for k = #wo, 1, -1 do
						if wo[k] == f.a or wo[k] == f.b then
							table.remove(wo, k)
						end
					end
					table.insert(fo, c.key)
				elseif c.kind == "weapon" or c.kind == "evo" then
					if not table.find(wo, c.key) then
						table.insert(wo, c.key)
					end
				elseif c.kind == "passive" then
					if not table.find(po, c.key) then
						table.insert(po, c.key)
					end
				end
				sim.choose(i)
				picks += 1
				if join(S.wOrder) ~= join(wo) or join(S.pOrder) ~= join(po) or join(S.fOrder) ~= join(fo) then
					okOrder = false
				end
				if count(S.weapons) ~= #S.wOrder or count(S.passives) ~= #S.pOrder or count(S.fus) ~= #S.fOrder then
					okOrder = false
				end
			elseif S.state ~= "run" then
				break
			else
				local b = sim.bot()
				S.input = b
				if b.dash then
					sim.dash()
				end
				S.p.hp = S.p.maxhp
				sim.update(1 / 60, view)
				table.clear(S.ev)
			end
		end
		check("고른 순서 = S.wOrder · S.pOrder · S.fOrder (" .. picks .. "번 고름" .. (if sawFuse then ", 조합 포함" else "") .. ")", okOrder and picks > 20, join(S.wOrder) .. " | " .. join(S.pOrder) .. " | " .. join(S.fOrder))
		check("조합까지 가 봤다", sawFuse)
		local uniq, okD = {}, count(S.dmg) == #S.dmgOrder
		for _, k in ipairs(S.dmgOrder) do
			if uniq[k] or S.dmg[k] == nil then
				okD = false
			end
			uniq[k] = true
		end
		check("S.dmgOrder 가 S.dmg 의 키와 맞는다", okD and #S.dmgOrder > 0, join(S.dmgOrder))
		-- 저장 → 복원: 순서가 그대로
		local ser = sim.serialize()
		check("serialize 가 순서 목록을 같이 내보낸다", ser.wOrder == S.wOrder and ser.pOrder == S.pOrder and ser.fOrder == S.fOrder and ser.dmgOrder == S.dmgOrder and ser.weapons == S.weapons)
		local sim2 = Sim.create(mkHost({}), { restore = ser, rng = rng.next })
		check("복원: 순서 목록이 그대로", join(sim2.S.wOrder) == join(S.wOrder) and join(sim2.S.pOrder) == join(S.pOrder) and join(sim2.S.fOrder) == join(S.fOrder) and join(sim2.S.dmgOrder) == join(S.dmgOrder))
		check("복원: 맵은 사본이다", sim2.S.weapons ~= S.weapons and sim2.S.wOrder ~= S.wOrder)
	end

	-- 3. 순서 목록 없이 복원 · 빌드 → 상수 순서
	do
		local sim = Sim.create(mkHost({}), { rng = P.makeRng(3).next, restore = { diff = 1, zone = 2, t = 50, hp = 60, level = 5, xp = 1, kills = 9, weapons = { gum = 2, card = 3, tie = 1 }, passives = { vitamin = 1, will = 2 }, dmg = { tie = 5, card = 9 }, rerolls = 1, fus = {}, fsrc = {} } })
		check("순서 목록 없는 복원 → 상수 순서", join(sim.S.wOrder) == "card,tie,gum" and join(sim.S.pOrder) == "will,vitamin" and join(sim.S.dmgOrder) == "card,tie", join(sim.S.wOrder) .. " | " .. join(sim.S.pOrder) .. " | " .. join(sim.S.dmgOrder))
		check("복원한 값", sim.S.zone == 2 and sim.S.t == 50 and sim.S.p.hp == 60 and sim.S.p.level == 5 and sim.S.kills == 9 and sim.S.rerolls == 1 and sim.S.diff == 1)
		local sim3 = Sim.create(mkHost({}), { rng = P.makeRng(3).next, build = { weapons = { gum = 2, card = 3 }, passives = { will = 2 }, wOrder = { "gum", "card" } } })
		check("빌드: 주어진 순서를 따른다", join(sim3.S.wOrder) == "gum,card" and join(sim3.S.pOrder) == "will")
		-- 밖에서 갈아 끼움 (실험실 방식)
		local S = sim3.S
		S.weapons = { tie = 7, umbrella = 7, card = 1 }
		S.passives = {}
		S.fus = { gentleman = 1 }
		S.fsrc = { umbrella = 1, tie = 1 }
		S.weapons.tie = nil
		S.weapons.umbrella = nil
		sim3.dbg.recalc()
		check("밖에서 갈아 끼운 뒤 recalc → 순서 목록이 맞춰진다", join(S.wOrder) == "card" and #S.pOrder == 0 and join(S.fOrder) == "gentleman")
		S.weapons = { anc = 2, card = 1 }
		sim3.dbg.syncOrder()
		check("syncOrder: 있던 키는 제자리, 새 키는 뒤에", join(S.wOrder) == "card,anc")
	end

	-- 4. opts.rng 없이 (math.random) 끝까지 도는가 · host.finish
	do
		local log = {}
		local sim = Sim.create(mkHost(log), { diff = 3, autoPick = function(ch)
			return ch[1]
		end })
		local S = sim.S
		local n = 0
		while S.state == "run" and n < 60 * 600 do
			S.input = { x = 0, y = 0 }
			sim.update(1 / 60, { w = 1280, h = 720 })
			table.clear(S.ev)
			n += 1
		end
		check("math.random 기본값으로 가만히 서 있으면 죽는다 → host.finish(false)", S.state == "over" and log.finish == false, "tick " .. n)
		sim.update(1 / 60)
		check("끝난 뒤의 update · dash · choose · reroll 은 아무 일도 하지 않는다", sim.dash() == false and sim.reroll() == false and sim.choose(1) == nil and S.state == "over")
	end

	-- 5. choose 는 1부터
	do
		local log = {}
		local sim = Sim.create(mkHost(log), { rng = P.makeRng(9).next, diff = 1 })
		local S = sim.S
		S.pending = 1
		S.pickMode = "start"
		sim.update(1 / 60, { w = 1280, h = 720 })
		check("시작 무기 고르기: host.levelUp(choices 3개, 'start')", S.state == "levelup" and log.mode == "start" and log.n == 3)
		check("시작 무기 고르기에서는 reroll 이 거절된다", sim.reroll() == false)
		local c = S.choices[1]
		sim.choose(0)
		check("choose(0) 은 아무 일도 하지 않는다", S.state == "levelup")
		sim.choose(1)
		check("choose(1) 이 첫 선택지를 고른다", S.state == "run" and S.weapons[c.key] == 1 and S.pickMode == "level")
	end

	-- 6. 글 · 수
	check("clockText", Sim.clockText(0) == "08:00" and Sim.clockText(540) == "09:00" and Sim.clockText(269.5) == "08:29")
	check("xpNeed", Sim.xpNeed(1) == 5 and Sim.xpNeed(2) == 8 and Sim.xpNeed(21) == 103)
	check("상수 순서 목록의 길이", #Sim.WEAPON_ORDER == 16 and #Sim.PASSIVE_ORDER == 16 and #Sim.FUSION_ORDER == 5 and #Sim.ENEMY_ORDER == 15 and #Sim.ZONES == 7 and #Sim.DIFFS == 4)
	for _, k in ipairs(Sim.WEAPON_ORDER) do
		if #Sim.WEAPONS[k].lv ~= 6 or Sim.PAIR_OF[Sim.WEAPONS[k].pair] ~= k then
			check("무기 " .. k .. " 의 lv 6개 · 짝", false)
		end
	end
	check("도움 함수: hypot(∞, 1) = ∞ · sign(0) = 0 · round(-0.4) = -0 · round(2.5) = 3 · round(-2.5) = -2", Sim.hypot(math.huge, 1) == math.huge and Sim.sign(0) == 0 and 1 / Sim.round(-0.4) == -math.huge and Sim.round(2.5) == 3 and Sim.round(-2.5) == -2)

	-- 7. 이상한 입력: 숫자가 아닌 난이도(→ 0), 상수에 없는 키(이름순으로 뒤에 붙는다)
	do
		local sim = Sim.create(mkHost({}), { rng = P.makeRng(5).next, diff = "abc" })
		check("숫자가 아닌 난이도는 0(여유)", sim.S.diff == 0)
		local S = sim.S
		S.weapons = { zzz = 1, card = 2, aaa = 3 }
		S.dmg = { card = 1 }
		sim.dbg.syncOrder()
		check("상수에 없는 키는 이름순으로 뒤에", join(S.wOrder) == "card,aaa,zzz" and join(S.dmgOrder) == "card", join(S.wOrder))
	end
end
