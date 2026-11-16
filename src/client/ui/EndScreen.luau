--!strict
-- 결과(원본 #end): 도장이 찍힌 출근 기록부 — 제목 · 도장 · 지나온 경로 · 숫자 넷 · 무기별 피해 막대 · 단추 둘.
--  원본 main.js의 showEnd()의 화면 부분.
local Sim = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Sim")) :: any
local T = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Stage = require(script.Parent.Parent.Stage) :: any

local C = T.C
local EndScreen = {}
EndScreen.onRetry = nil :: (() -> ())?
EndScreen.onHome = nil :: (() -> ())?
EndScreen.E = {} :: { [string]: any }

local ROUTE = { "역 앞", "개찰구", "승강장", "열차 안", "승강장", "에스컬", "회사 앞" }

export type Info = {
	won: boolean,
	late: boolean,
	diff: number,
	zone: number,
	clock: string,
	kills: number,
	level: number,
	taken: number,
	rows: { { name: string, v: number, train: boolean } },
}

local ov: W.Overlay? = nil
local cur: Info? = nil

-- 판의 상태에서 결과 화면에 쓸 것만 뽑는다
function EndScreen.info(S: any, won: boolean): Info
	local rows = {}
	for i, k in ipairs(S.dmgOrder) do
		local v = S.dmg[k]
		if v ~= nil then
			local name: string
			if k == "train" then
				name = "열차"
			elseif Sim.FUSIONS[k] then
				name = Sim.FUSIONS[k].name
			elseif not Sim.WEAPONS[k] then
				name = k
			elseif (S.weapons[k] or 0) > Sim.WMAX or S.fsrc[k] then
				name = Sim.WEAPONS[k].evoName
			else
				name = Sim.WEAPONS[k].name
			end
			table.insert(rows, { name = name, v = v, train = k == "train", i = i })
		end
	end
	table.sort(rows, function(a: any, b: any)
		if a.v ~= b.v then
			return a.v > b.v
		end
		return a.i < b.i
	end)
	return {
		won = won,
		late = won and S.t > Sim.GAME_LEN,
		diff = S.diff,
		zone = S.zone,
		clock = Sim.clockText(S.t),
		kills = S.kills,
		level = S.p.level,
		taken = S.taken,
		rows = rows :: any,
	}
end

local function render(info: Info, again: boolean?)
	local o: W.Overlay = ov or W.overlay("End", 25, T.rgb(12, 16, 18), 0.74)
	ov = o
	o.root.Visible = true -- (글의 폭을 재기 전에 보이게 해 둔다)
	o.scroll:ClearAllChildren()
	o.scroll.CanvasPosition = Vector2.zero
	table.clear(EndScreen.E)
	local E = EndScreen.E
	local sw = Stage.w
	local phone = Stage.phone
	local pw = math.min(820, sw - 32)
	local panel = T.box(o.scroll, "Panel", { w = pw, h = 100 })
	local slip = T.box(panel, "Slip", { w = pw, h = 100, bg = C.paper, r = 12, clip = true })
	local won, late = info.won, info.late

	-- 머리(.slip-top): 「출근 기록부」 + 난이도 딱지
	local topH = 39
	local top = T.box(slip, "Top", { w = pw, h = topH, bg = C.ink, r = 12 })
	T.box(top, "Sq", { pos = UDim2.fromOffset(0, topH / 2), size = UDim2.new(1, 0, 0.5, 0), bg = C.ink })
	T.label(top, "T", { text = "출근 기록부", fs = 16, font = "display", color = C.white, x = 18, y = 0, w = 200, h = topH, z = 2 })
	local chipL = T.label(top, "ChipT", { text = "혼잡도 " .. Sim.DIFFS[info.diff + 1].name, fs = 12.5, wt = 700, color = C.body, ax = "Center", z = 3 })
	chipL.Size = UDim2.fromOffset(400, 20)
	local chipW = T.bounds(chipL) + 20
	T.box(top, "Chip", { x = pw - 18 - chipW, y = (topH - 23) / 2, w = chipW, h = 23, bg = T.DIFF_COLOR[info.diff + 1], r = 1000, z = 2 })
	chipL.Position = UDim2.fromOffset(pw - 18 - chipW, (topH - 23) / 2)
	chipL.Size = UDim2.fromOffset(chipW, 23)
	E.chip = chipL
	local y = topH + 12

	-- 제목(h2) + 작은 글
	local fs = math.clamp(0.064 * sw, 26, 40)
	local padR = if phone then 112 else 150
	local title, th = T.para(slip, "Title", {
		text = if won then info.clock .. (if late then " 지각 출근" else " 정시 출근") else "멘탈이 무너졌습니다",
		fs = fs,
		font = "display",
		color = C.ink,
		lh = 1.1,
		x = 18,
		y = y + 4,
		w = pw - 18 - padR,
	})
	E.title = title
	local small, sh = T.para(slip, "Small", {
		text = if won
			then (if late then "도착은 했습니다. 팀장님 눈을 피해 자리에 앉습니다" else "사원증을 찍었습니다. 이제 진짜 하루가 시작됩니다")
			else Sim.ZONES[info.zone + 1].name .. "에서 멈췄습니다. 오늘은 반차를 씁니다",
		fs = 13,
		wt = 500,
		color = C.muted,
		lh = 1.1,
		x = 18,
		y = y + 4 + th + 6,
		w = pw - 18 - padR,
	})
	E.small = small
	y += math.max(if phone then 92 else 118, 4 + th + 6 + sh) + 12

	-- 도장(.stamp): 두 겹 테두리의 동그라미, 13도 기울어 있다. 0.25초 뒤 크게 나타나 찍힌다
	local ss = if phone then 92 else 118
	local sc = if won then (if late then T.hex("#d06a10") else T.hex("#008a3f")) else T.hex("#d23338")
	local stamp = T.box(slip, "Stamp", { pos = UDim2.fromOffset(pw - (if phone then 10 else 16) - ss / 2, (if phone then 44 else 48) + ss / 2), w = ss, h = ss, anchor = Vector2.new(0.5, 0.5), z = 5 })
	stamp.Rotation = -13
	T.box(stamp, "Ring1", { size = UDim2.fromScale(1, 1), r = 1000, b = 1.7, bc = sc })
	T.box(stamp, "Ring2", { pos = UDim2.fromOffset(3.3, 3.3), size = UDim2.new(1, -6.6, 1, -6.6), r = 1000, b = 1.7, bc = sc })
	local stFs = if phone then 20 else 25
	local smFs = if phone then 15 else 19
	-- (한 줄로: 원본 글꼴에서는 「정시 출근」이 동그라미 안에 한 줄로 들어간다)
	local stH = math.ceil(stFs * 1.2)
	local st = T.label(stamp, "T", { text = if won then (if late then "지각" else "정시 출근") else "반차", fs = stFs, font = "display", color = sc, ax = "Center" })
	st.Size = UDim2.fromOffset(600, stH)
	local stW = T.bounds(st)
	if stW > ss - 12 then
		T.setFs(st, stFs * (ss - 12) / stW) -- (테두리를 넘지 않게)
	end
	local smH = math.ceil(smFs * 1.05)
	-- 원본은 display:grid — 글과 시각이 동그라미 안을 위아래 반씩 나눠 각자 가운데에 놓인다
	local half = (ss - 10) / 2
	st.Position = UDim2.fromOffset(5, 5 + (half - stH) / 2)
	st.Size = UDim2.fromOffset(ss - 10, stH)
	E.stampText = st
	E.stampClock = T.label(stamp, "Clock", { text = info.clock, fs = smFs, font = "led", color = sc, ax = "Center", ls = 0.04, x = 0, y = 5 + half + (half - smH) / 2, w = ss, h = smH })
	E.stamp = stamp
	local stScale = Instance.new("UIScale")
	stScale.Parent = stamp
	local stFade = T.fader(stamp)
	if again then
		stFade(0.92)
	else
		T.animate(0.35, T.bezier(0.2, 1.6, 0.4, 1), function(x)
			stScale.Scale = 2.2 + (1 - 2.2) * x
			stFade(0.92 * math.clamp(x, 0, 1))
		end, 0.25)
	end

	-- 경로(.eroute): 지나온 곳은 초록, 멈춘 곳은 빨강
	local n = #ROUTE
	local colW = (pw - 20) / n
	T.box(slip, "RouteLine", { x = 10 + colW / 2, y = y + 6, w = colW * (n - 1), h = 4, bg = T.hex("#d6d2c7"), r = 2 })
	E.route = {}
	for i, name in ipairs(ROUTE) do
		local done = won or (i - 1) < info.zone
		local stop = not done and (i - 1) == info.zone
		local col = if done then C.line2 elseif stop then C.danger else nil
		local cx = 10 + colW * (i - 0.5)
		-- 점: 안 16px + 테두리 3px = 22px (원본의 ::before는 content-box)
		T.box(slip, "RouteDot" .. i, { x = cx - 11, y = y, w = 22, h = 22, bg = col or C.white, r = 1000, b = 3, bc = col or T.hex("#c3bfb4"), z = 2 })
		local l = T.label(slip, "RouteName" .. i, { text = name, fs = 10.5, wt = 600, color = if done then C.ink elseif stop then C.danger else C.muted, ax = "Center", x = cx - colW / 2, y = y + 26, w = colW, h = 15 })
		l:SetAttribute("State", if done then "done" elseif stop then "stop" else "")
		E.route[i] = l
	end
	y += 22 + 4 + 15 + 12

	-- 숫자 넷(.stat-row): 시각 · 밀어낸 인파 · 레벨 · 받은 피해
	local stats = {
		{ "시각", info.clock, true },
		{ "밀어낸 인파", T.num(info.kills), false },
		{ "레벨", tostring(info.level), false },
		{ "받은 피해", T.num(math.floor(info.taken + 0.5)), false },
	} :: { { any } }
	local cols = if phone then 2 else 4
	local cellW = (pw - 36 - 8 * (cols - 1)) / cols
	local cellH = 2 + 7 + 17 + 2 + 34
	E.stats = {}
	for i, s in ipairs(stats) do
		local cxi, ryi = (i - 1) % cols, math.floor((i - 1) / cols)
		local x0, y0 = 18 + cxi * (cellW + 8), y + ryi * (cellH + 8)
		T.box(slip, "StatLine" .. i, { x = x0, y = y0, w = cellW, h = 2, bg = C.ink })
		T.label(slip, "StatName" .. i, { text = s[1], fs = 11, wt = 700, color = C.muted, ax = "Center", x = x0, y = y0 + 9, w = cellW, h = 17 })
		E.stats[i] = T.label(slip, "StatValue" .. i, {
			text = s[2],
			fs = if s[3] then 38 else 27,
			font = if s[3] then "led" else "display",
			color = C.ink,
			ax = "Center",
			x = x0,
			y = y0 + 9 + 17 + 2,
			w = cellW,
			h = if s[3] then 32.5 else 34,
		})
	end
	y += math.ceil(#stats / cols) * (cellH + 8) - 8 + 12

	-- 무기별 피해(.dmg): 이름 · 막대 · 값
	local nameW, valW = if phone then 96 else 118, if phone then 56 else 70
	local barW = pw - 36 - nameW - valW - 16
	local mx = if #info.rows > 0 then info.rows[1].v else 1
	E.dmg = {}
	for i, row in ipairs(info.rows) do
		local ry = y + (i - 1) * (19 + 5)
		local nl = T.label(slip, "DmgName" .. i, { text = row.name, fs = 12.5, color = C.ink, x = 18, y = ry, w = nameW, h = 19, trunc = true })
		local pct = math.max(2, row.v / mx * 100)
		local bar = T.box(slip, "DmgBar" .. i, { x = 18 + nameW + 8, y = ry + 5.5, w = barW * pct / 100, h = 8, bg = if row.train then T.hex("#8b9599") else C.line2, r = 4 })
		local vl = T.label(slip, "DmgValue" .. i, { text = T.num(math.floor(row.v + 0.5)), fs = 12.5, wt = 600, color = C.ink, ax = "Right", x = pw - 18 - valW, y = ry, w = valW, h = 19 })
		E.dmg[i] = { name = nl, bar = bar, value = vl, pct = pct }
	end
	if #info.rows > 0 then
		y += #info.rows * (19 + 5) - 5
	else
		y -= 12
	end
	y += 16
	slip.Size = UDim2.fromOffset(pw, y)
	T.box(panel, "SlipShadow", { x = 0, y = 4, w = pw, h = y, bg = C.black, a = 0.25, r = 12, z = 0 })
	slip.ZIndex = 2

	-- 단추(.btnrow)
	y += 14
	local function goW(text: string, fsz: number, padX: number): number
		local l = T.label(panel, "m", { text = text, fs = fsz, font = "display" })
		l.Size = UDim2.fromOffset(900, 30)
		local tw = T.bounds(l)
		l:Destroy()
		return math.max(200, tw + 2 * padX + 4)
	end
	local w1, w2 = goW("다시 출근하기", 24, 20), goW("처음 화면으로", 18, 16)
	local bh = 61
	if w1 + 10 + w2 <= pw then
		local x0 = (pw - (w1 + 10 + w2)) / 2
		E.retry = W.go(panel, "BtnRetry", { text = "다시 출근하기", x = x0, y = y, w = w1, h = bh })
		E.home = W.go(panel, "BtnHome", { text = "처음 화면으로", x = x0 + w1 + 10, y = y, w = w2, h = bh, sub = true })
		y += bh
	else
		E.retry = W.go(panel, "BtnRetry", { text = "다시 출근하기", x = (pw - w1) / 2, y = y, w = w1, h = bh })
		E.home = W.go(panel, "BtnHome", { text = "처음 화면으로", x = (pw - w2) / 2, y = y + bh + 10, w = w2, h = 45, sub = true })
		y += bh + 10 + 45
	end
	E.retry.MouseButton1Click:Connect(function()
		if EndScreen.onRetry then
			EndScreen.onRetry()
		end
	end)
	E.home.MouseButton1Click:Connect(function()
		if EndScreen.onHome then
			EndScreen.onHome()
		end
	end)
	panel.Size = UDim2.fromOffset(pw, y)
	o.place(panel, pw, y)
end

function EndScreen.show(info: Info)
	cur = info
	render(info, false)
	if ov then
		ov.root.Visible = true
	end
end

function EndScreen.hide()
	if ov then
		ov.root.Visible = false
	end
end

function EndScreen.isShown(): boolean
	return ov ~= nil and ov.root.Visible
end

function EndScreen.build()
	local was = EndScreen.isShown()
	if ov then
		ov.root:Destroy()
		ov = nil
	end
	local c = cur
	if was and c then
		render(c, true)
		if ov then
			(ov :: W.Overlay).root.Visible = true
		end
	end
end

return EndScreen
