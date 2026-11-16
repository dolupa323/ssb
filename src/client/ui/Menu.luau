--!strict
-- 처음 화면(원본 #menu): 승강장 표지판 모양의 판 — 새벽 하늘 + 제목, 휴대폰 알림, 오늘의 경로, 설명, 혼잡도 고르기, 출근하기, 최고 기록, 조작법.
local Sim = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Sim")) :: any
local T = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Stage = require(script.Parent.Parent.Stage) :: any

local C = T.C
local Menu = {}
Menu.onStart = nil :: (() -> ())?
Menu.onDiff = nil :: ((number) -> ())?
Menu.onSettings = nil :: (() -> ())?
Menu.E = {} :: { [string]: any }

-- 원본 NOTI: { 아이콘 글, 보낸 사람, 내용 }
local NOTI = {
	{ "알람", "알람", "08:00입니다. 5분만 더는 없습니다" },
	{ "팀장", "김 팀장", "9시 주간 회의입니다. 늦지 마세요" },
	{ "동기", "입사 동기", "오늘 2호선 지옥이래. 살아서 보자" },
	{ "엄마", "엄마", "아침은 먹고 가니? 우산 챙겨라" },
	{ "날씨", "오늘 날씨", "월요일, 출근길 인파 매우 많음" },
	{ "회사", "사내 공지", "지각 3회 시 반차 1회 차감됩니다" },
}
Menu.NOTI = NOTI
local STOPS = {
	{ "역 앞", "전단지 알바" },
	{ "개찰구", "백팩 빌런" },
	{ "승강장", "문지기" },
	{ "열차 안", "도착까지 버티기" },
	{ "승강장", "하차 인파" },
	{ "에스컬\n레이터", "캐리어 여행객" }, -- 원본: 에스컬<wbr>레이터
	{ "회사 앞", "김 팀장" },
}
local INTRO = "역 앞에서 회사 자리에 앉기까지, 한 시간짜리 출근길입니다. 장소마다 버티고 선 진상을 밀어내야 다음으로 넘어가고, 9시를 넘기면 지각입니다."
-- 조작법: 글쇠는 { k = "W" }, 글은 낱말
local function K(k: string): any
	return { k = k }
end
local KEYS: { { any } } = {
	{ "이동", { K("W"), K("A"), K("S"), K("D"), "방향키, 또는 화면 드래그" } },
	{ "대시", { K("Space"), "또는 대시 버튼. 터치 화면에서는 끌고 있는 손 말고 다른 손가락으로 아무 곳이나 톡 쳐도 됩니다" } },
	{ "레벨업", { K("1"), K("2"), K("3"), "고르기,", K("R"), "다시 뽑기" } },
	{ "일시정지", { K("P"), K("Esc") } },
}
local TIPS = {
	"공격은 자동입니다. 움직여서 피하고, 떨어진 것을 주워 레벨을 올리세요.",
	"교통카드와 운동화는 기본으로 들고 시작합니다. 그 밖에 무기 네 칸, 장비 네 칸을 채울 수 있습니다. 무기를 6레벨까지 올리고 짝이 되는 장비를 갖추면 진화합니다.",
	"진화한 무기 둘이 서로 어울리면 숨겨진 조합이 열립니다. 어떤 짝인지는 직접 찾아보세요.",
	"차도와 선로에 빨간 경고가 뜨면 물러나세요. 버스와 열차는 인파도 쓸어 갑니다.",
}

local ov: W.Overlay? = nil
local shown = true
local howOpen = false
local notiI = 0 -- NOTI의 번호(1부터). 0 = 아직 없음
local diff = 1
local bestText = ""
local blurb = ""
local notiFade: ((number) -> ())? = nil
local notiBase = 0

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- 새벽 하늘(원본 <svg class="sky"> viewBox 560x190 · 아래쪽에 맞춰 잘라 채움)
local function buildHero(parent: Frame, iw: number, heroH: number)
	local hero = T.box(parent, "Hero", { w = iw, h = heroH, clip = true })
	local s = math.max(iw / 560, heroH / 190)
	local g0 = 1 - heroH / (190 * s) -- 보이는 맨 위가 그러데이션의 어디인가
	local c0, c1, c2 = T.hex("#2b3f66"), T.hex("#e98b5c"), T.hex("#ffd79a")
	local function colorAt(g: number): Color3
		return if g < 0.55 then lerpColor(c0, c1, g / 0.55) else lerpColor(c1, c2, (g - 0.55) / 0.45)
	end
	local backH = heroH + 14 -- 위쪽 모서리만 둥글게: 아래로 더 길게 만들고 잘라 낸다
	local span = 190 * s / backH
	local vm = math.clamp((0.55 - g0) * span, 0.01, 0.98)
	local vEnd = math.clamp((1 - g0) * span, vm + 0.005, 0.995)
	T.box(hero, "Sky", { w = iw, h = backH, r = 11, grad = { rot = 180, { 0, colorAt(g0) }, { vm, c1 }, { vEnd, c2 }, { 1, c2 } } })
	local art = T.box(hero, "SkyArt", { pos = UDim2.new(0.5, 0, 1, 0), w = 560, h = 190, anchor = Vector2.new(0.5, 1) })
	local sc = Instance.new("UIScale")
	sc.Scale = s
	sc.Parent = art
	local sun = T.hex("#fff3c4")
	T.box(art, "Halo", { x = 430 - 74, y = 150 - 74, w = 148, h = 148, bg = sun, a = 0.18, r = 1000 })
	T.box(art, "Sun", { x = 430 - 46, y = 150 - 46, w = 92, h = 92, bg = sun, a = 0.9, r = 1000 })
	for _, r in { { 0, 118, 46, 72 }, { 52, 96, 34, 94 }, { 250, 110, 40, 80 }, { 296, 84, 30, 106 }, { 500, 100, 60, 90 } } do
		T.box(art, "Far", { x = r[1], y = r[2], w = r[3], h = r[4], bg = T.hex("#3a3550"), a = 0.55 })
	end
	for _, r in { { 20, 138, 56, 52 }, { 84, 112, 44, 78 }, { 134, 146, 70, 44 }, { 330, 128, 50, 62 }, { 386, 104, 62, 86 }, { 454, 140, 64, 50 }, { 524, 122, 36, 68 } } do
		T.box(art, "Near", { x = r[1], y = r[2], w = r[3], h = r[4], bg = T.hex("#1d2233"), z = 2 })
	end
	for _, r in { { 92, 122, 6 }, { 104, 122, 6 }, { 92, 136, 6 }, { 116, 150, 6 }, { 394, 114, 7 }, { 408, 114, 7 }, { 422, 128, 7 }, { 394, 142, 7 }, { 436, 156, 7 }, { 340, 140, 6 }, { 362, 154, 6 }, { 30, 150, 6 }, { 54, 164, 6 } } do
		T.box(art, "Win", { x = r[1], y = r[2], w = r[3], h = 7, bg = T.hex("#ffd97a"), z = 3 })
	end
	return hero
end

-- 혼잡도 그림(.car): 사람이 찰수록 칸이 채워지는 객차
local function buildCar(parent: Instance, x: number, y: number, ink: Color3, fillN: number, fillC: Color3)
	local car = T.box(parent, "Car", { x = x, y = y, w = 56, h = 20, r = 4.5, b = 2, bc = ink })
	for i = 1, 8 do
		local on = i <= fillN
		T.box(car, "i" .. i, { x = 3 + (i - 1) * 6, y = 2, w = 4, h = 12, bg = if on then fillC else ink, a = if on then 1 else 0.16, r = 1.5 })
	end
	-- 바퀴 둘
	T.box(car, "w1", { x = 8 + 9 - 1.4, y = 16 + 5 - 3 + 0.1, w = 2.8, h = 2.8, bg = ink, r = 1000 })
	T.box(car, "w2", { x = 8 + 27 - 1.4, y = 16 + 5 - 3 + 0.1, w = 2.8, h = 2.8, bg = ink, r = 1000 })
end

-- 글쇠와 낱말이 섞인 줄을 폭에 맞춰 흘려 놓는다. 돌려주는 것: 높이
local function flow(parent: Instance, tokens: { any }, x0: number, y0: number, width: number): number
	local lineH = 19
	local probe = T.label(parent, "probe", { text = "", fs = 13, color = C.ink })
	probe.Size = UDim2.fromOffset(2000, lineH)
	probe.Text = "가 가"
	local a = probe.TextBounds.X
	probe.Text = "가가"
	local space = math.max(0, a - probe.TextBounds.X)
	probe:Destroy()
	local x, y = 0, 0
	for _, tok in tokens do
		if type(tok) == "table" then
			local f, w, l = W.kbd(parent, tok.k, 0, 0)
			if x > 0 and x + w > width then
				x, y = 0, y + lineH
			end
			f.Position = UDim2.fromOffset(x0 + x + 1, y0 + y - 2 + 1)
			l.Position = UDim2.fromOffset(x0 + x, y0 + y - 2)
			x += w + 2 + space
		else
			for _, word in string.split(tok, " ") do
				local l, w = T.fit(parent, "w", { text = word, fs = 13, color = C.ink, h = lineH })
				if x > 0 and x + w > width then
					x, y = 0, y + lineH
				end
				l.Position = UDim2.fromOffset(x0 + x, y0 + y)
				x += w + space
			end
		end
	end
	return y + lineH
end

function Menu.build()
	local keepScroll = Vector2.zero
	if ov then
		keepScroll = ov.scroll.CanvasPosition
		ov.root:Destroy()
	end
	local o = W.overlay("Menu", 15, T.rgb(12, 16, 18), 1)
	ov = o
	T.gradient(o.root, { rot = 90, alpha = { { 0, 0.66 }, { 1, 0.1 } } })
	o.root.Visible = shown
	table.clear(Menu.E)
	local E = Menu.E
	local sw = Stage.w
	local phone = Stage.phone
	local signW = math.min(560, sw - 32)
	local iw = signW - 6
	local padX = if phone then 16 else 22

	local wrap = T.box(o.scroll, "SignWrap", { w = signW, h = 100 })
	local sign = T.box(wrap, "Sign", { w = signW, h = 100, bg = C.paper, r = 14, b = 3, bc = C.edge })
	E.sign = sign

	-- 하늘 + 제목(.hero)
	local heroH = if phone then 150 else 168
	local hero = buildHero(sign, iw, heroH)
	local hp = if phone then { 12, 16, 10 } else { 14, 22, 12 }
	local whenFs = if phone then 38 else 46
	local whenH = math.ceil(whenFs * 0.9)
	local wl, ww = T.fit(hero, "When", { text = "08:00", fs = whenFs, font = "display", color = C.white, x = hp[2], y = hp[1], h = whenH, z = 5, shadow = 0.25, shadowColor = T.rgb(20, 20, 50) })
	local _ = wl
	T.label(hero, "WhenSub", { text = "월요일 아침\n출근까지 60분", fs = 12.5, wt = 600, color = C.white, a = 0.95, lh = 1.35, x = hp[2] + ww + 12, y = hp[1] + (whenH - 34) / 2, w = 200, h = 34, z = 5, shadow = 0.25, shadowColor = T.rgb(20, 20, 50) })
	local h1Fs = math.clamp(0.1 * sw, 36, 54)
	local h1H = math.ceil(h1Fs)
	-- 제목의 굳은 그림자(0 3px 0): 같은 글을 3px 아래에 한 번 더
	T.label(hero, "TitleShadow", { text = "출근길 서바이벌", fs = h1Fs, font = "display", color = T.rgb(20, 22, 40), a = 0.55, x = hp[2], y = heroH - hp[3] - h1H + 3, w = iw - 2 * hp[2], h = h1H, z = 5 })
	E.title = T.label(hero, "Title", { text = "출근길 서바이벌", fs = h1Fs, font = "display", color = C.white, x = hp[2], y = heroH - hp[3] - h1H, w = iw - 2 * hp[2], h = h1H, z = 6 })
	local y = heroH

	-- 휴대폰 알림(.noti)
	y += if phone then 10 else 12
	local nw = iw - 2 * padX
	T.box(sign, "NotiShadow", { x = padX, y = y + 2, w = nw, h = 56, bg = C.black, a = 0.06, r = 12 })
	local noti = T.box(sign, "Noti", { x = padX, y = y, w = nw, h = 56, bg = C.white, r = 12, b = 1, bc = T.hex("#dcd8cd") })
	notiBase = y + 1
	E.noti = noti
	local ic = T.box(noti, "Ic", { x = 12, y = 9, w = 36, h = 36, bg = C.ink, r = 10 })
	E.notiIc = T.label(ic, "T", { text = "", fs = 13, font = "display", color = C.white, ax = "Center", size = UDim2.fromScale(1, 1) })
	E.notiFrom = T.label(noti, "From", { text = "", fs = 12, wt = 700, color = C.muted, x = 12 + 36 + 11, y = 9.8, w = nw - 74, h = 16.2 })
	E.notiTxt = T.label(noti, "Txt", { text = "", fs = 13.5, color = C.ink, x = 12 + 36 + 11, y = 9.8 + 16.2, w = nw - 74, h = 18.2 })
	notiFade = T.fader(noti)
	y += 56

	-- 경로 머리(.route-h)
	y += if phone then 10 else 12
	local rdown = 1
	T.label(sign, "RouteL", { text = "08:00 출발", fs = 12, wt = 700, color = C.muted, x = padX, y = y + rdown, w = 120, h = 20 })
	T.label(sign, "RouteC", { text = "오늘의 출근 경로", fs = 16, font = "display", color = C.ink, ax = "Center", x = 0, y = y, w = iw, h = 20 })
	T.label(sign, "RouteR", { text = "09:00 출근", fs = 12, wt = 700, color = C.muted, ax = "Right", x = iw - padX - 120, y = y + rdown, w = 120, h = 20 })
	y += 20

	-- 일곱 정거장(.stops)
	local sp = if phone then 6 else 12
	local colW = (iw - 2 * sp) / #STOPS
	y += 10
	-- 점선(4px 점, 8px마다)
	local x1, x2 = sp + colW / 2, iw - sp - colW / 2
	local dx = x1
	while dx <= x2 do
		T.box(sign, "dot", { x = dx - 2, y = y + 6, w = 4, h = 4, bg = C.ink, r = 1000 })
		dx += 8
	end
	local stopFs = if phone then 12 else 14
	local rowH = 0
	for i, st in ipairs(STOPS) do
		local cx = sp + colW * (i - 0.5)
		local first, lastOne = i == 1, i == #STOPS
		-- 점: 안 17px + 테두리 4px = 25px (원본의 ::before는 box-sizing이 content-box다)
		T.box(sign, "StopDot" .. i, { x = cx - 12.5, y = y, w = 25, h = 25, bg = if first then C.ink elseif lastOne then C.danger else C.white, r = if lastOne then 8 else 1000, b = 4, bc = if lastOne then C.danger else C.ink, z = 2 })
		local name = st[1]
		local lines = #string.split(name, "\n")
		-- 이름이 칸에 들어가면 한 줄로(원본의 <wbr>: 넘칠 때만 끊긴다)
		local probe, pw = T.fit(sign, "probe", { text = (string.gsub(name, "\n", "")), fs = stopFs, font = "display" })
		probe:Destroy()
		if pw <= colW then
			name, lines = (string.gsub(name, "\n", "")), 1
		end
		local nameH = lines * stopFs * 1.1
		T.label(sign, "StopName" .. i, { text = name, fs = stopFs, font = "display", color = C.ink, ax = "Center", lh = 1.1, x = cx - colW / 2, y = y + 25 + 4, w = colW, h = nameH })
		local h = 25 + 4 + nameH
		if not phone then
			local _, sh = T.para(sign, "StopSub" .. i, { text = st[2], fs = 10.5, wt = 600, color = C.muted, ax = "Center", lh = 1.2, x = cx - colW / 2, y = y + h + 4, w = colW })
			h += 4 + sh
		end
		rowH = math.max(rowH, h)
	end
	y += rowH + (if phone then 10 else 12)
	T.box(sign, "StopsEdge", { x = 0, y = y, w = iw, h = 1, bg = T.hex("#d9d5ca") })
	y += 1

	-- 본문(.sign-body)
	local bw = iw - 2 * padX
	y += if phone then 12 else 14
	local _, introH = T.para(sign, "Intro", { text = INTRO, fs = 14, color = C.ink, lh = 1.55, x = padX, y = y, w = bw })
	y += introH + 12

	-- 혼잡도(.diff)
	T.label(sign, "DiffLabel", { text = "오늘 출근길 혼잡도", fs = 12, wt = 700, color = C.muted, x = padX, y = y, w = bw, h = 18 })
	y += 18 + 6
	local dw = (bw - 18) / 4
	E.diff = {}
	for i = 0, Sim.DIFFS and #Sim.DIFFS - 1 or 3 do
		local on = i == diff
		local dc = T.DIFF_COLOR[i + 1]
		local bx = padX + i * (dw + 6)
		if on then
			T.box(sign, "DiffShadow" .. i, { x = bx, y = y + 3, w = dw, h = 62, bg = dc, r = 9 }) -- 0 3px 0 var(--c)
		end
		local b = T.button(sign, "Diff" .. i, { x = bx, y = y, w = dw, h = 62, bg = if on then C.ink else C.white, r = 9, b = 2, bc = if on then C.ink else T.hex("#cfcbc0"), z = 2 })
		local ink = if on then C.white else C.ink
		buildCar(b, (dw - 4 - 56) / 2, 8, ink, (i + 1) * 2, dc)
		T.label(b, "T", { text = Sim.DIFFS[i + 1].name, fs = 17, font = "display", color = ink, ax = "Center", x = 0, y = 8 + 20 + 6, w = dw - 4, h = 17 })
		b:SetAttribute("Pressed", on)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		T.states(b, function(over)
			if not on and stroke then
				stroke.Color = if over then C.ink else T.hex("#cfcbc0")
			end
		end, nil)
		b.MouseButton1Click:Connect(function()
			if Menu.onDiff then
				Menu.onDiff(i)
			end
		end)
		E.diff[i] = b
	end
	y += 62 + 6
	E.blurb = T.label(sign, "DiffBlurb", { text = blurb, fs = 12.5, wt = 500, color = C.muted, x = padX, y = y, w = bw, h = 19 })
	y += 19 + 12

	-- 출근하기(.go) — 교통카드 그림(.idc)이 붙는다
	E.start = W.go(sign, "BtnStart", {
		text = "출근하기",
		x = padX,
		y = y,
		w = bw,
		h = 65,
		icon = function(holder: Frame): number
			holder.AnchorPoint = Vector2.new(0, 0.5)
			holder.Size = UDim2.fromOffset(26, 34)
			local card = T.box(holder, "Card", { w = 26, h = 34, bg = C.white, r = 5, clip = true })
			local band = T.box(card, "Band", { w = 26, h = 12, bg = C.line2, r = 5 })
			T.box(band, "Sq", { x = 0, y = 6, w = 26, h = 3, bg = C.line2 })
			T.box(card, "Cover", { x = 0, y = 9, w = 26, h = 4, bg = C.white })
			T.box(card, "Chip", { x = 8, y = 14, w = 10, h = 10, bg = T.hex("#c9c5ba"), r = 1000 })
			T.box(card, "Line", { x = 5, y = 27, w = 16, h = 3, bg = T.hex("#c9c5ba"), r = 2 })
			return 26
		end,
	})
	E.start.MouseButton1Click:Connect(function()
		if Menu.onStart then
			Menu.onStart()
		end
	end)
	y += 65 + 12

	-- 최고 기록 + 조작법 · 설정(.foot)
	local function link(name: string, text: string): (TextButton, number)
		local b = T.button(sign, name, { w = 10, h = 33, bg = C.white, r = 7, b = 1.5, bc = T.hex("#bdb9ae") })
		local l = T.label(b, "T", { text = text, fs = 12.5, wt = 700, color = C.ink, ax = "Center" })
		l.Size = UDim2.fromOffset(300, 30)
		local tw = T.bounds(l)
		local w = tw + 22 + 3
		b.Size = UDim2.fromOffset(w - 3, 30)
		l.Size = UDim2.fromScale(1, 1)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		T.states(b, function(over)
			if stroke then
				stroke.Color = if over then C.ink else T.hex("#bdb9ae")
			end
		end, nil)
		return b, w
	end
	local bSet, wSet = link("BtnSetMenu", "설정")
	local bHow, wHow = link("BtnHow", "조작법")
	E.btnSet, E.btnHow = bSet, bHow
	local bestW = bw - wSet - wHow - 20
	local best, bestH = T.para(sign, "Best", { text = bestText, fs = 12, wt = 500, color = C.muted, lh = 1.45, x = padX, y = y, w = bestW })
	E.best = best
	E.bestW = bestW
	local footH = math.max(33, bestH)
	best.Position = UDim2.fromOffset(padX, y + (footH - bestH) / 2)
	E.bestY, E.footH = y, footH
	bSet.Position = UDim2.fromOffset(padX + bw - wSet + 1.5, y + (footH - 33) / 2 + 1.5)
	bHow.Position = UDim2.fromOffset(padX + bw - wSet - 10 - wHow + 1.5, y + (footH - 33) / 2 + 1.5)
	bSet.MouseButton1Click:Connect(function()
		if Menu.onSettings then
			Menu.onSettings()
		end
	end)
	bHow.MouseButton1Click:Connect(function()
		howOpen = not howOpen
		Menu.build()
	end)
	bHow:SetAttribute("Expanded", howOpen)
	y += footH

	-- 조작법(.how)
	if howOpen then
		y += 12
		local how = T.box(sign, "How", { x = padX, y = y, w = bw, h = 10 })
		T.box(how, "Edge", { w = bw, h = 1, bg = T.hex("#dcd8cd") })
		local hy = 1 + 11
		local dtW = 0
		local dts = {}
		for i, row in ipairs(KEYS) do
			local l, w = T.fit(how, "Dt" .. i, { text = row[1], fs = 13, wt = 700, color = C.muted, h = 19 })
			dts[i] = l
			dtW = math.max(dtW, w)
		end
		for i, row in ipairs(KEYS) do
			dts[i].Position = UDim2.fromOffset(0, hy)
			local h = flow(how, row[2], dtW + 14, hy, bw - dtW - 14)
			hy += h + 6
		end
		hy += 10 - 6
		for i, tip in ipairs(TIPS) do
			T.box(how, "Bullet" .. i, { x = 0, y = hy + 6.5, w = 7, h = 7, bg = C.line2, r = 1000 })
			local _, th = T.para(how, "Tip" .. i, { text = tip, fs = 13, color = C.ink, lh = 1.45, x = 14, y = hy, w = bw - 14 })
			hy += th + 5
		end
		hy -= 5
		how.Size = UDim2.fromOffset(bw, hy)
		E.how = how
		y += hy
	end
	y += if phone then 16 else 18

	local signH = y + 6
	sign.Size = UDim2.fromOffset(iw, y)
	wrap.Size = UDim2.fromOffset(signW, signH)
	-- 넓은 화면(980px 이상): 왼쪽에 붙인다(padding-left: clamp(24px, 6vw, 96px))
	local left = if Stage.wide then math.clamp(0.06 * sw, 24, 96) else nil
	o.place(wrap, signW, signH, left)
	o.scroll.CanvasPosition = keepScroll

	if notiI > 0 then
		local n = NOTI[notiI]
		E.notiIc.Text, E.notiFrom.Text, E.notiTxt.Text = n[1], n[2], n[3]
	end
end

function Menu.show(v: boolean)
	shown = v
	if ov then
		ov.root.Visible = v
		if v then
			ov.scroll.CanvasPosition = Vector2.zero
		end
	end
end

function Menu.isShown(): boolean
	return shown
end

-- 원본 showBest()의 화면 부분: 고른 난이도 · 그 설명 · 최고 기록 줄
function Menu.refresh(d: number, blurbText: string, best: string)
	local changed = d ~= diff
	diff, blurb, bestText = d, blurbText, best
	if changed or not ov then
		Menu.build()
		return
	end
	local E = Menu.E
	E.blurb.Text = blurb
	local h = T.setPara(E.best, best, E.bestW, 12, 1.45)
	if math.max(33, h) ~= E.footH then
		Menu.build() -- 줄 수가 달라져 아래가 밀린다
	else
		E.best.Position = UDim2.fromOffset(E.best.Position.X.Offset, E.bestY + (E.footH - h) / 2)
	end
end

-- 원본 nextNoti(): 다음 알림으로. 위에서 8px 내려오며 나타난다(.35s ease-out)
function Menu.nextNoti()
	notiI = notiI % #NOTI + 1
	local n = NOTI[notiI]
	local E = Menu.E
	if not E.noti then
		return
	end
	E.notiIc.Text, E.notiFrom.Text, E.notiTxt.Text = n[1], n[2], n[3]
	local noti = E.noti :: Frame
	local f = notiFade
	local x0 = noti.Position.X.Offset
	T.animate(0.35, T.EASE.easeOut, function(x)
		if noti.Parent then
			noti.Position = UDim2.fromOffset(x0, notiBase - 8 * (1 - x))
			if f then
				f(x)
			end
		end
	end)
end

function Menu.notiIndex(): number
	return notiI
end

function Menu.howOpen(): boolean
	return howOpen
end

return Menu
