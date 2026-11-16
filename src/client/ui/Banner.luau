--!strict
-- 큰 알림(원본 #banner): 위쪽 줄 아래에 뜨는 얇은 카드. 꼬리표(안내 · 주의 · 보상 · 등장 …) + 제목 + 설명 + 남은 시간 줄.
local T = require(script.Parent.Theme)
local Stage = require(script.Parent.Parent.Stage) :: any

local C = T.C
local Banner = {}
Banner.topShift = 0 -- 폰 배치에서 Roblox 단추 때문에 윗줄을 내린 만큼(Hud.topShift)

-- 원본 host.banner의 꼬리표 글
local TAG = { station = "안내", warn = "주의", good = "보상", boss = "등장", heal = "회복", pass = "통과" }

local root: Frame? = nil
local fade: ((number) -> ())? = nil
local on = false
local modal = false
local kind: string? = nil
local tagFrame: Frame? = nil
local stopLine: (() -> ())? = nil
local cur: { a: string, b: string?, kind: string? }? = nil
local pulseT = 0
local lineStart, lineDur = 0, 2.6
local setOp: (number, boolean?) -> ()
local setTf: (number, boolean?) -> ()

local function top(): number
	return (if Stage.phone then 96 else 128) + Banner.topShift
end

function Banner.build()
	if root then
		root:Destroy()
	end
	local r = T.box(Stage.ui, "Banner", { pos = UDim2.new(0.5, 0, 0, top()), w = 100, h = 40, anchor = Vector2.new(0.5, 0), z = 7, visible = false })
	root = r
	local sc = Instance.new("UIScale")
	sc.Parent = r
	fade = nil
	-- opacity .18s · transform .22s cubic-bezier(.2,1.4,.4,1)
	setOp = T.transition(0.18, T.EASE.ease, function(v)
		r.Visible = v > 0.001
		if fade then
			fade(v)
		end
	end)
	setTf = T.transition(0.22, T.bezier(0.2, 1.4, 0.4, 1), function(v)
		r.Position = UDim2.new(0.5, 0, 0, top() - 10 * (1 - v))
		sc.Scale = 0.96 + 0.04 * v
	end)
	setOp(0, true)
	setTf(0, true)
	local c = cur
	if on and c then
		Banner.show(c.a, c.b, c.kind, true)
	end
end

-- 원본 host.banner(a, b, kind)의 화면 부분. again = 화면 크기가 바뀌어 다시 그리는 것(남은 시간 줄은 다시 달리지 않는다)
function Banner.show(a: string, b: string?, k: string?, again: boolean?)
	local r = root :: Frame
	cur = { a = a, b = b, kind = k }
	kind = k
	on = true
	r.Visible = true -- (글의 폭을 재기 전에 보이게 해 둔다)
	if not again then
		lineStart, lineDur = os.clock(), if k == "boss" then 3.2 else 2.6
	end
	if fade then
		fade(1)
	end
	for _, ch in r:GetChildren() do
		if not ch:IsA("UIScale") then
			ch:Destroy()
		end
	end
	if stopLine then
		stopLine()
		stopLine = nil
	end
	local phone = Stage.phone
	local boss = k == "boss"
	local kc = if k == "warn" then C.danger elseif k == "good" then C.safety elseif boss then C.boss else C.line2
	local kt = if k == "good" then C.body else C.white
	local b1Fs = if boss then (if phone then 20 else 23) else (if phone then 17 else 20)
	local b2Fs = if phone then 12 else 12.5
	local maxW = Stage.w - 24 - 3 -- 테두리 1.5px씩

	-- 꼬리표(.b0)
	local tagL = T.label(r, "TagT", { text = TAG[k or ""] or "안내", fs = if phone then 13 else 14, font = "display", color = kt, ax = "Center", z = 3 })
	tagL.Size = UDim2.fromOffset(400, 20)
	local tagW = math.max(if phone then 42 else 48, T.bounds(tagL) + 2 * (if phone then 9 else 11))

	-- 제목(.b1) · 설명(.b2)
	local l1 = T.label(r, "B1", { text = a, fs = b1Fs, font = "display", color = if boss then T.hex("#f3d2ff") else C.white, z = 3 })
	l1.Size = UDim2.fromOffset(2000, 30)
	local w1 = T.bounds(l1)
	local h1 = b1Fs * 1.15
	local has2 = b ~= nil and b ~= ""
	local l2: TextLabel? = nil
	local w2, h2 = 0, 0
	local padL, padR = if phone then 10 else 12, if phone then 12 else 15
	local padT, padB = if phone then 5 else 6, 8
	local innerW, innerH
	if phone then
		-- 세로로: 제목 아래에 설명 (gap 1)
		local avail = maxW - tagW - padL - padR
		if has2 then
			local l = T.label(r, "B2", { text = b, fs = b2Fs, wt = 600, color = T.hex("#c3cbce"), lh = 1.3, z = 3 })
			local lines = T.wrap(l, b :: string, avail)
			l.Size = UDim2.fromOffset(avail, 400)
			w2 = math.min((T.bounds(l)), avail)
			h2 = lines * b2Fs * 1.3
			l2 = l
		end
		w1 = math.min(w1, avail)
		innerW = tagW + padL + math.max(w1, w2) + padR
		innerH = padT + h1 + (if has2 then 1 + h2 else 0) + padB
		l1.Position = UDim2.fromOffset(tagW + padL, padT)
		l1.Size = UDim2.fromOffset(w1 + 1, h1)
		if l2 then
			l2.Position = UDim2.fromOffset(tagW + padL, padT + h1 + 1)
			l2.Size = UDim2.fromOffset(w2 + 1, h2)
		end
	else
		-- 가로로: 제목 옆에 설명 (gap 10 · 밑줄 맞춤). 넘치면 설명이 줄을 바꾼다
		local avail = maxW - tagW - padL - padR - w1 - 10
		if has2 then
			local l = T.label(r, "B2", { text = b, fs = b2Fs, wt = 600, color = T.hex("#c3cbce"), lh = 1.3, z = 3 })
			local lines = T.wrap(l, b :: string, math.max(60, avail))
			l.Size = UDim2.fromOffset(math.max(60, avail), 400)
			w2 = math.min((T.bounds(l)), math.max(60, avail))
			h2 = lines * b2Fs * 1.3
			l2 = l
		end
		innerW = tagW + padL + w1 + (if has2 then 10 + w2 else 0) + padR
		innerH = padT + math.max(h1, h2) + padB
		l1.Position = UDim2.fromOffset(tagW + padL, padT)
		l1.Size = UDim2.fromOffset(w1 + 1, h1)
		if l2 then
			-- 첫 줄의 밑줄을 제목의 밑줄에 맞춘다
			local lineH = b2Fs * 1.3
			l2.Position = UDim2.fromOffset(tagW + padL + w1 + 10, padT + 5 + (b1Fs - 20) * 0.5)
			local _ = lineH
			l2.Size = UDim2.fromOffset(w2 + 1, h2)
		end
	end
	r.Size = UDim2.fromOffset(innerW + 3, innerH + 3)

	-- 바탕 · 테두리 (보스는 보라 테두리 + 바깥 고리)
	if boss then
		T.box(r, "Glow", { x = -3, y = -3, w = innerW + 9, h = innerH + 9, bg = C.boss, a = 0.25, r = 13 })
	end
	local card = T.box(r, "Card", { w = innerW + 3, h = innerH + 3, bg = T.rgb(16, 21, 24), a = 0.9, r = 10, b = 1.5, bc = if boss then T.rgb(214, 130, 245) else C.white, ba = if boss then 0.7 else 0.16, clip = true, z = 2 })
	-- 꼬리표 바탕: 왼쪽만 둥글다 → 둥근 네모 + 오른쪽 절반을 덮는 네모
	local tg = T.box(card, "Tag", { w = tagW, h = innerH, bg = kc, r = 8.5 })
	T.box(tg, "Sq", { pos = UDim2.fromOffset(tagW / 2, 0), w = tagW / 2, h = innerH, bg = kc })
	tagFrame = tg
	tagL.Position = UDim2.fromOffset(1.5, 1.5)
	tagL.Size = UDim2.fromOffset(tagW, innerH)
	for _, l in { l1, l2 :: any } do
		if l then
			l.Position = l.Position + UDim2.fromOffset(1.5, 1.5)
		end
	end
	-- 남은 시간 줄(::after): 왼쪽에서부터 줄어든다
	local line = T.box(card, "Time", { pos = UDim2.new(0, 0, 1, -2.5), size = UDim2.new(1, 0, 0, 2.5), bg = kc, z = 3 })
	do
		-- (다시 그릴 때는 남은 만큼만 이어서 줄어든다)
		local f0 = math.clamp((os.clock() - lineStart) / lineDur, 0, 1)
		stopLine = T.animate(lineDur * (1 - f0), T.EASE.linear, function(x)
			line.Size = UDim2.new((1 - f0) * (1 - x), 0, 0, 2.5)
		end)
	end
	-- (설명 글의 진짜 폭이 잰 것과 다르면 Theme이 알아채 화면을 다시 놓게 한다 — T.bounds가 그 꼬리표를 지켜본다)

	fade = T.fader(r)
	setOp(if modal then 0 else 1, again)
	setTf(1, again)
end

-- 원본 $('banner').className = ''
function Banner.hide(instant: boolean?)
	if not on and not instant then
		return
	end
	on = false
	setOp(0, instant)
	setTf(0, instant)
end

function Banner.isOn(): boolean
	return on
end

-- 원본 #app.modal #banner { opacity: 0 }
function Banner.setModal(v: boolean)
	if modal == v then
		return
	end
	modal = v
	if on then
		setOp(if v then 0 else 1)
	end
end

-- 매 장면: 보스 알림의 꼬리표가 밝아졌다 어두워진다(원본 @keyframes bosstag: 0.5초에 밝기 1 → 1.35, 오가며)
function Banner.frame(dt: number)
	if not on or kind ~= "boss" then
		return
	end
	pulseT += dt
	local ph = pulseT % 1
	local x = if ph < 0.5 then ph * 2 else 2 - ph * 2
	local k = 1 + 0.35 * T.EASE.easeInOut(x)
	local tg = tagFrame
	if tg then
		local col = Color3.new(math.min(1, C.boss.R * k), math.min(1, C.boss.G * k), math.min(1, C.boss.B * k))
		tg.BackgroundColor3 = col
		local sq = tg:FindFirstChild("Sq")
		if sq and sq:IsA("Frame") then
			sq.BackgroundColor3 = col
		end
	end
end

return Banner
