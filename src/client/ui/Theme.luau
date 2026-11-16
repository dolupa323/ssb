--!strict
-- UI를 짜는 연장: 원본 index.html의 CSS 값(색 · 글꼴 · 둥근 모서리 · 테두리)을 Roblox GUI로 옮길 때 쓰는 것들.
--  길이는 모두 「CSS px」 = 화면 틀(Stage.ui)의 한 점이다.
local TextService = game:GetService("TextService")
local Bitmap = require(script.Parent.Bitmap)

local T = {}

-- ---------- 색 (원본 :root) ----------
local function hex(s: string): Color3
	return Color3.fromRGB(tonumber(s:sub(2, 3), 16) :: number, tonumber(s:sub(4, 5), 16) :: number, tonumber(s:sub(6, 7), 16) :: number)
end
T.hex = hex
T.rgb = Color3.fromRGB
T.C = {
	floor = hex("#cfcbc0"),
	ink = hex("#1b2124"),
	panel = hex("#1e2629"),
	paper = hex("#f6f4ee"),
	line2 = hex("#00a84d"),
	safety = hex("#ffc928"),
	led = hex("#ffb300"),
	danger = hex("#e5484d"),
	boss = hex("#b03bd6"),
	muted = hex("#6d7679"),
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
	edge = hex("#0b0f10"), -- HUD 틀의 테두리
	dark = Color3.fromRGB(15, 20, 22), -- rgba(15,20,22,…) HUD 바탕
	body = hex("#14191c"),
}
-- 난이도 색 (.d0 ~ .d3)
T.DIFF_COLOR = { hex("#35b25f"), hex("#f2b824"), hex("#f07d24"), hex("#e5484d") }

-- ---------- 글꼴 ----------
-- 제목(Do Hyeon) · 전광판 숫자(VT323): 진짜 글꼴을 구운 글자 그림으로 그린다(ui/Bitmap.luau). 아래의 display · led 글꼴은 구운 판에 없는 글자가 섞였을 때만 쓰인다.
-- 본문(IBM Plex Sans KR): Roblox에는 그 글꼴이 없다. 같은 집안의 「IBM Plex Sans JP」(Roblox가 올린 글꼴 · 영문 · 숫자의 모양이 같다)를 쓰고, 한글은 Roblox가 스스로 고르는 한글 글꼴로 그려진다.
--  T.BODY = "builder"로 바꾸면 BuilderSans(Roblox 기본 글꼴)를 쓴다.
T.BODY = "plex"
local BODY_FAMILY = {
	plex = "rbxassetid://12187364147", -- IBM Plex Sans JP
	builder = Font.fromEnum(Enum.Font.BuilderSans).Family,
}
-- CSS font-size(px) → Roblox TextSize의 배율. Roblox의 TextSize는 「한 줄의 높이」라 같은 수를 넣으면 CSS보다 글자가 작다.
--  builder 1.32 = 실제 Studio 화면(tools/studio/shots/cmp/50-pause.png)에서 원본과 글의 폭을 재서 맞춘 값(1.2일 때 원본이 1.10배 컸다).
--  plex 1.45 = 그 글꼴의 줄 높이(1.448em)로 셈한 값 — Studio에서 아직 재지 않았다.
local BODY_FS = { plex = 1.45, builder = 1.32 }
local FAMILY = {
	body = BODY_FAMILY[T.BODY],
	display = BODY_FAMILY[T.BODY],
	led = Font.fromEnum(Enum.Font.Code).Family,
}
-- 같은 글꼴의 Enum.Font (TextService:GetTextSize로 폭을 잴 때 쓴다)
local ENUM_FONT = {
	body = { [400] = Enum.Font.BuilderSans, [500] = Enum.Font.BuilderSansMedium, [600] = Enum.Font.BuilderSansBold, [700] = Enum.Font.BuilderSansBold },
	display = { [800] = Enum.Font.BuilderSansExtraBold },
	led = { [700] = Enum.Font.Code },
}
local WEIGHT = {
	[400] = Enum.FontWeight.Regular,
	[500] = Enum.FontWeight.Medium,
	[600] = Enum.FontWeight.SemiBold,
	[700] = Enum.FontWeight.Bold,
	[800] = Enum.FontWeight.ExtraBold,
}
-- 본문 글꼴이 에셋 글꼴이면 미리 읽어 둔다(다 읽히기 전에 잰 글의 폭은 임시 글꼴의 것이다). 기다린다 — 불러오는 화면 동안 부른다
function T.preload()
	local family = FAMILY.body
	if string.sub(family, 1, 13) ~= "rbxassetid://" then
		return
	end
	pcall(function()
		TextService:GetFamilyInfoAsync(family)
	end)
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ family })
	end)
end

local fontCache = {} :: { [string]: Font }
function T.font(kind: string?, weight: number?): Font
	local k = kind or "body"
	local w = weight or (if k == "display" then 700 elseif k == "led" then 700 else 400)
	local id = k .. w
	local f = fontCache[id]
	if not f then
		f = Font.new(FAMILY[k], WEIGHT[w] or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
		fontCache[id] = f
	end
	return f
end

T.FS = BODY_FS[T.BODY]
function T.px(css: number): number
	return math.floor(css * T.FS + 0.5)
end

-- ---------- 틀 ----------
export type BoxOpts = {
	x: number?,
	y: number?,
	w: number?,
	h: number?,
	pos: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	bg: Color3?,
	a: number?, -- 바탕의 불투명도(0..1)
	r: number?, -- 둥근 모서리(px). 1000 넘게 주면 동그라미
	b: number?, -- 테두리 굵기(CSS처럼 틀 안쪽으로 먹는다)
	bc: Color3?,
	ba: number?, -- 테두리의 불투명도
	z: number?,
	clip: boolean?,
	visible: boolean?,
	grad: any?, -- { rot = CSS 각도, { 자리, 색 }, … } 또는 alpha = { { 자리, 불투명도 }, … }
	active: boolean?,
}

local function place(inst: GuiObject, o: any, inset: number)
	local pos = o.pos or UDim2.fromOffset(o.x or 0, o.y or 0)
	local size = o.size or UDim2.fromOffset(o.w or 0, o.h or 0)
	local anchor = o.anchor or Vector2.zero
	if inset > 0 then
		-- CSS의 테두리는 틀 안쪽, UIStroke는 바깥쪽 → 틀을 그만큼 줄여 놓는다
		size = UDim2.new(size.X.Scale, size.X.Offset - 2 * inset, size.Y.Scale, size.Y.Offset - 2 * inset)
		pos = UDim2.new(pos.X.Scale, pos.X.Offset + inset * (1 - 2 * anchor.X), pos.Y.Scale, pos.Y.Offset + inset * (1 - 2 * anchor.Y))
	end
	inst.Position = pos
	inst.Size = size
	inst.AnchorPoint = anchor
end

function T.corner(inst: Instance, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = if r >= 1000 then UDim.new(1, 0) else UDim.new(0, r)
	c.Parent = inst
	return c
end

function T.stroke(inst: Instance, thickness: number, color: Color3, alpha: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Transparency = 1 - (alpha or 1)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

-- CSS linear-gradient(각도, …) → UIGradient. CSS 180deg(위→아래) = Rotation 90
function T.gradient(inst: Instance, g: any): UIGradient
	local ug = Instance.new("UIGradient")
	ug.Rotation = (g.rot or 180) - 90
	if #g > 0 then
		local keys = {}
		for _, k in ipairs(g) do
			table.insert(keys, ColorSequenceKeypoint.new(k[1], k[2]))
		end
		ug.Color = ColorSequence.new(keys)
	end
	if g.alpha then
		local keys = {}
		for _, k in ipairs(g.alpha) do
			table.insert(keys, NumberSequenceKeypoint.new(k[1], 1 - k[2]))
		end
		ug.Transparency = NumberSequence.new(keys)
	end
	ug.Parent = inst
	return ug
end

local function dress(f: GuiObject, o: any, inset: number)
	f.BorderSizePixel = 0
	if o.bg or o.grad then
		f.BackgroundColor3 = if o.grad and #o.grad > 0 then T.C.white else (o.bg or T.C.white)
		f.BackgroundTransparency = 1 - (o.a or 1)
	else
		f.BackgroundTransparency = 1
	end
	if o.z then
		f.ZIndex = o.z
	end
	if o.clip then
		f.ClipsDescendants = true
	end
	if o.visible == false then
		f.Visible = false
	end
	if o.r and o.r > 0 then
		T.corner(f, if o.r >= 1000 then o.r else math.max(0, o.r - inset))
	end
	if inset > 0 then
		T.stroke(f, inset, o.bc or T.C.black, o.ba)
	end
	if o.grad then
		T.gradient(f, o.grad)
	end
end

function T.box(parent: Instance, name: string, o: BoxOpts): Frame
	local f = Instance.new("Frame")
	f.Name = name
	local inset = o.b or 0
	place(f, o, inset)
	dress(f, o, inset)
	if o.active then
		f.Active = true
	end
	f.Parent = parent
	return f
end

-- 누르는 것. 글은 따로 얹는다(Text = "")
function T.button(parent: Instance, name: string, o: BoxOpts): TextButton
	local f = Instance.new("TextButton")
	f.Name = name
	f.Text = ""
	f.AutoButtonColor = false
	local inset = o.b or 0
	place(f, o, inset)
	dress(f, o, inset)
	f.Parent = parent
	return f
end

export type TextOpts = {
	text: string?,
	fs: number, -- CSS font-size
	font: string?, -- "body" | "display" | "led"
	wt: number?, -- 400 · 500 · 600 · 700
	color: Color3?,
	a: number?,
	ax: string?, -- "Left" | "Center" | "Right"
	ay: string?, -- "Top" | "Center" | "Bottom"
	wrap: boolean?,
	lh: number?, -- CSS line-height(배수)
	x: number?,
	y: number?,
	w: number?,
	h: number?,
	pos: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	z: number?,
	rich: boolean?,
	shadow: number?, -- 글자 테두리(어두운 그림자 대신)의 불투명도
	shadowColor: Color3?,
	trunc: boolean?,
	ls: number?, -- 글자 사이(em) — 구운 글자(display · led)에만
}

local AX = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local AY = { Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

local enumFont: { [any]: Enum.Font } = setmetatable({}, { __mode = "k" }) :: any

-- 지금 글의 크기(한 줄로 놓았을 때). TextBounds는 아직 화면에 그려지지 않은 꼬리표에서 0일 수 있다 → 그때는 TextService로 잰다
-- ---------- 본문 글의 폭 재기 ----------
-- Roblox에서 글의 진짜 폭(TextBounds)은 「화면에 그려진 뒤」에야 믿을 수 있다: 막 만든 꼬리표는 0을 주고, 에셋 글꼴은 늦게 읽히며,
--  TextService:GetTextSize는 한글 대체 글꼴의 폭을 실제와 다르게 준다(실제 Studio에서 알림 상자가 글보다 좁게 나왔다).
-- 그래서 세 겹으로 잰다:
--  1) 시작할 때(T.calibrate) 화면에 놓은 견본 꼬리표로 「GetTextSize가 준 폭 → 실제 폭」의 배율을 굵기마다 구해 둔다. 그 꼬리표들은 그 뒤 자로도 쓴다.
--  2) 잴 때: 전에 본 진짜 폭(sizeCache) → 그 꼬리표의 TextBounds → 견본 꼬리표에 같은 글을 넣어 본 TextBounds → GetTextSize x 배율.
--  3) 잰 뒤에도 그 꼬리표를 지켜본다: 그려진 뒤의 진짜 폭이 잰 값과 1.5px 넘게 다르면 진짜 폭을 기억하고 화면들을 다시 놓게 한다(T.onRelayout).
local weightOf: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local calib = {} :: { [number]: number } -- 굵기 → 실제 폭 / GetTextSize의 폭
local probes = {} :: { [number]: TextLabel } -- 굵기 → 화면에 놓인 견본 꼬리표(자)
local sizeCache = {} :: { [string]: Vector2 } -- 그려진 뒤에 본 진짜 크기
local cacheN = 0
local tracked: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local relayouts, relayoutPending = 0, false
T.syncBounds = true -- 글을 바꾼 바로 그 자리에서 TextBounds가 새 값인가(T.calibrate가 실제로 해 보고 정한다)
T.onRelayout = nil :: (() -> ())? -- 글의 진짜 폭이 잰 것과 달랐다 → 화면들을 다시 놓는다(App이 건다)
T.RELAYOUT_MAX = 8 -- 한 접속에서 다시 놓는 횟수의 한도(끝없이 되풀이하지 않게)

local BIG = Vector2.new(100000, 100000)
-- TextBounds는 화면 픽셀이다: 조상에 UIScale이 걸려 있으면(화면 틀의 배율 · 알림이 나타날 때의 0.96배) 그만큼 곱해져 있다 → 그 배율로 나눠 「CSS px」로 돌린다
local function scaleOf(inst: Instance): number
	local k = 1
	local p: Instance? = inst
	while p and not p:IsA("LayerCollector") do
		local sc = p:FindFirstChildOfClass("UIScale")
		if sc then
			k *= sc.Scale
		end
		p = p.Parent
	end
	return if k > 0 then k else 1
end
local function realBounds(l: TextLabel | TextButton): Vector2
	local b = l.TextBounds
	if b.X <= 0 then
		return b
	end
	return b / scaleOf(l)
end
local function keyOf(l: TextLabel | TextButton): string
	return (weightOf[l] or 400) .. "|" .. l.TextSize .. "|" .. l.Text
end
local function estimate(text: string, size: number, weight: number): Vector2
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, ENUM_FONT.body[weight] or Enum.Font.BuilderSans, BIG)
	end)
	if ok then
		return Vector2.new(v.X * (calib[weight] or 1), v.Y)
	end
	return Vector2.zero
end
local function requestRelayout()
	if relayoutPending or relayouts >= T.RELAYOUT_MAX then
		return
	end
	relayoutPending = true
	task.delay(0.1, function()
		relayoutPending = false
		relayouts += 1
		if T.onRelayout then
			T.onRelayout()
		end
	end)
end

local function textSize(l: TextLabel | TextButton): Vector2
	local text = l.Text
	if text == "" then
		return Vector2.zero
	end
	local hit = sizeCache[keyOf(l)]
	if hit then
		return hit
	end
	local w = weightOf[l] or 400
	if T.syncBounds then
		local b = realBounds(l)
		if b.X > 0 then
			return b
		end
		local p = probes[w]
		if p then
			p.TextSize = l.TextSize
			p.Text = text
			local pb = realBounds(p)
			if pb.X > 0 then
				return pb
			end
		end
	end
	return estimate(text, l.TextSize, w)
end

-- 잰 값을 적어 두고, 그려진 뒤의 진짜 폭과 다르면 고치게 한다
local recent = {} :: { { any } } -- 방금 잰 것들 { 꼬리표, 기록, 잰 때 } — 신호가 오지 않아도 2초 동안 가끔 다시 본다
local function verify(l: TextLabel | TextButton, rec: any)
	if l.Parent == nil or l.Text ~= rec.text or l.TextWrapped then
		return
	end
	local rb = realBounds(l)
	local real = rb.X
	if real <= 0 or math.abs(real - rec.used) <= math.max(1.5, rec.used * 0.012) then
		return
	end
	local w = weightOf[l] or 400
	if cacheN < 600 then
		sizeCache[keyOf(l)] = rb
		cacheN += 1
	end
	if rec.used > 8 then
		calib[w] = math.clamp((calib[w] or 1) * real / rec.used, 0.6, 1.7) -- 다음 어림이 맞게 배율도 고친다
	end
	rec.used = real
	requestRelayout()
end
local function track(l: TextLabel | TextButton, used: number)
	local rec = tracked[l]
	if rec then
		rec.text, rec.used = l.Text, used
	else
		rec = { text = l.Text, used = used }
		tracked[l] = rec
		l:GetPropertyChangedSignal("TextBounds"):Connect(function()
			verify(l, rec)
		end)
	end
	if #recent < 400 then
		table.insert(recent, { l, rec, os.clock() })
	end
end
local pollT = 0
local function pollRecent(dt: number)
	pollT += dt
	if pollT < 0.12 or #recent == 0 then
		return
	end
	pollT = 0
	local now = os.clock()
	for i = #recent, 1, -1 do
		local r = recent[i]
		verify(r[1], r[2])
		if now - r[3] > 2 then
			table.remove(recent, i)
		end
	end
end

-- 시작할 때 한 번(기다린다): 견본 꼬리표를 화면에 놓고 본문 글꼴이 다 읽혀 폭이 가라앉기를 기다려 배율을 구한다
function T.calibrate(parent: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "TextProbe"
	holder.Size = UDim2.fromOffset(2, 2) -- (그려지기는 하되 보이지 않게: 2x2 안으로 잘라 낸다)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Parent = parent
	local SAMPLE = "가나다라마 바사아자 0123 ABC abc"
	local function probe(weight: number): TextLabel
		local pl = Instance.new("TextLabel")
		pl.Name = "p" .. weight
		pl.BackgroundTransparency = 1
		pl.Size = UDim2.fromOffset(4000, 60)
		pl.FontFace = T.font("body", weight)
		pl.TextSize = T.px(14)
		pl.TextXAlignment = Enum.TextXAlignment.Left
		pl.TextTransparency = 0.5
		pl.Text = SAMPLE
		pl.Parent = holder
		return pl
	end
	local weights = { 400, 500, 600, 700 }
	for _, w in weights do
		probes[w] = probe(w)
	end
	local sentinel = probe(400) -- 글꼴이 나중에 바뀌는지 지켜보는 것(글을 바꾸지 않는다)
	sentinel.Name = "sentinel"
	-- 폭이 0이 아니고 6장 내리 같아질 때까지(길어도 3초)
	local last, same = -1, 0
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		task.wait()
		local sum = 0
		local all = true
		for _, w in weights do
			local x = realBounds(probes[w]).X
			sum += x
			all = all and x > 0
		end
		if all and sum == last then
			same += 1
			if same >= 6 then
				break
			end
		else
			same = 0
		end
		last = sum
	end
	local any = false
	for _, w in weights do
		local real = realBounds(probes[w]).X
		local est = estimate(SAMPLE, probes[w].TextSize, w).X
		if real > 0 and est > 0 then
			calib[w] = math.clamp(real / est, 0.6, 1.7)
			any = true
		end
	end
	-- 글을 바꾼 자리에서 바로 TextBounds가 바뀌는가
	local p4 = probes[400]
	if any then
		p4.Text = "가"
		task.wait()
		task.wait()
		local short = p4.TextBounds.X
		p4.Text = SAMPLE
		local now = p4.TextBounds.X
		task.wait()
		task.wait()
		local later = p4.TextBounds.X
		T.syncBounds = math.abs(now - later) <= 0.5 and later > short + 1
	else
		T.syncBounds = false
	end
	-- 글꼴이 나중에 다 읽혀 폭이 달라지면: 기억한 것을 버리고 배율을 맞춘 뒤 화면을 다시 놓는다
	local base = realBounds(sentinel).X
	sentinel:GetPropertyChangedSignal("TextBounds"):Connect(function()
		local x = realBounds(sentinel).X
		if x > 0 and base > 0 and math.abs(x - base) > 1 then
			for _, w in weights do
				calib[w] = math.clamp((calib[w] or 1) * x / base, 0.6, 1.7)
			end
			table.clear(sizeCache)
			cacheN = 0
			base = x
			requestRelayout()
		elseif x > 0 and base <= 0 then
			base = x
			requestRelayout()
		end
	end)
end
T.calib = calib
-- 지금까지 화면을 다시 놓은 횟수(시험 · 살펴보기용)
function T.relayouts(): number
	return relayouts
end

function T.label(parent: Instance, name: string, o: TextOpts): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = T.font(o.font, o.wt)
	local kind = o.font or "body"
	local wt = o.wt or (if kind == "display" then 800 elseif kind == "led" then 700 else 400)
	enumFont[l] = (ENUM_FONT[kind] and ENUM_FONT[kind][wt]) or Enum.Font.BuilderSans
	weightOf[l] = if kind == "body" then wt else 700
	l.TextSize = T.px(o.fs)
	l.TextColor3 = o.color or T.C.ink
	l.TextTransparency = 1 - (o.a or 1)
	l.TextXAlignment = AX[o.ax or "Left"]
	l.TextYAlignment = AY[o.ay or "Center"]
	l.TextWrapped = o.wrap == true
	l.RichText = o.rich == true
	if o.trunc then
		l.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if o.lh then
		l.LineHeight = math.clamp(o.lh / T.FS, 1, 3)
	end
	l.Text = o.text or ""
	place(l, o, 0)
	if o.z then
		l.ZIndex = o.z
	end
	-- 제목 · 전광판 글꼴은 구운 글자로 그린다(그림자도 그쪽이 그린다)
	local baked = false
	if kind == "display" or kind == "led" then
		if o.trunc then
			l.ClipsDescendants = true
		end
		baked = Bitmap.attach(l, kind, o.fs, { ls = o.ls, lh = o.lh, shadow = o.shadow, shadowColor = o.shadowColor })
	end
	if o.shadow and not baked then
		local s = Instance.new("UIStroke")
		s.Thickness = 1
		s.Color = o.shadowColor or T.C.black
		s.Transparency = 1 - o.shadow
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = l
	end
	l.Parent = parent
	return l
end

-- 글이 차지하는 크기(px). 줄 바꿈이 있는 글은 폭을 먼저 정해 놓고 잰다
function T.bounds(l: TextLabel | TextButton): (number, number)
	local bw, bh = Bitmap.size(l)
	if bw and bh then
		return math.ceil(bw - 0.01), math.ceil(bh - 0.01)
	end
	local b = textSize(l)
	if not l.TextWrapped and l.Text ~= "" then
		track(l, b.X)
	end
	return math.ceil(b.X), math.ceil(b.Y)
end

-- 한 줄 글을 그 글의 폭에 맞춘 꼬리표로 만든다. 돌려주는 것: 꼬리표, 폭
function T.fit(parent: Instance, name: string, o: TextOpts): (TextLabel, number)
	local l = T.label(parent, name, o)
	l.Size = UDim2.fromOffset(2000, o.h or 20)
	local w = T.bounds(l)
	l.Size = UDim2.fromOffset(w, o.h or 20)
	return l, w
end

-- 글을 폭 w에 맞춰 낱말 사이에서만 줄을 바꾼다(원본 CSS의 word-break: keep-all — 한글 낱말을 중간에서 끊지 않는다).
--  Roblox의 TextWrapped는 한글을 글자 단위로 끊으므로 쓰지 않고, 낱말의 폭을 재서 줄바꿈을 직접 넣는다. 돌려주는 것: 줄 수
function T.wrap(l: TextLabel, text: string, w: number): number
	l.TextWrapped = false
	local keep = l.Size
	l.Size = UDim2.fromOffset(4000, 100)
	local cache = {} :: { [string]: number }
	local function width(s: string): number
		local v = cache[s]
		if not v then
			local bw = Bitmap.size(l, s) -- 구운 글자면 치수 표로 바로 잰다
			if bw then
				v = bw
			else
				l.Text = s
				v = textSize(l).X
			end
			cache[s] = v
		end
		return v
	end
	local space = math.max(0, width("가 가") - width("가가"))
	local lines = {} :: { string }
	for _, para in string.split(text, "\n") do
		local line, lw = "", 0
		for _, word in string.split(para, " ") do
			local ww = if word == "" then 0 else width(word)
			if line == "" then
				line, lw = word, ww
			elseif lw + space + ww <= w then
				line, lw = line .. " " .. word, lw + space + ww
			else
				table.insert(lines, line)
				line, lw = word, ww
			end
		end
		table.insert(lines, line)
	end
	l.Text = table.concat(lines, "\n")
	l.Size = keep
	return #lines
end

-- 폭 w 안에서 줄을 바꾸는 글. 높이를 재서 맞춘다. 돌려주는 것: 꼬리표, 높이
function T.para(parent: Instance, name: string, o: TextOpts): (TextLabel, number)
	o.wrap = false
	o.ay = o.ay or "Center" -- (줄 간격이 1.2보다 좁은 글은 Roblox에서 틀보다 조금 길어진다 → 위아래로 고르게 넘치게)
	local text = o.text or ""
	local l = T.label(parent, name, o)
	local n = T.wrap(l, text, o.w or 100)
	local h = n * (o.lh or 1.2) * o.fs -- 원본 CSS의 높이(줄 수 x line-height)
	l.Size = UDim2.fromOffset(o.w or 100, h)
	return l, h
end

-- 이미 만든 줄바꿈 글의 내용을 바꾼다. 돌려주는 것: 높이
function T.setPara(l: TextLabel, text: string, w: number, fs: number, lh: number?): number
	local n = T.wrap(l, text, w)
	local h = n * (lh or 1.2) * fs
	l.Size = UDim2.fromOffset(w, h)
	return h
end

-- 글의 불투명도(0..1)를 바꾼다 · 읽는다 (구운 글자든 보통 글꼴이든)
function T.setAlpha(l: TextLabel, a: number)
	if Bitmap.is(l) then
		Bitmap.setAlpha(l, a)
	else
		l.TextTransparency = 1 - a
	end
end
function T.alpha(l: TextLabel): number
	return if Bitmap.is(l) then Bitmap.alpha(l) else 1 - l.TextTransparency
end
-- 글씨 크기(CSS px)를 바꾼다
function T.setFs(l: TextLabel, fs: number)
	if Bitmap.is(l) then
		Bitmap.setSize(l, fs)
	else
		l.TextSize = T.px(fs)
	end
end

-- 1,234 (원본 toLocaleString('ko-KR'))
function T.num(v: number): string
	local s = tostring(math.floor(v + 0.5))
	local neg = s:sub(1, 1) == "-"
	if neg then
		s = s:sub(2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if neg then "-" else "") .. out
end

-- 마우스가 올라갔을 때 · 눌렀을 때의 모양(:hover · :active)
function T.states(btn: GuiButton, onHover: ((boolean) -> ())?, onPress: ((boolean) -> ())?)
	local down = false
	btn.MouseEnter:Connect(function()
		if onHover then
			onHover(true)
		end
	end)
	btn.MouseLeave:Connect(function()
		if onHover then
			onHover(false)
		end
		if down then
			down = false
			if onPress then
				onPress(false)
			end
		end
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		if onPress then
			onPress(true)
		end
	end)
	btn.MouseButton1Up:Connect(function()
		if down then
			down = false
			if onPress then
				onPress(false)
			end
		end
	end)
end

-- ---------- 움직임 (CSS transition · animation) ----------
-- cubic-bezier(x1, y1, x2, y2)
function T.bezier(x1: number, y1: number, x2: number, y2: number): (number) -> number
	local function bx(t: number): number
		local u = 1 - t
		return 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
	end
	local function by(t: number): number
		local u = 1 - t
		return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
	end
	return function(x: number): number
		if x <= 0 then
			return 0
		elseif x >= 1 then
			return 1
		end
		local lo, hi = 0, 1
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			if bx(mid) < x then
				lo = mid
			else
				hi = mid
			end
		end
		return by((lo + hi) / 2)
	end
end
T.EASE = {
	linear = function(x: number): number
		return x
	end,
	ease = T.bezier(0.25, 0.1, 0.25, 1), -- CSS 기본
	easeOut = T.bezier(0, 0, 0.58, 1),
	easeInOut = T.bezier(0.42, 0, 0.58, 1),
}

type Anim = { t: number, dur: number, delay: number, ease: (number) -> number, fn: (number) -> (), done: (() -> ())?, dead: boolean }
local anims = {} :: { Anim }

-- dur초 동안 fn(0→1)을 부른다. delay 동안은 fn(0)에 머문다(animation-fill-mode: backwards). 돌려주는 것: 멈추는 함수
function T.animate(dur: number, ease: ((number) -> number)?, fn: (number) -> (), delay: number?, done: (() -> ())?): () -> ()
	local a: Anim = { t = 0, dur = dur, delay = delay or 0, ease = ease or T.EASE.ease, fn = fn, done = done, dead = false }
	table.insert(anims, a)
	fn(0)
	return function()
		a.dead = true
	end
end

-- 매 장면 한 번(init.client의 고리에서) 부른다
function T.stepAnims(dt: number)
	pollRecent(dt)
	local i = 1
	while i <= #anims do
		local a = anims[i]
		if not a.dead then
			a.t += dt
			local x = if a.dur <= 0 then 1 else math.clamp((a.t - a.delay) / a.dur, 0, 1)
			a.fn(a.ease(x))
			if x >= 1 then
				a.dead = true
				if a.done then
					a.done()
				end
			end
		end
		if a.dead then
			table.remove(anims, i)
		else
			i += 1
		end
	end
end

-- 값이 바뀌면 dur초에 걸쳐 따라가게 한다(CSS transition). 돌려주는 것: 값을 넣는 함수(instant = 바로)
function T.transition(dur: number, ease: ((number) -> number)?, apply: (number) -> ()): (number, boolean?) -> ()
	local cur: number? = nil
	local target: number? = nil
	local stop: (() -> ())? = nil
	return function(v: number, instant: boolean?)
		if instant or cur == nil then
			if stop then
				stop()
				stop = nil
			end
			cur, target = v, v
			apply(v)
			return
		end
		if v == target then
			return
		end
		if stop then
			stop()
		end
		local from = cur :: number
		target = v
		stop = T.animate(dur, ease, function(x)
			cur = from + (v - from) * x
			apply(cur :: number)
		end)
	end
end

-- 크기가 다른 두 글(CSS px)을 밑줄(baseline)에 맞춰 나란히 놓을 때, 작은 글의 가운데를 큰 글의 가운데보다 내릴 만큼
function T.baseDown(big: number, small: number): number
	return 0.4 * (big - small)
end

-- 틀과 그 안의 모든 것을 한 덩어리처럼 흐리게(CSS opacity). 돌려주는 것: 불투명도(0..1)를 넣는 함수.
--  만들 때의 투명도를 바탕값으로 기억한다 — 안의 것을 새로 만들었으면 다시 만들 것.
function T.fader(root: Instance): (number) -> ()
	local items = {} :: { { any } }
	local function add(inst: Instance)
		if inst:GetAttribute("G") then
			return -- 구운 글자의 그림: 주인 꼬리표를 통해 흐린다
		end
		if inst:IsA("GuiObject") then
			table.insert(items, { inst, "BackgroundTransparency", inst.BackgroundTransparency })
			if Bitmap.is(inst) then
				table.insert(items, { inst, "", Bitmap.alpha(inst) })
			elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
				table.insert(items, { inst, "TextTransparency", (inst :: any).TextTransparency })
			elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				table.insert(items, { inst, "ImageTransparency", (inst :: any).ImageTransparency })
			end
		elseif inst:IsA("UIStroke") then
			table.insert(items, { inst, "Transparency", inst.Transparency })
		end
	end
	add(root)
	for _, d in root:GetDescendants() do
		add(d)
	end
	return function(alpha: number)
		for _, it in items do
			if it[2] == "" then
				Bitmap.setAlpha(it[1], it[3] * alpha)
			else
				(it[1] :: any)[it[2]] = 1 - (1 - it[3]) * alpha
			end
		end
	end
end

return T
