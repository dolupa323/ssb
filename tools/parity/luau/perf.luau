--!optimize 2
-- update 한 번에 걸리는 시간을 잰다 (적 300~450명). js/perf.cjs 와 같은 상황.
local P = require("./prng")
return function(Sim: any)
	local rng = P.makeRng(4242)
	local nop = function() end
	local host = { sfx = nop, banner = nop, shake = nop, levelUp = nop, finish = nop }
	local sim = Sim.create(host, {
		diff = 3, demo = true, rng = rng.next,
		build = { weapons = { card = 5, backpack = 4, anc = 4, coffee = 3, selfie = 3 }, passives = { shoes = 2, will = 2, pods = 2, tumbler = 2, badge = 2 } },
	})
	local S = sim.S
	S.admNoPick = true
	S.t = 400
	local view, dt = { w = 1280, h = 720 }, 1 / 60
	local function step()
		local b = sim.bot()
		S.input = b
		if b.dash then
			sim.dash()
		end
		if (S.phase == "crowd" or S.phase == "ride") and S.zt > 6 then
			S.zt = 6
		end
		sim.update(dt, view)
		table.clear(S.ev)
	end
	step()
	S.zone = 2
	sim.dbg.enterZone(2)
	S.admRate = 8
	-- 적이 찰 때까지 돌린다
	local warm = 0
	while #S.enemies < 380 and warm < 6000 do
		step()
		warm += 1
	end
	local N = 1500
	local tUpd, tBot, tMax, eSum, eMin, eMax = 0, 0, 0, 0, math.huge, 0
	for _ = 1, N do
		local c0 = os.clock()
		local b = sim.bot()
		local c1 = os.clock()
		S.input = b
		if b.dash then
			sim.dash()
		end
		if (S.phase == "crowd" or S.phase == "ride") and S.zt > 6 then
			S.zt = 6
		end
		local c2 = os.clock()
		sim.update(dt, view)
		local c3 = os.clock()
		table.clear(S.ev)
		tBot += c1 - c0
		tUpd += c3 - c2
		if c3 - c2 > tMax then
			tMax = c3 - c2
		end
		local n = #S.enemies
		eSum += n
		eMin = math.min(eMin, n)
		eMax = math.max(eMax, n)
	end
	print(string.format("PERF update 평균 %.3f ms (최대 %.3f ms) · bot %.3f ms · 적 평균 %.0f명 (최소 %d, 최대 %d) · %d번 · 준비 %d tick", tUpd / N * 1000, tMax * 1000, tBot / N * 1000, eSum / N, eMin, eMax, N, warm))
end
