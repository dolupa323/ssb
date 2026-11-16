-- 그리기 바탕: 「매 장면 다시 그리는」 캔버스 코드를 GuiObject 풀(pool) 위에 얹는다.
--  · 층(layer) = Frame 하나. 층 안에서는 z(ZIndex)마다 풀이 따로 있고, 한 번 만든 것은 지우지 않고 숨긴다.
--  · 물건마다 마지막으로 쓴 값을 기억해, 값이 바뀐 속성만 쓴다.
--  · 자리 · 크기는 Scale로 준다: 층의 크기가 U×U(세계 단위)라서 x/U가 곧 세계 좌표다(소수 자리까지 살아 있다).
local Art = require(script.Parent.Parent.Art)

local D = {}
local U = 4096
local INV = 1 / U
D.U = U
D.writes = 0 -- 속성을 쓴 횟수(잴 때 본다)
D.created = 0 -- 만든 GuiObject 수
D.layers = {} :: { any }
-- 지금 보이는 세계의 네모(잘라 내기에 쓴다)
D.vx0, D.vy0, D.vx1, D.vy1 = -1e9, -1e9, 1e9, 1e9

local floor, sqrt, cos, sin, atan2, abs, max, min, ceil = math.floor, math.sqrt, math.cos, math.sin, math.atan2, math.abs, math.max, math.min, math.ceil
local fromScale = UDim2.fromScale
local DEG = 180 / math.pi
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
D.WHITE, D.BLACK = WHITE, BLACK

D.FD = Enum.Font.GothamBlack -- 원본의 「Do Hyeon」(굵은 제목 글꼴) 자리
D.FB = Enum.Font.GothamBold -- 원본의 「IBM Plex Sans KR 700」 자리

-- ---------- 색 ----------
local colCache = {} :: { [string]: Color3 }
-- "255,214,90" 또는 "#ffd65a" → Color3 (같은 글이면 같은 값을 돌려준다 — 견줄 때 그대로 견줄 수 있다)
local function rgb(s: string): Color3
	local c = colCache[s]
	if c then
		return c
	end
	if string.sub(s, 1, 1) == "#" then
		c = Color3.fromRGB(tonumber(string.sub(s, 2, 3), 16) :: number, tonumber(string.sub(s, 4, 5), 16) :: number, tonumber(string.sub(s, 6, 7), 16) :: number)
	else
		local r, g, b = string.match(s, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
		c = Color3.fromRGB(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)
	end
	colCache[s] = c
	return c
end
D.rgb = rgb
-- 빛의 색: 원본은 빛을 「더하기 섞기」(+ 번짐)로 얹는다 — 밝은 바닥 위에서는 금방 하얗게 뜬다.
--  보통 섞기뿐인 GUI에서는 빛의 색을 흰 쪽으로 당겨서 흉내 낸다. 얼마나 당길지는 바닥의 밝기에 달려 있어 장소마다 바꾼다(D.setLite).
--  D.lite가 주는 값은 「열쇠」이고, 그릴 때 지금 장소의 색으로 바꿔 쓴다.
local liteByStr = {} :: { [string]: Color3 }
local liteKeys = {} :: { [Color3]: string }
local remap = {} :: { [Color3]: Color3 }
D.liteAmt = 0.55
D.glowName = "fx/glow" -- 둥근 빛에 쓰는 그림: 밝은 바닥이면 "prim/glow2"
function D.lite(s: string): Color3
	local key = liteByStr[s]
	if not key then
		local base = rgb(s)
		key = Color3.new(base.R, base.G, base.B) -- 새 값(열쇠로 쓴다)
		liteByStr[s] = key
		liteKeys[key] = s
		remap[key] = base:Lerp(WHITE, D.liteAmt)
	end
	return key
end
function D.setLite(amt: number)
	if D.liteAmt == amt then
		return
	end
	D.liteAmt = amt
	for key, s in liteKeys do
		remap[key] = rgb(s):Lerp(WHITE, amt)
	end
end
-- 밝게 뜬 색(흰 쪽으로 35% — 장소와 상관없이): 또렷한 빛 테두리에 쓴다
local brightCache = {} :: { [string]: Color3 }
function D.bright(s: string): Color3
	local c = brightCache[s]
	if not c then
		c = rgb(s):Lerp(WHITE, 0.35)
		brightCache[s] = c
	end
	return c
end
-- 달아오른 색(채널마다 1.25배 — 색은 그대로 두고 밝게): 원본의 번짐 층이 제 색을 한 번 더 얹어 생기는 선명함
local hotCache = {} :: { [string]: Color3 }
function D.hot(s: string): Color3
	local c = hotCache[s]
	if not c then
		local b = rgb(s)
		c = Color3.new(min(1, b.R * 1.25), min(1, b.G * 1.25), min(1, b.B * 1.25))
		hotCache[s] = c
	end
	return c
end
-- 열쇠 → 지금 쓰는 색
function D.lit(col: Color3): Color3
	return remap[col] or col
end

-- ---------- 층 ----------
local function newFrame(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	D.created += 1
	return f
end
D.newFrame = newFrame

function D.layer(parent: Instance, name: string, z: number)
	local L = { frame = newFrame(parent, name, z), pools = {}, list = {}, name = name }
	table.insert(D.layers, L)
	return L
end

function D.begin(L)
	for _, pool in L.list do
		pool.n = 0
	end
end

function D.finish(L)
	for _, pool in L.list do
		local items = pool.items
		for i = pool.n + 1, pool.shown do
			local o = items[i]
			if o.vis then
				o.vis = false
				o.g.Visible = false
				D.writes += 1
			end
		end
		pool.shown = pool.n
	end
end

-- 층을 통째로 비운다(숨긴다)
function D.clear(L)
	D.begin(L)
	D.finish(L)
end

-- 지금 보이는 물건 수
function D.visible(): number
	local n = 0
	for _, L in D.layers do
		for _, pool in L.list do
			n += pool.shown
		end
	end
	return n
end

-- 어느 풀이 많이 쓰는지 (잴 때 본다): "층:z:종류=수" 큰 것부터 n개
function D.breakdown(n: number): string
	local list = {}
	for _, L in D.layers do
		for key, pool in L.pools do
			if pool.shown > 0 then
				table.insert(list, { name = L.name .. ":" .. (key // 8) .. ":" .. (key % 8), c = pool.shown })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.c > b.c
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i].name .. "=" .. list[i].c
	end
	return table.concat(out, " ")
end

-- ---------- 만들기 ----------
local K_IMG, K_BOX, K_SHAPE, K_TEXT, K_TEXTL = 1, 2, 3, 4, 5

local function base(g: GuiObject, z: number, parent: Instance)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.BorderSizePixel = 0
	g.ZIndex = z
	g.Parent = parent
	D.created += 1
end

local create = {}
create[K_IMG] = function(parent: Instance, z: number)
	local g = Instance.new("ImageLabel")
	g.BackgroundTransparency = 1
	g.ScaleType = Enum.ScaleType.Stretch
	base(g, z, parent)
	return { g = g, vis = true, a = 1, rot = 0, col = WHITE, flip = false }
end
create[K_BOX] = function(parent: Instance, z: number)
	local g = Instance.new("Frame")
	g.BackgroundColor3 = WHITE
	base(g, z, parent)
	return { g = g, vis = true, a = 1, rot = 0, col = WHITE }
end
create[K_SHAPE] = function(parent: Instance, z: number)
	local g = Instance.new("Frame")
	g.BackgroundColor3 = WHITE
	g.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = g
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = 1
	stroke.Color = WHITE
	stroke.Parent = g
	base(g, z, parent)
	return { g = g, corner = corner, stroke = stroke, vis = true, fa = 0, fc = WHITE, sa = 1, sc = WHITE, sw = 1, rad = -1, rot = 0, son = true }
end
local function makeText(parent: Instance, z: number, left: boolean)
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Font = D.FD
	g.TextSize = 14
	g.TextColor3 = WHITE
	g.Text = ""
	g.TextWrapped = false
	g.RichText = false
	g.TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	g.TextYAlignment = Enum.TextYAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = 1
	stroke.Color = BLACK
	stroke.Enabled = false
	stroke.Parent = g
	base(g, z, parent)
	if left then
		g.AnchorPoint = Vector2.new(0, 0.5)
	end
	return { g = g, stroke = stroke, vis = true, a = 1, rot = 0, col = WHITE, ts = 14, font = D.FD, txt = "", sc = BLACK, sw = 0, sa = 1 }
end
create[K_TEXT] = function(parent: Instance, z: number)
	return makeText(parent, z, false)
end
create[K_TEXTL] = function(parent: Instance, z: number)
	return makeText(parent, z, true)
end

local function acquire(L, kind: number, z: number)
	local key = z * 8 + kind
	local pool = L.pools[key]
	if not pool then
		pool = { items = {}, n = 0, shown = 0 }
		L.pools[key] = pool
		table.insert(L.list, pool)
	end
	local n = pool.n + 1
	pool.n = n
	local o = pool.items[n]
	if not o then
		o = create[kind](L.frame, z)
		pool.items[n] = o
	elseif not o.vis then
		o.vis = true
		o.g.Visible = true
		D.writes += 1
	end
	return o
end

-- 투명도는 1/64 단계로(조금씩 바뀌는 값 때문에 매번 쓰지 않게)
local function qa(a: number?): number
	if a == nil or a >= 1 then
		return 1
	elseif a <= 0 then
		return 0
	end
	return floor(a * 64 + 0.5) / 64
end

-- ---------- 그리기 ----------
-- 그림: 가운데 (cx, cy), 크기 w×h(세계 단위), rot는 라디안
function D.img(L, z: number, name: string, cx: number, cy: number, w: number, h: number, alpha: number?, rot: number?, flip: boolean?, col: Color3?)
	if name == "fx/glow" and col and remap[col] then
		name = D.glowName -- 「빛의 색」으로 그리는 둥근 빛은 밝은 바닥에서 퍼진 빛 그림으로 바꿔 쓴다(D.glowName). 제 색으로 그리는 것은 그대로
	end
	local o = acquire(L, K_IMG, z)
	local g = o.g
	local fl = flip or false
	if o.name ~= name or o.flip ~= fl then
		local e = Art.info(name)
		if o.page ~= e.page then
			o.page = e.page
			Art.setPage(g, e.page)
			D.writes += 1
		end
		Art.setRect(g, e, fl)
		o.name = name
		o.flip = fl
		D.writes += 2
	end
	if o.x ~= cx or o.y ~= cy then
		o.x = cx
		o.y = cy
		g.Position = fromScale(cx * INV, cy * INV)
		D.writes += 1
	end
	if w < 0 then
		w = -w
	end
	if h < 0 then
		h = -h
	end
	if o.w ~= w or o.h ~= h then
		o.w = w
		o.h = h
		g.Size = fromScale(w * INV, h * INV)
		D.writes += 1
	end
	local a = qa(alpha)
	if o.a ~= a then
		o.a = a
		g.ImageTransparency = 1 - a
		D.writes += 1
	end
	local r = if rot then floor(rot * DEG * 2 + 0.5) / 2 else 0
	if o.rot ~= r then
		o.rot = r
		g.Rotation = r
		D.writes += 1
	end
	local c = if col then remap[col] or col else WHITE
	if o.col ~= c then
		o.col = c
		g.ImageColor3 = c
		D.writes += 1
	end
	return o
end

-- 그림을 「기준점」으로 놓는다: (X, Y)에 그림의 기준점(ox, oy)이 오고 k배. rot는 기준점을 축으로 돈다
function D.spr(L, z: number, name: string, X: number, Y: number, k: number, alpha: number?, rot: number?, flip: boolean?, col: Color3?)
	local e = Art.info(name)
	local w, h = e.w / e.s * k, e.h / e.s * k
	local dx = if flip then (e.w / e.s - e.ox) * k else e.ox * k
	local ox, oy = w / 2 - dx, h / 2 - e.oy * k
	if rot and rot ~= 0 then
		local c, s = cos(rot), sin(rot)
		ox, oy = ox * c - oy * s, ox * s + oy * c
	end
	return D.img(L, z, name, X + ox, Y + oy, w, h, alpha, rot, flip, col)
end

-- 네모(색을 채운 것)
function D.box(L, z: number, cx: number, cy: number, w: number, h: number, col: Color3, alpha: number?, rot: number?)
	local o = acquire(L, K_BOX, z)
	local g = o.g
	if o.x ~= cx or o.y ~= cy then
		o.x = cx
		o.y = cy
		g.Position = fromScale(cx * INV, cy * INV)
		D.writes += 1
	end
	if o.w ~= w or o.h ~= h then
		o.w = w
		o.h = h
		g.Size = fromScale(w * INV, h * INV)
		D.writes += 1
	end
	local a = qa(alpha)
	if o.a ~= a then
		o.a = a
		g.BackgroundTransparency = 1 - a
		D.writes += 1
	end
	local r = if rot then floor(rot * DEG * 2 + 0.5) / 2 else 0
	if o.rot ~= r then
		o.rot = r
		g.Rotation = r
		D.writes += 1
	end
	local c = remap[col] or col
	if o.col ~= c then
		o.col = c
		g.BackgroundColor3 = c
		D.writes += 1
	end
	return o
end

-- 왼쪽 위 (x, y)에서 w×h인 네모 (캔버스의 fillRect)
function D.rect(L, z: number, x: number, y: number, w: number, h: number, col: Color3, alpha: number?)
	return D.box(L, z, x + w / 2, y + h / 2, w, h, col, alpha)
end

-- 둥근 네모 · 동그라미: 채움(fillCol, fillA)과 테두리(strokeCol, strokeA, strokeW). radius가 없으면 알약 꼴(정사각형이면 동그라미)
--  테두리는 틀 바깥으로 그려진다 → 캔버스의 「가운데에 걸친 선」을 옮길 때는 부르는 쪽이 크기를 굵기만큼 줄여 준다(D.ring)
function D.shape(L, z: number, cx: number, cy: number, w: number, h: number, fillCol: Color3?, fillA: number?, strokeCol: Color3?, strokeA: number?, strokeW: number?, radius: number?, rot: number?)
	local o = acquire(L, K_SHAPE, z)
	local g = o.g
	if o.x ~= cx or o.y ~= cy then
		o.x = cx
		o.y = cy
		g.Position = fromScale(cx * INV, cy * INV)
		D.writes += 1
	end
	if w < 0.01 then
		w = 0.01
	end
	if h < 0.01 then
		h = 0.01
	end
	if o.w ~= w or o.h ~= h then
		o.w = w
		o.h = h
		g.Size = fromScale(w * INV, h * INV)
		D.writes += 1
	end
	if fillCol then
		fillCol = remap[fillCol] or fillCol
	end
	if strokeCol then
		strokeCol = remap[strokeCol] or strokeCol
	end
	local fa = if fillCol then qa(fillA) else 0
	if o.fa ~= fa then
		o.fa = fa
		g.BackgroundTransparency = 1 - fa
		D.writes += 1
	end
	if fillCol and o.fc ~= fillCol then
		o.fc = fillCol
		g.BackgroundColor3 = fillCol
		D.writes += 1
	end
	local sw = if strokeCol and strokeW and strokeW > 0 then floor(strokeW * 4 + 0.5) / 4 else 0
	local sa = if sw > 0 then qa(strokeA) else 0
	local on = sw > 0 and sa > 0
	local stroke = o.stroke
	if o.son ~= on then
		o.son = on
		stroke.Enabled = on
		D.writes += 1
	end
	if on then
		if o.sw ~= sw then
			o.sw = sw
			stroke.Thickness = sw
			D.writes += 1
		end
		if o.sa ~= sa then
			o.sa = sa
			stroke.Transparency = 1 - sa
			D.writes += 1
		end
		if o.sc ~= strokeCol then
			o.sc = strokeCol
			stroke.Color = strokeCol :: Color3
			D.writes += 1
		end
	end
	local rad = radius or -1
	if o.rad ~= rad then
		o.rad = rad
		o.corner.CornerRadius = if rad < 0 then UDim.new(0.5, 0) else UDim.new(0, rad)
		D.writes += 1
	end
	local r = if rot then floor(rot * DEG * 2 + 0.5) / 2 else 0
	if o.rot ~= r then
		o.rot = r
		g.Rotation = r
		D.writes += 1
	end
	return o
end

-- 채운 동그라미 (반지름 r)
function D.disc(L, z: number, cx: number, cy: number, r: number, col: Color3, alpha: number?)
	if r <= 20 then
		return D.img(L, z, "prim/disc", cx, cy, r * 2, r * 2, alpha, nil, nil, col)
	end
	return D.shape(L, z, cx, cy, r * 2, r * 2, col, alpha)
end

-- 채운 타원 (반지름 rx, ry · rot 라디안)
function D.oval(L, z: number, cx: number, cy: number, rx: number, ry: number, col: Color3, alpha: number?, rot: number?)
	return D.img(L, z, "prim/disc", cx, cy, rx * 2, ry * 2, alpha, rot, nil, col)
end

-- 고리: 반지름 r의 원 위에 굵기 lw로 걸친 선 (캔버스의 arc(0..TAU) + stroke)
function D.ring(L, z: number, cx: number, cy: number, r: number, lw: number, col: Color3, alpha: number?)
	local d = r * 2 - lw
	if d < 0.5 then
		-- 선이 반지름보다 굵다: 채운 동그라미가 된다
		return D.shape(L, z, cx, cy, r * 2 + lw, r * 2 + lw, col, alpha)
	end
	return D.shape(L, z, cx, cy, d, d, nil, nil, col, alpha, lw)
end

-- 타원 고리 (구운 고리 그림을 늘인다 — 선 굵기는 크기를 따라간다. thick = 굵은 고리 그림)
function D.ovalRing(L, z: number, cx: number, cy: number, rx: number, ry: number, col: Color3, alpha: number?, thick: boolean?)
	-- prim/ring: 96칸에 반지름 45 · prim/ringb: 반지름 40
	local k = if thick then 96 / 80 else 96 / 90
	return D.img(L, z, if thick then "prim/ringb" else "prim/ring", cx, cy, rx * 2 * k, ry * 2 * k, alpha, nil, nil, col)
end

-- 글. (cx, cy)는 글의 한가운데
function D.text(L, z: number, str: string, cx: number, cy: number, size: number, col: Color3, alpha: number?, strokeCol: Color3?, strokeW: number?, rot: number?, font: Enum.Font?, left: boolean?)
	local o = acquire(L, if left then K_TEXTL else K_TEXT, z)
	local g = o.g
	if o.txt ~= str then
		o.txt = str
		g.Text = str
		D.writes += 1
	end
	local ts = floor(size * 2 + 0.5) / 2
	if ts < 1 then
		ts = 1
	end
	if o.ts ~= ts then
		o.ts = ts
		g.TextSize = ts
		g.Size = fromScale((if left then 1200 else 600) * INV, ts * 1.4 * INV)
		D.writes += 2
	end
	if o.x ~= cx or o.y ~= cy then
		o.x = cx
		o.y = cy
		g.Position = fromScale(cx * INV, cy * INV)
		D.writes += 1
	end
	local a = qa(alpha)
	if o.a ~= a then
		o.a = a
		g.TextTransparency = 1 - a
		D.writes += 1
	end
	if o.col ~= col then
		o.col = col
		g.TextColor3 = col
		D.writes += 1
	end
	local f = font or D.FD
	if o.font ~= f then
		o.font = f
		g.Font = f
		D.writes += 1
	end
	local sw = if strokeCol and strokeW and strokeW > 0 then floor(strokeW * 4 + 0.5) / 4 else 0
	local stroke = o.stroke
	if o.sw ~= sw then
		if (o.sw > 0) ~= (sw > 0) then
			stroke.Enabled = sw > 0
			D.writes += 1
		end
		o.sw = sw
		if sw > 0 then
			stroke.Thickness = sw
			D.writes += 1
		end
	end
	if sw > 0 then
		if o.sc ~= strokeCol then
			o.sc = strokeCol
			stroke.Color = strokeCol :: Color3
			D.writes += 1
		end
		if o.sa ~= a then
			o.sa = a
			stroke.Transparency = 1 - a
			D.writes += 1
		end
	end
	local r = if rot then floor(rot * DEG * 2 + 0.5) / 2 else 0
	if o.rot ~= r then
		o.rot = r
		g.Rotation = r
		D.writes += 1
	end
	return o
end

-- 곧은 선 (x0,y0)→(x1,y1), 굵기 lw. cap = 끝을 둥글게(굵기의 반만큼 늘인다)
function D.line(L, z: number, x0: number, y0: number, x1: number, y1: number, lw: number, col: Color3, alpha: number?, cap: boolean?)
	local dx, dy = x1 - x0, y1 - y0
	local len = sqrt(dx * dx + dy * dy)
	if cap then
		len += lw * 0.7
	end
	return D.box(L, z, (x0 + x1) / 2, (y0 + y1) / 2, len, lw, col, alpha, atan2(dy, dx))
end

-- 점점 사라지는 선: (x0,y0)에서 진하고 (x1,y1)에서 투명. soft = 가장자리도 부드럽게
function D.gline(L, z: number, x0: number, y0: number, x1: number, y1: number, lw: number, col: Color3, alpha: number?, soft: boolean?)
	local dx, dy = x1 - x0, y1 - y0
	local len = sqrt(dx * dx + dy * dy)
	return D.img(L, z, if soft then "prim/softgrad" else "prim/grad", (x0 + x1) / 2, (y0 + y1) / 2, len, lw, alpha, atan2(dy, dx), nil, col)
end

-- 가장자리가 부드러운 선(빛줄기)
function D.sline(L, z: number, x0: number, y0: number, x1: number, y1: number, lw: number, col: Color3, alpha: number?)
	local dx, dy = x1 - x0, y1 - y0
	local len = sqrt(dx * dx + dy * dy)
	return D.img(L, z, "prim/soft", (x0 + x1) / 2, (y0 + y1) / 2, len, lw, alpha, atan2(dy, dx), nil, col)
end

-- 호: 가운데 (cx, cy) · 반지름 r · 각도 a0→a1(라디안, a1 > a0) · 굵기 lw. ysc = 세로 눌림(캔버스의 scale(1, ysc))
--  짧은 선분(돌린 네모)을 이어 만든다. 화면 밖의 선분은 만들지 않는다. seg = 선분 수를 정해 줄 때
function D.arc(L, z: number, cx: number, cy: number, r: number, a0: number, a1: number, lw: number, col: Color3, alpha: number?, ysc: number?, seg: number?)
	if a1 < a0 then
		a0, a1 = a1, a0
	end
	local span = a1 - a0
	if span <= 0 or r <= 0 then
		return
	end
	local ys = ysc or 1
	local n = seg or max(1, min(96, ceil(span * r / max(6, sqrt(14 * r)))))
	local step = span / n
	local chord = 2 * r * sin(step / 2)
	local ext = lw * math.tan(step / 2) -- 바깥쪽 틈을 메운다
	local m = lw + chord
	local vx0, vy0, vx1, vy1 = D.vx0 - m, D.vy0 - m, D.vx1 + m, D.vy1 + m
	local rm = r * cos(step / 2)
	for i = 0, n - 1 do
		local am = a0 + (i + 0.5) * step
		local ca, sa = cos(am), sin(am)
		local x, y = cx + ca * rm, cy + sa * rm * ys
		if x > vx0 and x < vx1 and y > vy0 and y < vy1 then
			if ys == 1 then
				D.box(L, z, x, y, chord + ext, lw, col, alpha, am + math.pi / 2)
			else
				-- 눌린 원: 접선 방향과 길이를 눌림에 맞춘다
				local tx, ty = -sa, ca * ys
				local tl = sqrt(tx * tx + ty * ty)
				D.box(L, z, x, y, (chord + ext) * tl, lw * (ys + (1 - ys) * abs(sa)), col, alpha, atan2(ty, tx))
			end
		end
	end
end

-- 그림 띠로 만든 호: name은 「세로가 반지름 방향(위가 바깥)」인 띠 그림. hgt = 띠의 높이, off = 띠 가운데가 반지름에서 벗어난 만큼(바깥이 +)
function D.arcImg(L, z: number, name: string, cx: number, cy: number, r: number, a0: number, a1: number, hgt: number, off: number, alpha: number?)
	local span = a1 - a0
	if span <= 0 or r <= 0 then
		return
	end
	local n = max(1, min(96, ceil(span * r / max(6, sqrt(24 * r)))))
	local step = span / n
	local chord = 2 * r * sin(step / 2)
	local ext = hgt * 0.5 * math.tan(step / 2)
	local m = hgt + chord
	local vx0, vy0, vx1, vy1 = D.vx0 - m, D.vy0 - m, D.vx1 + m, D.vy1 + m
	local rm = r * cos(step / 2) + off
	for i = 0, n - 1 do
		local am = a0 + (i + 0.5) * step
		local x, y = cx + cos(am) * rm, cy + sin(am) * rm
		if x > vx0 and x < vx1 and y > vy0 and y < vy1 then
			D.img(L, z, name, x, y, chord + ext, hgt, alpha, am + math.pi / 2)
		end
	end
end

-- 그림의 가로 일부만 보이게 자른다 (u0..u1 = 0..1). D.img로 얻은 것에 쓴다
function D.crop(o, u0: number, u1: number)
	local e = Art.info(o.name)
	local x0, x1 = floor(e.x + e.w * u0 + 0.5), floor(e.x + e.w * u1 + 0.5)
	local g = o.g
	g.ImageRectOffset = Vector2.new(x0, e.y)
	g.ImageRectSize = Vector2.new(max(1, x1 - x0), e.h)
	o.name = nil -- 다음에 쓸 때 자르는 네모를 다시 잡게
	D.writes += 2
end

-- 겹치는 순서를 바꾼다(바뀔 때만 쓴다)
function D.z(o, z: number)
	if o.z ~= z then
		o.z = z
		o.g.ZIndex = z
		D.writes += 1
	end
end

-- 화면에 걸리는가 (가운데 x, y · 여유 m)
function D.inView(x: number, y: number, m: number): boolean
	return x > D.vx0 - m and x < D.vx1 + m and y > D.vy0 - m and y < D.vy1 + m
end

-- 풀에 든 것 모두에 fn(o)를 한다 (가만히 둔 층의 색만 바꿀 때)
function D.each(L, fn: (any) -> ())
	for _, pool in L.list do
		for i = 1, pool.shown do
			fn(pool.items[i])
		end
	end
end

return D
