--!strict
-- 게임 중 화면(원본 #hud): 경험치 줄 · 레벨 · 멘탈 · 전광판(시계 · 역 이름 · 경로) · 처치 수 · 설정/일시정지 · 보스 줄 · 무기/장비 칸 · 대시 단추 · 안내.
--  값 채우기는 원본 main.js의 updateHud() · slotEl() · tutorial()의 화면 부분.
local Sim = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Sim")) :: any
local T = require(script.Parent.Theme)
local Stage = require(script.Parent.Parent.Stage) :: any
local Art = require(script.Parent.Parent.Art) :: any
local Gfx = require(script.Parent.Parent.Gfx) :: any

local C = T.C
local Hud = {}
Hud.onPause = nil :: (() -> ())?
Hud.onSettings = nil :: (() -> ())?
Hud.onDash = nil :: (() -> ())?
Hud.onClick = nil :: (() -> ())? -- 단추 소리
Hud.lefty = false
Hud.topShift = 0 -- 폭이 좁아 Roblox 단추를 옆으로 피할 수 없을 때 윗줄을 내린 만큼(알림도 같이 내린다)

local SEGS = 60 -- 대시 단추 둘레의 조각 수
local BOSS_GRAD = {
	[""] = { { 0, T.hex("#d37af0") }, { 0.6, T.hex("#b03bd6") }, { 1, T.hex("#7b1fa0") } },
	wait = { { 0, T.hex("#ffe07a") }, { 0.6, T.hex("#ffb300") }, { 1, T.hex("#c98500") } },
	rage = { { 0, T.hex("#ff8a8e") }, { 0.6, T.hex("#e5484d") }, { 1, T.hex("#a82228") } },
}

local root: Frame? = nil
local shown = false
local modal = false
local E = {} :: { [string]: any } -- 만든 것들
local M = {} :: { [string]: any } -- 지금 배치의 치수
-- 원본의 last… (같은 값이면 다시 쓰지 않는다)
local last = {} :: { [string]: any }
local hintOn = false
local hintText = ""
local setXp: any, setHp: any, setBoss: any
local setHint: any
local nowDot: UIScale? = nil
local clockT = 0

local function metrics()
	local phone = Stage.phone
	M = {
		phone = phone,
		rowTop = if phone then 11 else 18,
		rowPad = if phone then 8 else 16,
		rowGap = if phone then 7 else 10,
		slot = if phone then 26 else 42,
		slotR = if phone then 6 else 8,
		slotB = if phone then 1.5 else 2,
		slotGap = if phone then 3 else 5,
		baseGap = if phone then 2 else 5,
		imgInset = if phone then 2 else 3,
		em = if phone then 13 else 17,
		emFs = if phone then 8.5 else 10,
		emOut = if phone then 3 else 4,
		emPad = if phone then 2 else 3,
		buildPad = if phone then 8 else 16,
		buildGap = if phone then 6 else 5,
		dash = if phone then 98 else 78,
		dashRight = if phone then 14 else 18,
		dashBottom = if phone then 72 else 18,
		dashFs = if phone then 21 else 18,
		bossTop = if phone then 50 else 84,
		bossFs = if phone then 14 else 18,
		bossH = if phone then 8 else 12,
		bossB = if phone then 1.5 else 2,
		bossGap = if phone then 1 else 2,
		hintBottom = if phone then 180 else 112,
		hintFs = if phone then 13 else 14,
		clockFs = if phone then 23 else 36,
		stnFs = if phone then 12.5 else 17,
		indent = 0,
	}
	-- Roblox 메뉴 단추(왼쪽 위 44px)를 피한다. 넓은 배치: 「레벨 N」 글만 단추 오른쪽으로(멘탈 줄은 y=49부터라 단추 아래 — 원본 자리 그대로).
	--  폰 배치(윗줄이 한 줄): 줄의 왼쪽 끝을 단추 오른쪽으로, 그럴 폭이 없으면 윗줄 · 보스 줄 · 알림을 그 띠 아래로 내린다
	Hud.topShift = 0
	if Stage.insetTop > M.rowTop then
		if phone and Stage.w - Stage.insetLeft < 440 then
			Hud.topShift = math.ceil(Stage.insetTop - 6)
			M.rowTop += Hud.topShift
			M.bossTop += Hud.topShift
		else
			M.indent = Stage.insetLeft + 8
		end
	end
end

-- ---------- 전광판(시계 · 역 이름 · 경로) ----------
local function layoutRow()
	local W = Stage.w
	local phone = M.phone
	local board = E.board :: Frame
	-- 전광판 안
	local clockW = T.bounds(E.clock)
	local nameW = T.bounds(E.stn)
	local x
	local rowH
	if phone then
		nameW = math.min(74, nameW + 2)
		rowH = 19
		x = 7
		E.clock.Position = UDim2.fromOffset(x, 3)
		E.clock.Size = UDim2.fromOffset(clockW, rowH)
		x += clockW + 6
		E.stn.Position = UDim2.fromOffset(x, 3)
		E.stn.Size = UDim2.fromOffset(nameW, rowH)
		x += nameW + 8
	else
		rowH = 28.8
		local labelW = T.bounds(E.stnLabel)
		local stnW = math.max(nameW, labelW)
		x = 8
		E.roundel.Position = UDim2.fromOffset(x, 6 + (rowH - 26) / 2)
		x += 26 + 10
		E.clock.Position = UDim2.fromOffset(x, 6)
		E.clock.Size = UDim2.fromOffset(clockW, rowH)
		x += clockW + 10
		E.stnLabel.Position = UDim2.fromOffset(x, 6.2)
		E.stnLabel.Size = UDim2.fromOffset(stnW, 10.5)
		E.stn.Position = UDim2.fromOffset(x, 6.2 + 10.5)
		E.stn.Size = UDim2.fromOffset(stnW, 17.8)
		x += stnW + 13
	end
	local b = if phone then 1.5 else 2
	local bw = x + 2 * b
	local bh = if phone then rowH + 6 + 2 * b else 6 + rowH + 5 + 9 + 7 + 2 * b
	local bx = math.floor((W - bw) / 2)
	-- 양옆(멘탈 · 처치 수)의 폭: 원본 flex 1 1 0 · max-width 250 (폰은 남는 폭 전부)
	local pad, gap = M.rowPad, M.rowGap
	local left = if phone then math.max(pad, M.indent) else pad
	local lvX = if phone then 0 else math.max(0, M.indent - pad) -- 넓은 배치: 「레벨 N」 글만 Roblox 단추 오른쪽으로 민다(멘탈 줄은 단추 아래라 제자리)
	local rowH2 = if phone then 30 else bh
	local by = if phone then M.rowTop + (rowH2 - bh) / 2 else M.rowTop
	board.Position = UDim2.fromOffset(bx + b, by + b)
	board.Size = UDim2.fromOffset(bw - 2 * b, bh - 2 * b)
	if E.boardShadow then
		E.boardShadow.Position = UDim2.fromOffset(bx, by + 3)
		E.boardShadow.Size = UDim2.fromOffset(bw, bh)
	end
	if E.mini then
		E.mini.Position = UDim2.fromOffset(8, 6 + rowH + 5)
		E.mini.Size = UDim2.fromOffset(bw - 2 * b - 8 - 13, 9)
		E.miniW = bw - 2 * b - 8 - 13
	end
	if phone then
		-- [Lv N][멘탈 줄 ……][전광판][일시정지]
		local side = 34
		local sideX = W - pad - side
		bx = sideX - gap - bw
		board.Position = UDim2.fromOffset(bx + b, by + b)
		local lvW = T.bounds(E.lv)
		local lvPre = T.bounds(E.lvLabel)
		E.lvLabel.Position = UDim2.fromOffset(left, M.rowTop + T.baseDown(19, 10))
		E.lvLabel.Size = UDim2.fromOffset(lvPre, 30)
		E.lv.Position = UDim2.fromOffset(left + lvPre + 2, M.rowTop)
		E.lv.Size = UDim2.fromOffset(lvW, 30)
		local hx = left + lvPre + 2 + lvW + 6
		local hw = math.max(40, bx - gap - hx)
		E.hpWrap.Position = UDim2.fromOffset(hx, M.rowTop + (30 - 15) / 2)
		E.hpWrap.Size = UDim2.fromOffset(hw, 15)
		E.btnPause.Position = UDim2.fromOffset(sideX + 1, M.rowTop + 1)
	else
		local avail = (W - 2 * pad - bw - 2 * gap) / 2
		local sideW = math.clamp(avail, 60, 250)
		local vw = math.min(sideW, bx - gap - left)
		E.vitals.Position = UDim2.fromOffset(left, M.rowTop)
		E.vitals.Size = UDim2.fromOffset(vw, 50)
		local lvPre = T.bounds(E.lvLabel)
		local lvW = T.bounds(E.lv)
		E.lvLabel.Position = UDim2.fromOffset(lvX, T.baseDown(24, 13))
		E.lvLabel.Size = UDim2.fromOffset(lvPre, 24)
		E.lv.Position = UDim2.fromOffset(lvX + lvPre + 8, 0)
		E.lv.Size = UDim2.fromOffset(lvW, 24)
		-- 오른쪽: 처치 수, 그 아래 단추 둘
		local right = W - pad
		local kW = T.bounds(E.kills)
		local kPre = T.bounds(E.killsLabel)
		E.kills.Position = UDim2.fromOffset(right - kW, M.rowTop)
		E.kills.Size = UDim2.fromOffset(kW, 30)
		E.killsLabel.Position = UDim2.fromOffset(right - kW - 5 - kPre, M.rowTop + T.baseDown(24, 13))
		E.killsLabel.Size = UDim2.fromOffset(kPre, 30)
		local pw = E.btnPause.Size.X.Offset + 2
		E.btnPause.Position = UDim2.fromOffset(right - pw + 1, M.rowTop + 36 + 1)
		local sw = E.btnSet.Size.X.Offset + 2
		E.btnSet.Position = UDim2.fromOffset(right - pw - 6 - sw + 1, M.rowTop + 36 + 1)
	end
end

local function buildMini(zone: number)
	local mini = E.mini :: Frame?
	if not mini then
		return
	end
	mini:ClearAllChildren()
	nowDot = nil
	local n = #Sim.ZONES
	local w = E.miniW or 100
	local seg = math.max(8, (w - 4 - n * 9) / (n - 1))
	local x = 2
	for i = 0, n - 1 do
		if i > 0 then
			T.box(mini, "u" .. i, { x = x, y = 3, w = seg, h = 3, bg = if i <= zone then C.line2 else T.hex("#3a4549") })
			x += seg
		end
		local isNow = i == zone
		local col = if i < zone then C.line2 elseif isNow then C.safety else T.hex("#3a4549")
		local d = T.box(mini, "i" .. i, { pos = UDim2.fromOffset(x + 4.5, 4.5), w = 9, h = 9, anchor = Vector2.new(0.5, 0.5), bg = col, r = 1000, b = 2, bc = if isNow then C.white else col, z = 2 })
		if isNow then
			local sc = Instance.new("UIScale")
			sc.Parent = d
			nowDot = sc
		end
		x += 9
	end
end

-- ---------- 무기 · 장비 칸 ----------
local function slotEl(parent: Frame, x: number, y: number, base: boolean, pv: boolean, key: string?, lvl: number?, max: number, evo: boolean)
	local s = M.slot
	local on = key ~= nil
	local border = if evo then T.hex("#ff8a3c") elseif on then (if pv then C.safety else C.line2) else C.white
	if base then
		-- .slot.base: 바깥에 노란 고리 2px
		T.box(parent, "ring", { x = x - 2, y = y - 2, w = s + 4, h = s + 4, bg = C.safety, r = M.slotR + 2 })
	elseif evo then
		-- .slot.evo: 주황 빛(번짐은 못 한다 → 옅은 고리)
		T.box(parent, "glow", { x = x - 3, y = y - 3, w = s + 6, h = s + 6, bg = T.hex("#ff8a3c"), a = 0.35, r = M.slotR + 3 })
	end
	local f = T.box(parent, "slot", {
		x = x,
		y = y,
		w = s,
		h = s,
		bg = if on then T.hex("#e9e5da") else C.dark,
		a = if on then 1 else 0.72,
		r = M.slotR,
		b = M.slotB,
		bc = border,
		ba = if on or evo then 1 else 0.14,
	})
	if key then
		local im = Instance.new("ImageLabel")
		im.Name = "icon"
		im.BackgroundTransparency = 1
		im.BorderSizePixel = 0
		local inset = M.imgInset - M.slotB
		im.Position = UDim2.fromOffset(inset, inset)
		im.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
		pcall(Art.set, im, Gfx.icon(key, evo))
		im.Parent = f
		local txt = if Sim.FUSIONS[key] then "◆" elseif evo then "★" elseif (lvl or 0) >= max then "M" else tostring(lvl)
		local em = T.label(parent, "em", { text = txt, fs = M.emFs, wt = 700, color = C.led, ax = "Center", z = 3 })
		local tw = T.bounds(em)
		local ew = math.max(M.em, tw + 2 * M.emPad + 2)
		local ex, ey = x + s - M.slotB + M.emOut - ew, y + s - M.slotB + M.emOut - M.em
		T.box(parent, "emBack", { x = ex, y = ey, w = ew, h = M.em, bg = C.edge, r = 9, b = 1, bc = C.white, ba = 0.25, z = 2 })
		em.Position = UDim2.fromOffset(ex, ey)
		em.Size = UDim2.fromOffset(ew, M.em)
	end
end

local function buildSlots(S: any)
	local build = E.build :: Frame
	build:ClearAllChildren()
	local s, gap = M.slot, M.slotGap
	local wk = {} :: { string }
	for _, k in ipairs(S.fOrder) do
		table.insert(wk, k)
	end
	for _, k in ipairs(S.wOrder) do
		table.insert(wk, k)
	end
	local pk = S.pOrder
	local function row(keys: { string }, x0: number, y: number, pv: boolean): number
		local x = x0
		local n = if pv then Sim.MAX_P else Sim.MAX_W
		for i = 1, n do
			local k = keys[i]
			local base = if pv then k == "shoes" else (k == "card" or k == "freepass")
			if pv then
				slotEl(build, x, y, base, true, k, if k then S.passives[k] else nil, Sim.PMAX, false)
			else
				local fus = k ~= nil and S.fus[k] ~= nil
				local lvl = if k == nil then nil elseif fus then Sim.EVO else S.weapons[k]
				local evo = k ~= nil and (fus or S.weapons[k] > Sim.WMAX)
				slotEl(build, x, y, base, false, k, lvl, Sim.WMAX, evo)
			end
			x += s + gap + (if base then M.baseGap else 0)
		end
		return x - gap
	end
	local H = Stage.h
	if M.phone then
		-- 폰: 한 줄로 나란히, 조금 흐리게(opacity .82)
		local y = H - M.buildPad - s
		local x = row(wk, M.buildPad, y, false)
		row(pk, x + M.buildGap, y, true)
		T.fader(build)(0.82)
	else
		local y2 = H - M.buildPad - s
		row(wk, M.buildPad, y2 - M.buildGap - s, false)
		row(pk, M.buildPad, y2, true)
	end
end

-- ---------- 만들기 ----------
function Hud.build()
	if root then
		root:Destroy()
	end
	metrics()
	table.clear(E)
	table.clear(last)
	local W = Stage.w
	local phone = M.phone
	local r = T.box(Stage.ui, "Hud", { size = UDim2.fromScale(1, 1), z = 5, visible = shown })
	root = r

	-- 경험치 줄 (#xpbar)
	local xp = T.box(r, "XpBar", { size = UDim2.new(1, 0, 0, 9), bg = C.dark, a = 0.7 })
	T.box(xp, "Edge", { pos = UDim2.fromOffset(0, 8), size = UDim2.new(1, 0, 0, 1), bg = C.edge })
	local xpFill = T.box(xp, "Fill", { size = UDim2.new(0, 0, 0, 8), grad = { rot = 90, { 0, C.line2 }, { 1, T.hex("#5df0a0") } } })
	setXp = T.transition(0.12, T.EASE.linear, function(v)
		xpFill.Size = UDim2.new(v, 0, 0, 8)
	end)

	-- 레벨 · 멘탈 (.vitals)
	local hpWrap
	if phone then
		E.lvLabel = T.label(r, "LvLabel", { text = "Lv", fs = 10, wt = 700, color = C.white, a = 0.85, shadow = 0.5 })
		E.lv = T.label(r, "Lv", { text = "1", fs = 19, font = "display", color = C.white, shadow = 0.5 })
		hpWrap = T.box(r, "Hp", { w = 100, h = 15 })
	else
		local v = T.box(r, "Vitals", { w = 250, h = 50 })
		E.vitals = v
		E.lvLabel = T.label(v, "LvLabel", { text = "레벨", fs = 13, wt = 700, color = C.white, shadow = 0.5 })
		E.lv = T.label(v, "Lv", { text = "1", fs = 24, font = "display", color = C.white, shadow = 0.5 })
		hpWrap = T.box(v, "Hp", { pos = UDim2.fromOffset(0, 30), size = UDim2.new(1, 0, 0, 20) })
		T.box(hpWrap, "Shadow", { pos = UDim2.fromOffset(0, 2), size = UDim2.fromScale(1, 1), bg = C.black, a = 0.3, r = 10 })
	end
	E.hpWrap = hpWrap
	local hb = if phone then 1.5 else 2
	local hp = T.box(hpWrap, "Bar", { size = UDim2.fromScale(1, 1), bg = C.dark, a = 0.8, r = if phone then 8 else 10, b = hb, bc = C.edge, clip = true })
	local hpFill = T.box(hp, "Fill", { size = UDim2.fromScale(1, 1), r = (if phone then 8 else 10) - hb, grad = { rot = 180, { 0, T.hex("#ff7a7e") }, { 0.55, C.danger }, { 1, T.hex("#b92f35") } } })
	setHp = T.transition(0.15, T.EASE.ease, function(v)
		hpFill.Size = UDim2.fromScale(v, 1)
		hpFill.Visible = v > 0.001
	end)
	E.hpTxt = T.label(hp, "Text", { text = "멘탈 100", fs = if phone then 9.5 else 11, wt = 700, color = C.white, ax = "Center", size = UDim2.fromScale(1, 1), z = 2, shadow = 0.45 })

	-- 전광판 (.board)
	if not phone then
		E.boardShadow = T.box(r, "BoardShadow", { w = 10, h = 10, bg = C.black, a = 0.35, r = 9 })
	end
	local board = T.box(r, "Board", { w = 10, h = 10, r = 9, b = if phone then 1.5 else 2, bc = C.edge, grad = { rot = 180, { 0, T.hex("#263033") }, { 1, T.hex("#161c1e") } } })
	E.board = board
	if not phone then
		local ro = T.box(board, "Roundel", { w = 26, h = 26, bg = C.line2, r = 1000 })
		T.label(ro, "N", { text = "2", fs = 18, font = "display", color = C.white, ax = "Center", size = UDim2.fromScale(1, 1) })
		E.roundel = ro
		E.stnLabel = T.label(board, "StnLabel", { text = "지금 여기", fs = 10, wt = 500, color = T.hex("#8e999c") })
		E.mini = T.box(board, "Mini", { w = 10, h = 9 })
	end
	E.clock = T.label(board, "Clock", { text = "08:00", fs = M.clockFs, font = "led", color = C.led, ls = 0.04 })
	E.stn = T.label(board, "Stn", { text = "역삼역 앞", fs = M.stnFs, font = "display", color = C.led, trunc = phone })

	-- 처치 수 · 단추 (.side)
	local function hudBtn(name: string, text: string): TextButton
		local b
		if phone then
			b = T.button(r, name, { w = 34, h = 30, bg = C.dark, a = 0.82, r = 6, b = 1, bc = C.white, ba = 0.12 })
			-- 일시정지 그림(세로 막대 둘)
			T.box(b, "L", { x = 10, y = 7, w = 4, h = 14, bg = C.paper })
			T.box(b, "R", { x = 18, y = 7, w = 4, h = 14, bg = C.paper })
		else
			b = T.button(r, name, { w = 10, h = 32, bg = C.dark, a = 0.82, r = 6, b = 1, bc = C.white, ba = 0.12 })
			local l = T.label(b, "T", { text = text, fs = 12, wt = 600, color = C.paper, ax = "Center", size = UDim2.fromScale(1, 1) })
			local tw = T.bounds(l)
			b.Size = UDim2.fromOffset(tw + 20, 30)
		end
		T.states(b, function(over)
			b.BackgroundColor3 = if over then C.black else C.dark
			b.BackgroundTransparency = if over then 0 else 0.18
		end)
		b.MouseButton1Click:Connect(function()
			if Hud.onClick then
				Hud.onClick()
			end
		end)
		return b
	end
	if not phone then
		E.killsLabel = T.label(r, "KillsLabel", { text = "밀어낸 인파", fs = 13, wt = 700, color = C.white, shadow = 0.5 })
		E.kills = T.label(r, "Kills", { text = "0", fs = 24, font = "display", color = C.white, ax = "Right", shadow = 0.5 })
		E.btnSet = hudBtn("BtnSet", "설정")
		E.btnSet.MouseButton1Click:Connect(function()
			if Hud.onSettings then
				Hud.onSettings()
			end
		end)
	end
	E.btnPause = hudBtn("BtnPause", "일시정지")
	E.btnPause.MouseButton1Click:Connect(function()
		if Hud.onPause then
			Hud.onPause()
		end
	end)

	-- 보스 줄 (#bossbar)
	local bw = if phone then W - 20 else math.min(460, W - 32)
	local lineBox = if phone then 25 else 27
	local barY = lineBox + M.bossGap
	local bb = T.box(r, "BossBar", { pos = UDim2.new(0.5, 0, 0, M.bossTop), w = bw, h = barY + M.bossH, anchor = Vector2.new(0.5, 0), visible = false })
	E.bossbar = bb
	E.bossName = T.label(bb, "Name", { text = "", fs = M.bossFs, font = "display", color = C.white, ax = "Center", pos = UDim2.fromOffset(0, 6), size = UDim2.new(1, 0, 0, M.bossFs), shadow = 0.7 })
	local track = T.box(bb, "Track", { pos = UDim2.fromOffset(0, barY), size = UDim2.new(1, 0, 0, M.bossH), bg = C.dark, a = 0.85, r = 7, b = M.bossB, bc = C.edge, clip = true })
	local bossFill = T.box(track, "Fill", { size = UDim2.fromScale(1, 1), bg = C.white, r = 7 - M.bossB })
	E.bossGrad = T.gradient(bossFill, { rot = 180, table.unpack(BOSS_GRAD[""]) })
	setBoss = T.transition(0.12, T.EASE.ease, function(v)
		bossFill.Size = UDim2.fromScale(v, 1)
		bossFill.Visible = v > 0.001
	end)

	-- 무기 · 장비 칸 (#build)
	E.build = T.box(r, "Build", { size = UDim2.fromScale(1, 1) })

	-- 대시 단추 (#btnDash)
	local ds = M.dash
	local lefty = phone and Hud.lefty
	local dash = T.button(r, "BtnDash", {
		pos = if lefty then UDim2.new(0, M.dashRight + ds / 2, 1, -M.dashBottom - ds / 2) else UDim2.new(1, -M.dashRight - ds / 2, 1, -M.dashBottom - ds / 2),
		w = ds,
		h = ds,
		anchor = Vector2.new(0.5, 0.5),
		r = 1000,
	})
	E.dash = dash
	local dashScale = Instance.new("UIScale")
	dashScale.Parent = dash
	local setDashScale = T.transition(0.08, T.EASE.ease, function(v)
		dashScale.Scale = v
	end)
	setDashScale(1, true)
	-- 둘레: 남은 대기 시간을 위에서부터 시계 방향으로 채운다(원본 conic-gradient)
	local segs = {}
	local rad = ds / 2 - 1.9
	local segLen = 2 * math.pi * rad / SEGS + 0.7
	for i = 0, SEGS - 1 do
		local a = (i + 0.5) / SEGS * 2 * math.pi
		local sgm = T.box(dash, "s", { pos = UDim2.new(0.5, math.sin(a) * rad, 0.5, -math.cos(a) * rad), w = segLen, h = 3.8, anchor = Vector2.new(0.5, 0.5), bg = C.white, a = 0.18 })
		sgm.Rotation = math.deg(a)
		segs[i + 1] = sgm
	end
	E.segs = segs
	local inner = T.box(dash, "In", { pos = UDim2.fromScale(0.5, 0.5), w = ds - 12 - 2, h = ds - 12 - 2, anchor = Vector2.new(0.5, 0.5), r = 1000, grad = { rot = 180, alpha = { { 0, 0.2 }, { 0.45, 0.07 }, { 1, 0.03 } } }, bg = C.white })
	T.stroke(inner, 1, C.white, 0.2)
	local small = not phone
	E.dashTxt = T.label(inner, "T", { text = "대시", fs = M.dashFs, font = "display", color = C.white, a = 0.6, ax = "Center", pos = UDim2.new(0, 0, 0.5, if small then -16 else -M.dashFs * 0.65), size = UDim2.new(1, 0, 0, if small then 20 else M.dashFs * 1.3), shadow = 0.3 })
	if small then
		T.label(inner, "Key", { text = "Space", fs = 9, wt = 600, color = C.white, a = 0.6, ax = "Center", pos = UDim2.new(0, 0, 0.5, 7), size = UDim2.new(1, 0, 0, 11) })
	end
	T.states(dash, nil, function(down)
		setDashScale(if down then 0.94 else 1)
	end)
	dash.MouseButton1Down:Connect(function()
		if Hud.onDash then
			Hud.onDash()
		end
	end)

	-- 안내 (#hint)
	local hint = T.box(r, "Hint", { pos = UDim2.new(0.5, 0, 1, -M.hintBottom), w = 100, h = 30, anchor = Vector2.new(0.5, 1), bg = T.rgb(14, 19, 21), a = 0.93, r = 10, b = 2, bc = C.safety, z = 6, visible = false })
	E.hint = hint
	local tagL = T.label(hint, "TagT", { text = "안내", fs = 14, font = "display", color = C.body, ax = "Center", z = 2 })
	local tagW = T.bounds(tagL) + 16
	local tagH = 14 * 1.4 + 6
	E.hintTag = T.box(hint, "Tag", { w = tagW, h = tagH, bg = C.safety, r = 6 })
	tagL.Size = UDim2.fromOffset(tagW, tagH)
	E.hintTagL = tagL
	E.hintTagW, E.hintTagH = tagW, tagH
	E.hintTxt = T.label(hint, "Text", { text = "", fs = M.hintFs, wt = 600, color = C.white, lh = 1.4 })
	E.hintFade = nil
	setHint = T.transition(0.25, T.EASE.ease, function(v)
		hint.Visible = v > 0.001
		if E.hintFade then
			E.hintFade(v)
		end
		hint.Position = UDim2.new(0.5, 0, 1, -M.hintBottom + 12 * (1 - v))
	end)
	setHint(0, true)

	layoutRow()
	if hintOn then
		Hud.hint(hintText, true)
	end
end

function Hud.show(v: boolean)
	shown = v
	if root then
		root.Visible = v
	end
end

function Hud.isShown(): boolean
	return shown
end

-- 원본 startGame의 lastBuild = -1 … (다음 update에서 모두 다시 쓴다)
function Hud.reset()
	table.clear(last)
	if E.bossbar then
		E.bossbar.Visible = false
	end
end

-- 안내 한 줄(원본 #hint.on). instant = 움직임 없이
function Hud.hint(text: string?, instant: boolean?)
	if not text then
		hintOn = false
		if setHint then
			setHint(0, instant)
		end
		return
	end
	hintOn, hintText = true, text
	local hint = E.hint :: Frame
	hint.Visible = true -- (글의 폭을 재기 전에 보이게 해 둔다)
	local padL, padR = if M.phone then 7 else 8, if M.phone then 12 else 14
	local padY = if M.phone then 6 else 8
	local maxW = math.min(520, Stage.w - 28) - 4 -- 테두리 2px씩
	local tagW, tagH = E.hintTagW, E.hintTagH
	local txt = E.hintTxt :: TextLabel
	local availW = maxW - padL - tagW - 10 - padR
	local lines = T.wrap(txt, text, availW)
	txt.Size = UDim2.fromOffset(availW, 400)
	local tw = math.min((T.bounds(txt)), availW)
	local th = lines * M.hintFs * 1.4
	local innerH = math.max(th, tagH) + 2 * padY
	local innerW = padL + tagW + 10 + tw + padR
	hint.Size = UDim2.fromOffset(innerW, innerH)
	E.hintTag.Position = UDim2.fromOffset(padL, (innerH - tagH) / 2)
	E.hintTagL.Position = UDim2.fromOffset(padL, (innerH - tagH) / 2)
	txt.Position = UDim2.fromOffset(padL + tagW + 10, (innerH - th) / 2)
	txt.Size = UDim2.fromOffset(tw + 1, th)
	if E.hintFade then
		E.hintFade(1)
	end
	E.hintFade = T.fader(hint)
	setHint(if modal then 0 else 1, instant)
end

function Hud.hintShown(): boolean
	return hintOn
end

-- 원본 #app.modal: 창이 떠 있는 동안 안내를 숨긴다
function Hud.setModal(v: boolean)
	if modal == v then
		return
	end
	modal = v
	if hintOn and setHint then
		setHint(if v then 0 else 1)
	end
end

local function mmss(v: number): string
	v = math.max(0, math.ceil(v))
	local s = v % 60
	return math.floor(v / 60) .. ":" .. (if s < 10 then "0" else "") .. s
end

-- 원본 updateHud()
function Hud.update(S: any)
	local p = S.p
	local hpKey = math.ceil(p.hp) .. "/" .. p.maxhp
	if hpKey ~= last.hp then
		local first = last.hp == nil
		last.hp = hpKey
		setHp(math.clamp(p.hp / p.maxhp, 0, 1), first)
		E.hpTxt.Text = "멘탈 " .. math.ceil(p.hp) .. " / " .. p.maxhp
	end
	local xp = math.min(1, p.xp / Sim.xpNeed(p.level))
	setXp(xp, last.xp == nil)
	last.xp = xp
	local relayout = false
	if p.level ~= last.lv then
		last.lv = p.level
		E.lv.Text = tostring(p.level)
		relayout = true
	end
	if S.kills ~= last.kills then
		last.kills = S.kills
		if E.kills then
			E.kills.Text = T.num(S.kills)
			relayout = true
		end
	end
	local c = Sim.clockText(S.t)
	if c ~= last.clock then
		last.clock = c
		E.clock.Text = c
		local late = S.t > Sim.GAME_LEN
		E.clock.TextColor3 = if late then T.hex("#ff5a5f") else C.led
		local st = E.clock:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = E.clock.TextColor3
		end
		relayout = true
	end
	local inT = S.zk == "train"
	local nm: string
	if inT then
		if S.doorT > 0 and S.stopIdx > 0 then
			nm = Sim.STOPS[S.stopIdx].name
		elseif S.stopIdx < #Sim.STOPS then
			nm = Sim.STOPS[S.stopIdx + 1].name
		else
			nm = Sim.LAST_STOP
		end
	else
		nm = Sim.ZONES[S.zone + 1].short
	end
	local head = if inT then (if S.doorT > 0 then "이번 역" else "다음 역") else "지금 여기"
	local key = head .. "|" .. nm
	if key ~= last.stn then
		last.stn = key
		if E.stnLabel then
			E.stnLabel.Text = head
		end
		E.stn.Text = nm
		relayout = true
	end
	if relayout then
		layoutRow()
		last.zone = nil -- 전광판의 폭이 바뀌었으면 경로 줄도 다시
	end
	if S.zone ~= last.zone then
		last.zone = S.zone
		buildMini(S.zone)
	end
	-- 보스 줄: 문지기 보스 / 역에 서 있는 동안 / 열차를 타는 동안
	local bb = E.bossbar :: Frame
	local G = Sim.GATE[Sim.ZONES[S.zone + 1].key]
	local bl, bw, bc = "", 0, ""
	local bossAlive = S.boss ~= nil and not S.boss.dead
	if S.gate and not S.gate.dead then
		local label = S.gate.label
		if label == nil or label == "" then
			label = S.gate.def.name
		end
		bl = label .. (if S.rage > 0 then " · 폭주 " .. S.rage .. "단계" else " · 폭주까지 " .. mmss(S.rageT))
		bw = S.gate.hp / S.gate.maxhp
		bc = if S.rage > 0 then "rage" else ""
	elseif S.phase == "ride" and S.doorT > 0 and S.stopIdx > 0 and not bossAlive then
		bl = Sim.STOPS[S.stopIdx].name .. "역 정차 · 문 닫힘까지 " .. mmss(S.doorT)
		bw = S.doorT / Sim.DOOR_OPEN
		bc = "rage"
	elseif S.phase == "ride" then
		bl = (if bossAlive then S.boss.def.name .. " · " else "") .. Sim.LAST_STOP .. " 도착까지 " .. mmss(G.ride - S.zt)
		bw = if bossAlive then S.boss.hp / S.boss.maxhp else S.zt / G.ride
		bc = if bossAlive then "" else "wait"
	end
	if bl ~= "" then
		local was = bb.Visible
		bb.Visible = true
		if bl ~= last.boss then
			last.boss = bl
			E.bossName.Text = bl
		end
		if bc ~= last.bossClass then
			last.bossClass = bc
			local keys = {}
			for _, k in ipairs(BOSS_GRAD[bc]) do
				table.insert(keys, ColorSequenceKeypoint.new(k[1], k[2]))
			end
			E.bossGrad.Color = ColorSequence.new(keys)
			E.bossName.TextColor3 = if bc == "rage" then T.hex("#ffd0d2") else C.white
		end
		setBoss(math.clamp(bw, 0, 1), not was)
	else
		bb.Visible = false
	end
	-- 대시 단추
	local rd = p.dashCd <= 0
	local cd = if rd then 1 else 1 - p.dashCd / S.M.dashCd
	local lit = math.clamp(math.floor(cd * SEGS + 0.5), 0, SEGS)
	if lit ~= last.lit then
		last.lit = lit
		for i, sgm in ipairs(E.segs) do
			sgm.BackgroundTransparency = if i <= lit then 0.1 else 0.82
		end
	end
	if rd ~= last.ready then
		last.ready = rd
		T.setAlpha(E.dashTxt, if rd then 1 else 0.6)
	end
	if S.buildVer ~= last.build then
		last.build = S.buildVer
		buildSlots(S)
	end
end

-- 매 장면: 경로의 「지금」 점이 숨 쉬듯 커졌다 작아진다(원본 @keyframes now: 1초에 1 → 1.35, 오가며)
function Hud.frame(dt: number)
	clockT += dt
	local d = nowDot
	if d and shown then
		local ph = clockT % 2
		local x = if ph < 1 then ph else 2 - ph
		d.Scale = 1 + 0.35 * T.EASE.easeInOut(x)
	end
end

-- 시나리오 · 다른 화면이 쓰는 것
function Hud.elements(): { [string]: any }
	return E
end

return Hud
