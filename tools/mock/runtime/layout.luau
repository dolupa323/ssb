-- 화면 자리 셈: AbsolutePosition · AbsoluteSize · AbsoluteRotation, UIScale · UIPadding · UIListLayout · UIGridLayout ·
--  UISizeConstraint · UIAspectRatioConstraint · AutomaticSize · 글의 크기(어림) · 그리는 차례(ZIndex) · 누른 자리 찾기.
--  무엇이든 자리에 닿는 것이 바뀌면 Layout.version이 오르고, 읽을 때 그 마디(와 조상)만 다시 셈한다.
--  좌표: AbsolutePosition은 Roblox처럼 「위쪽 띠(GuiInset) 아래 왼쪽 위」가 (0, 0)이다. 화면 좌표 = Absolute + (0, insetTop).
local R = require("./rt")
R.mark()
local Types = require("./types")
local Inst = require("./inst")
local Sched = require("./sched")
local KEY = Inst.KEY
local V2 = Types.V2

local Layout = {}
R.Layout = Layout
Layout.version = 1
function Layout.bump()
	Layout.version += 1
end

local function P(st, key: string)
	local v = st.props[key]
	if v == nil then
		return st.info.defaults[key]
	end
	return v
end
Layout.P = P

-- ---------- 기본값 · 자리에 닿는 속성 ----------
do
	local E = Types.enumItem
	local go = Inst.hook("GuiObject")
	go.defaults.BackgroundColor3 = Types.C3(163 / 255, 162 / 255, 165 / 255)
	go.defaults.BorderColor3 = Types.C3(27 / 255, 42 / 255, 53 / 255)
	go.defaults.BorderSizePixel = 1
	go.defaults.Interactable = true
	go.defaults.Visible = true
	go.defaults.ZIndex = 1
	go.layout = { "Position", "Size", "AnchorPoint", "Visible", "Rotation", "SizeConstraint", "AutomaticSize", "LayoutOrder", "ZIndex", "ClipsDescendants" }
	Inst.hook("GuiBase2d").defaults.AutoLocalize = true
	local lc = Inst.hook("LayerCollector")
	lc.defaults.Enabled = true
	lc.defaults.ResetOnSpawn = true
	lc.layout = { "Enabled", "ZIndexBehavior" }
	local gb = Inst.hook("GuiButton")
	gb.defaults.AutoButtonColor = true
	gb.defaults.Active = true
	gb.defaults.Selectable = true
	local tb = Inst.hook("TextBox")
	tb.defaults.Active = true
	tb.defaults.Selectable = true
	local sf = Inst.hook("ScrollingFrame")
	sf.defaults.ClipsDescendants = true
	sf.layout = { "CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness" }
	Inst.hook("UIListLayout").defaults.FillDirection = E("FillDirection", "Vertical")
	Inst.hook("UIListLayout").layout = { "Padding", "Wraps" }
	Inst.hook("UIGridLayout").layout = { "CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner" }
	local gsl = Inst.hook("UIGridStyleLayout")
	gsl.layout = { "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder" }
	gsl.defaults.HorizontalAlignment = E("HorizontalAlignment", "Left")
	gsl.defaults.VerticalAlignment = E("VerticalAlignment", "Top")
	Inst.hook("UISizeConstraint").defaults.MaxSize = V2(math.huge, math.huge)
	Inst.hook("UISizeConstraint").layout = { "MinSize", "MaxSize" }
	Inst.hook("UIAspectRatioConstraint").layout = { "AspectRatio", "AspectType", "DominantAxis" }
	Inst.hook("UIScale").layout = { "Scale" }
	Inst.hook("UIPadding").layout = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" }
	Inst.hook("UITextSizeConstraint").layout = { "MinTextSize", "MaxTextSize" }
	for _, cls in { "TextLabel", "TextButton", "TextBox" } do
		Inst.hook(cls).layout = { "Text", "TextSize", "TextWrapped", "TextScaled", "RichText", "LineHeight", "FontFace" }
	end
	Inst.hook("ScreenGui").layout = { "DisplayOrder", "IgnoreGuiInset", "ScreenInsets" }
end

-- ---------- 딸린 것(UIScale 같은 것) 찾기 ----------
local function comps(st)
	local c = st.comps
	if c then
		return c
	end
	c = {}
	for _, ch in st.children do
		local cs = rawget(ch, KEY)
		if cs.info.isUI and c[cs.class] == nil then
			c[cs.class] = cs
		end
	end
	st.comps = c
	return c
end
Layout.comps = comps

-- 화면에서의 부모(Folder는 건너뛴다)
local function guiParent(st)
	local p = st.parent
	while p do
		local ps = rawget(p, KEY)
		if ps.info.isGui then
			return ps
		end
		if ps.class ~= "Folder" then
			return nil
		end
		p = ps.parent
	end
	return nil
end
Layout.guiParent = guiParent

-- 화면에서의 아이(GuiObject)들 — Folder 안의 것도
local function guiChildren(st, out)
	for _, ch in st.children do
		local cs = rawget(ch, KEY)
		if cs.info.isGuiObject then
			table.insert(out, cs)
		elseif cs.class == "Folder" then
			guiChildren(cs, out)
		end
	end
	return out
end

-- ---------- 글의 크기(어림) ----------
--  한 글자의 폭(em 기준). em = 글씨 크기(TextSize) x 0.85 — 화면 그림(shot.mjs)도 같은 크기로 그린다.
local EM = 0.85
Layout.EM = EM
local ASCII = table.create(128, 0.56)
do
	local function set(chars: string, w: number)
		for i = 1, #chars do
			ASCII[string.byte(chars, i) + 1] = w
		end
	end
	set("abcdeghknopqsuvxyz", 0.52)
	set("ABCDEFGHKLNOPQRSTUVXYZ", 0.64)
	set("mwMW", 0.86)
	set(" ", 0.28)
	set("ilIj.,:;'!|", 0.27)
	set('ftrJ()[]{}-"`*', 0.36)
	set("0123456789", 0.56)
end
local function charEm(cp: number): number
	if cp < 128 then
		return ASCII[cp + 1]
	end
	if cp >= 0x1100 then
		if cp <= 0x11FF or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7A3) or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFF60) or (cp >= 0xFFE0 and cp <= 0xFFE6) or cp >= 0x1F000 then
			return 1.0
		end
	end
	return 0.6
end

-- 돌려주는 것: 폭, 높이, 줄 수
function Layout.measureText(text: string, textSize: number, wrapWidth: number?, lineHeight: number?): (number, number, number)
	local em = textSize * EM
	local lines, cur, maxw = 1, 0, 0
	local lastSpace: number? = nil
	local lastSpaceEnd = 0
	local function feed(cp: number)
		if cp == 10 then
			if cur > maxw then
				maxw = cur
			end
			cur = 0
			lines += 1
			lastSpace = nil
			return
		end
		local cw = charEm(cp) * em
		if wrapWidth and cur + cw > wrapWidth and cur > 0 then
			if lastSpace and cp < 0x1100 and cp ~= 32 then
				if lastSpace > maxw then
					maxw = lastSpace
				end
				cur -= lastSpaceEnd
			else
				if cur > maxw then
					maxw = cur
				end
				cur = 0
			end
			lines += 1
			lastSpace = nil
			if cp == 32 then
				return
			end
		end
		if cp == 32 then
			lastSpace = cur
			lastSpaceEnd = cur + cw
		end
		cur += cw
	end
	if utf8.len(text) then
		for _, cp in utf8.codes(text) do
			feed(cp)
		end
	else
		for i = 1, #text do
			feed(string.byte(text, i))
		end
	end
	if cur > maxw then
		maxw = cur
	end
	return maxw, lines * textSize * (lineHeight or 1), lines
end

-- 꾸밈 글(RichText)의 꼬리표를 걷어 낸다
function Layout.plainText(text: string): string
	local s = string.gsub(text, "<br%s*/?>", "\n")
	s = string.gsub(s, "<[^>]+>", "")
	s = string.gsub(s, "&lt;", "<")
	s = string.gsub(s, "&gt;", ">")
	s = string.gsub(s, "&quot;", '"')
	s = string.gsub(s, "&apos;", "'")
	s = string.gsub(s, "&amp;", "&")
	return s
end

local ensure

-- 글 마디의 글 크기: { w, h, fits, size(화면 픽셀) }
local function textInfo(st)
	ensure(st)
	if st.tv == Layout.version then
		return st.ti
	end
	local text = P(st, "Text")
	if text == "" and st.class == "TextBox" then
		text = P(st, "PlaceholderText")
	end
	if P(st, "RichText") then
		text = Layout.plainText(text)
	end
	local scale = st.asc or 1
	local lh = P(st, "LineHeight")
	local size = P(st, "TextSize") * scale
	local wrapW = nil
	local auto = st.props.AutomaticSize
	local autoX = auto ~= nil and (auto.Name == "X" or auto.Name == "XY")
	if P(st, "TextScaled") then
		local c = comps(st)
		local lo, hi = 1, 100
		local tc = c.UITextSizeConstraint
		if tc then
			lo, hi = P(tc, "MinTextSize"), P(tc, "MaxTextSize")
		end
		lo, hi = math.max(1, math.floor(lo * scale)), math.max(1, math.floor(hi * scale))
		local best = lo
		local a, b = lo, hi
		while a <= b do
			local mid = (a + b) // 2
			local w, h = Layout.measureText(text, mid, st.aw, lh)
			if w <= st.aw + 0.5 and h <= st.ah + 0.5 then
				best = mid
				a = mid + 1
			else
				b = mid - 1
			end
		end
		size = best
		wrapW = st.aw
	elseif P(st, "TextWrapped") and not autoX then
		wrapW = st.aw
	end
	local w, h = Layout.measureText(text, size, wrapW, lh)
	local ti = { w = w, h = h, size = size, fits = w <= st.aw + 0.5 and h <= st.ah + 0.5 }
	st.ti = ti
	st.tv = Layout.version
	return ti
end
Layout.textInfo = textInfo

-- ---------- 자리 셈 ----------
local ZERO_PARENT = { cx = 0, cy = 0, cw = 0, ch = 0, asc = 1, arot = 0 }

-- 셈하는 도중에는 알림을 내지 않고 모아 둔다(건 함수가 셈 한가운데에서 자리를 바꾸지 않게) → 셈이 끝난 뒤 drain()
local notes = {} :: { any }
local function notifyAbs(st, changedPos: boolean, changedSize: boolean)
	if st.sig or st.psig then
		if not st.notePos and not st.noteSize then
			table.insert(notes, st)
		end
		st.notePos = st.notePos or changedPos
		st.noteSize = st.noteSize or changedSize
	end
end
local function noteContent(lay)
	if not lay.noteContent then
		lay.noteContent = true
		table.insert(notes, lay)
	end
end
local function drain()
	if #notes == 0 then
		return
	end
	local list = notes
	notes = {}
	for _, st in list do
		if st.noteContent then
			st.noteContent = false
			Inst.fireChanged(st, "AbsoluteContentSize", V2(st.contentW or 0, st.contentH or 0))
		else
			local ns, np = st.noteSize, st.notePos
			st.noteSize, st.notePos = false, false
			if ns then
				Inst.fireChanged(st, "AbsoluteSize", V2(st.aw, st.ah))
			end
			if np then
				Inst.fireChanged(st, "AbsolutePosition", V2(st.ax, st.ay))
			end
		end
	end
end
Layout.drain = drain

local arrange

-- 자리 · 크기가 정해진 뒤: 배율 · 내용 상자 · 알림 · 아이 놓기
local function finish(st, x: number, y: number, w: number, h: number, pscale: number, prot: number)
	local c = comps(st)
	local k = 1
	local us = c.UIScale
	if us then
		k = P(us, "Scale")
	end
	local s = pscale * k
	st.asc = s
	local changedPos = st.ax ~= x or st.ay ~= y
	local changedSize = st.aw ~= w or st.ah ~= h
	st.ax, st.ay, st.aw, st.ah = x, y, w, h
	local rot = st.props.Rotation
	st.arot = prot + (rot or 0)
	local cx, cy, cw, ch = x, y, w, h
	local pad = c.UIPadding
	local padW, padH = 0, 0
	if pad then
		local l, r, t, b = P(pad, "PaddingLeft"), P(pad, "PaddingRight"), P(pad, "PaddingTop"), P(pad, "PaddingBottom")
		local lp, rp = l.Scale * w + l.Offset * s, r.Scale * w + r.Offset * s
		local tp, bp = t.Scale * h + t.Offset * s, b.Scale * h + b.Offset * s
		cx += lp
		cy += tp
		cw -= lp + rp
		ch -= tp + bp
		padW, padH = lp + rp, tp + bp
	end
	st.padW, st.padH = padW, padH
	if st.class == "ScrollingFrame" then
		local cs = P(st, "CanvasSize")
		local canW = math.max(w, cs[1] * w + cs[2] * s)
		local canH = math.max(h, cs[3] * h + cs[4] * s)
		if st.autoCanvasW then
			canW = math.max(canW, st.autoCanvasW)
		end
		if st.autoCanvasH then
			canH = math.max(canH, st.autoCanvasH)
		end
		local cp = P(st, "CanvasPosition")
		local px = math.clamp(cp.X, 0, math.max(0, canW - w))
		local py = math.clamp(cp.Y, 0, math.max(0, canH - h))
		st.canvasW, st.canvasH = canW, canH
		cx -= px
		cy -= py
		cw = canW - padW
		ch = canH - padH
	end
	st.cx, st.cy, st.cw, st.ch = cx, cy, cw, ch
	st.lv = Layout.version
	if changedPos or changedSize then
		notifyAbs(st, changedPos, changedSize)
	end
	local lay = c.UIListLayout or c.UIGridLayout
	if lay then
		arrange(st, c, lay)
	else
		st.layW, st.layH = nil, nil
	end
end

local function baseSize(st, p): (number, number)
	local size = P(st, "Size")
	local s = p.asc
	local pw, ph = p.cw, p.ch
	local w, h
	local sc = st.props.SizeConstraint
	if sc == nil or sc.Name == "RelativeXY" then
		w = size[1] * pw + size[2] * s
		h = size[3] * ph + size[4] * s
	elseif sc.Name == "RelativeXX" then
		w = size[1] * pw + size[2] * s
		h = size[3] * pw + size[4] * s
	else
		w = size[1] * ph + size[2] * s
		h = size[3] * ph + size[4] * s
	end
	local c = comps(st)
	local us = c.UIScale
	if us then
		local k = P(us, "Scale")
		w *= k
		h *= k
	end
	local szc = c.UISizeConstraint
	if szc then
		local mn, mx = P(szc, "MinSize"), P(szc, "MaxSize")
		w = math.clamp(w, mn.X * s, math.max(mn.X * s, mx.X * s))
		h = math.clamp(h, mn.Y * s, math.max(mn.Y * s, mx.Y * s))
	end
	local arc = c.UIAspectRatioConstraint
	if arc then
		local ratio = P(arc, "AspectRatio")
		if ratio > 0 then
			if P(arc, "AspectType").Name == "FitWithinMaxSize" then
				if h > 0 and w / h > ratio then
					w = h * ratio
				else
					h = w / ratio
				end
			elseif P(arc, "DominantAxis").Name == "Width" then
				h = w / ratio
			else
				w = h * ratio
			end
		end
	end
	return w, h
end

local function placeOf(st, p, w: number, h: number): (number, number)
	local pos = P(st, "Position")
	local s = p.asc
	local x = p.cx + pos[1] * p.cw + pos[2] * s
	local y = p.cy + pos[3] * p.ch + pos[4] * s
	local an = st.props.AnchorPoint
	if an then
		x -= an.X * w
		y -= an.Y * h
	end
	return x, y
end

-- 이번 판에 셈해 둔 아래 마디들을 무른다(부모의 상자가 바뀌었다)
local function invalidate(st)
	for _, ch in st.children do
		local cs = rawget(ch, KEY)
		if cs.info.isGuiObject or cs.class == "Folder" then
			if cs.lv == Layout.version then
				cs.lv = 0
			end
			if #cs.children > 0 then
				invalidate(cs)
			end
		end
	end
end

-- 내용이 차지하는 크기(패딩 포함)
local function contentExtent(st): (number, number)
	local ew, eh = 0, 0
	if st.info.members.TextBounds then
		local ti = textInfo(st)
		ew, eh = ti.w, ti.h
	end
	if st.layW then
		ew, eh = math.max(ew, st.layW), math.max(eh, st.layH)
	else
		for _, cs in guiChildren(st, {}) do
			if P(cs, "Visible") then
				ensure(cs)
				ew = math.max(ew, cs.ax + cs.aw - st.cx)
				eh = math.max(eh, cs.ay + cs.ah - st.cy)
			end
		end
	end
	return ew + st.padW, eh + st.padH
end

-- fx, fy = 배치가 정해 준 자리 · fw, fh = 배치가 정해 준 크기(없으면 제 Position · Size로)
local function computeChild(st, p, fx: number?, fy: number?, fw: number?, fh: number?)
	local w, h = baseSize(st, p)
	if fw then
		w, h = fw, fh :: number
	end
	local x, y
	if fx then
		x, y = fx, fy :: number
	else
		x, y = placeOf(st, p, w, h)
	end
	finish(st, x, y, w, h, p.asc, p.arot)
	local auto = st.props.AutomaticSize
	if auto and auto.Name ~= "None" and not fw then
		local ew, eh = contentExtent(st)
		local nw, nh = w, h
		if auto.Name ~= "Y" and ew > w then
			nw = ew
		end
		if auto.Name ~= "X" and eh > h then
			nh = eh
		end
		if nw ~= w or nh ~= h then
			if not fx then
				x, y = placeOf(st, p, nw, nh)
			end
			invalidate(st)
			finish(st, x, y, nw, nh, p.asc, p.arot)
		end
	end
	if st.class == "ScrollingFrame" then
		local acs = st.props.AutomaticCanvasSize
		if acs and acs.Name ~= "None" then
			local ew, eh = contentExtent(st)
			local nw = if acs.Name ~= "Y" then ew else nil
			local nh = if acs.Name ~= "X" then eh else nil
			if nw ~= st.autoCanvasW or nh ~= st.autoCanvasH then
				st.autoCanvasW, st.autoCanvasH = nw, nh
				invalidate(st)
				finish(st, st.ax, st.ay, st.aw, st.ah, p.asc, p.arot)
			end
		end
	end
end

local function computeLayer(st)
	local o = R.opts
	local x, y, w, h = 0, 0, 0, 0
	if st.class == "ScreenGui" then
		local full = P(st, "IgnoreGuiInset")
		x, y, w, h = 0, if full then -o.insetTop else 0, o.viewW, if full then o.viewH else o.viewH - o.insetTop
	end
	finish(st, x, y, w, h, 1, 0)
end

ensure = function(st)
	if st.lv == Layout.version then
		return
	end
	if st.info.isLayer then
		computeLayer(st)
		return
	end
	local p = guiParent(st)
	if p then
		ensure(p)
		if st.lv == Layout.version then
			return -- 부모가 (배치로) 이미 놓았다
		end
		computeChild(st, p)
	else
		computeChild(st, ZERO_PARENT)
	end
end
Layout.ensure = ensure

-- ---------- UIListLayout · UIGridLayout ----------
local function sortedItems(st, lay)
	local items = {}
	for _, cs in guiChildren(st, {}) do
		if P(cs, "Visible") then
			table.insert(items, cs)
		end
	end
	local order = P(lay, "SortOrder").Name
	if lay.props.SortOrder == nil and #items > 1 then
		R.note("sortorder", "UIListLayout/UIGridLayout의 SortOrder를 정하지 않았다 — Instance.new의 기본값은 Name(이름순)이라 아이들이 이름순으로 놓인다(LayoutOrder로 놓으려면 SortOrder = Enum.SortOrder.LayoutOrder)")
	end
	local idx = {}
	for i, cs in items do
		idx[cs] = i
	end
	if order == "LayoutOrder" then
		table.sort(items, function(a, b)
			local la, lb = P(a, "LayoutOrder"), P(b, "LayoutOrder")
			if la ~= lb then
				return la < lb
			end
			return idx[a] < idx[b]
		end)
	elseif order == "Name" then
		table.sort(items, function(a, b)
			if a.name ~= b.name then
				return a.name < b.name
			end
			return idx[a] < idx[b]
		end)
	end
	return items
end

local function setContentSize(lay, w: number, h: number)
	if lay.contentW ~= w or lay.contentH ~= h then
		lay.contentW, lay.contentH = w, h
		if lay.sig or lay.psig then
			noteContent(lay)
		end
	end
end

local function alignStart(name: string, origin: number, room: number, used: number): number
	if name == "Center" then
		return origin + (room - used) / 2
	elseif name == "Right" or name == "Bottom" then
		return origin + room - used
	end
	return origin
end

arrange = function(st, c, lay)
	local items = sortedItems(st, lay)
	local n = #items
	local s = st.asc
	local ha, va = P(lay, "HorizontalAlignment").Name, P(lay, "VerticalAlignment").Name
	local horizontal = P(lay, "FillDirection").Name == "Horizontal"
	if lay.class == "UIListLayout" then
		if P(lay, "Wraps") then
			R.note("UIListLayout.Wraps", "UIListLayout.Wraps(줄 바꿈)는 흉내 내지 않는다 — 한 줄로 놓는다")
		end
		local pad = P(lay, "Padding")
		local padPx = pad.Scale * (if horizontal then st.cw else st.ch) + pad.Offset * s
		local ws, hs = table.create(n), table.create(n)
		local total, cross = 0, 0
		for i, cs in items do
			local w, h = baseSize(cs, st)
			local auto = cs.props.AutomaticSize
			if auto and auto.Name ~= "None" then
				-- 내용에 맞춰 커지는 것: 한 번 놓아 보고 크기를 잰다
				computeChild(cs, st, st.cx, st.cy)
				w, h = cs.aw, cs.ah
				invalidate(cs)
				cs.lv = 0
			end
			ws[i], hs[i] = w, h
			if horizontal then
				total += w
				cross = math.max(cross, h)
			else
				total += h
				cross = math.max(cross, w)
			end
		end
		total += padPx * math.max(0, n - 1)
		local cur = if horizontal then alignStart(ha, st.cx, st.cw, total) else alignStart(va, st.cy, st.ch, total)
		for i, cs in items do
			local x, y
			if horizontal then
				x, y = cur, alignStart(va, st.cy, st.ch, hs[i])
				cur += ws[i] + padPx
			else
				x, y = alignStart(ha, st.cx, st.cw, ws[i]), cur
				cur += hs[i] + padPx
			end
			computeChild(cs, st, x, y)
		end
		if horizontal then
			st.layW, st.layH = total, cross
		else
			st.layW, st.layH = cross, total
		end
	else
		local cell, cpad = P(lay, "CellSize"), P(lay, "CellPadding")
		local cw, chh = cell[1] * st.cw + cell[2] * s, cell[3] * st.ch + cell[4] * s
		local px, py = cpad[1] * st.cw + cpad[2] * s, cpad[3] * st.ch + cpad[4] * s
		local maxCells = P(lay, "FillDirectionMaxCells")
		local perLine
		if horizontal then
			perLine = math.max(1, math.floor((st.cw + px + 0.001) / math.max(1e-6, cw + px)))
		else
			perLine = math.max(1, math.floor((st.ch + py + 0.001) / math.max(1e-6, chh + py)))
		end
		if maxCells > 0 then
			perLine = math.min(perLine, maxCells)
		end
		local lineCount = math.ceil(n / perLine)
		local cols = if horizontal then math.min(n, perLine) else lineCount
		local rows = if horizontal then lineCount else math.min(n, perLine)
		local totalW = cols * cw + math.max(0, cols - 1) * px
		local totalH = rows * chh + math.max(0, rows - 1) * py
		local x0 = alignStart(ha, st.cx, st.cw, totalW)
		local y0 = alignStart(va, st.cy, st.ch, totalH)
		local corner = P(lay, "StartCorner").Name
		local flipX = corner == "TopRight" or corner == "BottomRight"
		local flipY = corner == "BottomLeft" or corner == "BottomRight"
		for i, cs in items do
			local line, at = (i - 1) // perLine, (i - 1) % perLine
			local col, row = if horizontal then at else line, if horizontal then line else at
			if flipX then
				col = cols - 1 - col
			end
			if flipY then
				row = rows - 1 - row
			end
			computeChild(cs, st, x0 + col * (cw + px), y0 + row * (chh + py), cw, chh)
		end
		st.layW, st.layH = totalW, totalH
	end
	setContentSize(lay, st.layW, st.layH)
end

-- ---------- 읽는 속성 ----------
do
	local gb = Inst.hook("GuiBase2d")
	gb.get.AbsolutePosition = function(st)
		ensure(st)
		local v = V2(st.ax, st.ay)
		drain()
		return v
	end
	gb.get.AbsoluteSize = function(st)
		ensure(st)
		local v = V2(st.aw, st.ah)
		drain()
		return v
	end
	gb.get.AbsoluteRotation = function(st)
		ensure(st)
		local v = st.arot
		drain()
		return v
	end
	gb.init = function(st)
		st.ax, st.ay, st.aw, st.ah, st.arot, st.asc = 0, 0, 0, 0, 0, 1
		st.cx, st.cy, st.cw, st.ch = 0, 0, 0, 0
		st.padW, st.padH = 0, 0
	end
	local gl = Inst.hook("UIGridStyleLayout")
	gl.get.AbsoluteContentSize = function(st)
		local p = st.parent and rawget(st.parent, KEY)
		if p and p.info.isGui then
			ensure(p)
		end
		local v = V2(st.contentW or 0, st.contentH or 0)
		drain()
		return v
	end
	local sf = Inst.hook("ScrollingFrame")
	sf.get.AbsoluteCanvasSize = function(st)
		ensure(st)
		return V2(st.canvasW or st.aw, st.canvasH or st.ah)
	end
	sf.get.AbsoluteWindowSize = function(st)
		ensure(st)
		return V2(st.aw, st.ah)
	end
	for _, cls in { "TextLabel", "TextButton", "TextBox" } do
		local h = Inst.hook(cls)
		h.get.TextBounds = function(st)
			local ti = textInfo(st)
			drain()
			return V2(ti.w, ti.h)
		end
		h.get.TextFits = function(st)
			local fits = textInfo(st).fits
			drain()
			return fits
		end
		h.get.ContentText = function(st)
			local t = P(st, "Text")
			return if P(st, "RichText") then Layout.plainText(t) else t
		end
	end
end

-- ---------- 그리는 차례 · 누른 자리 ----------
local function intersect(clip, x0: number, y0: number, x1: number, y1: number)
	if clip then
		x0, y0 = math.max(x0, clip[1]), math.max(y0, clip[2])
		x1, y1 = math.min(x1, clip[3]), math.min(y1, clip[4])
	end
	return { x0, y0, x1, y1 }
end

local function visit(st, clip, list, sibling: boolean, rchain, alpha: number)
	if not P(st, "Visible") then
		return
	end
	ensure(st)
	local rot = st.props.Rotation
	if rot and rot ~= 0 then
		rchain = if rchain then table.clone(rchain) else {}
		table.insert(rchain, { st.ax + st.aw / 2, st.ay + st.ah / 2, rot })
	end
	table.insert(list, { st = st, clip = clip, rot = rchain, z = P(st, "ZIndex"), alpha = alpha })
	local childClip = clip
	if st.class == "CanvasGroup" then
		childClip = intersect(clip, st.ax, st.ay, st.ax + st.aw, st.ay + st.ah)
		alpha *= 1 - P(st, "GroupTransparency")
	elseif P(st, "ClipsDescendants") and not (rot and rot ~= 0) then
		childClip = intersect(clip, st.ax, st.ay, st.ax + st.aw, st.ay + st.ah)
	end
	local kids = guiChildren(st, {})
	local nk = #kids
	if nk == 0 then
		return
	end
	if sibling and nk > 1 then
		local z0 = P(kids[1], "ZIndex")
		local same = true
		for i = 2, nk do
			if P(kids[i], "ZIndex") ~= z0 then
				same = false
				break
			end
		end
		if not same then
			local idx = {}
			for i, k in kids do
				idx[k] = i
			end
			table.sort(kids, function(a, b)
				local za, zb = P(a, "ZIndex"), P(b, "ZIndex")
				if za ~= zb then
					return za < zb
				end
				return idx[a] < idx[b]
			end)
		end
	end
	for i = 1, nk do
		visit(kids[i], childClip, list, sibling, rchain, alpha)
	end
end

local function collectLayers(st, out)
	for _, ch in st.children do
		local cs = rawget(ch, KEY)
		if cs.info.isLayer then
			if cs.class == "ScreenGui" and P(cs, "Enabled") then
				table.insert(out, cs)
			end
		elseif cs.class == "Folder" then
			collectLayers(cs, out)
		end
	end
	return out
end

local cacheList, cacheVersion = nil, -1

-- 보이는 것을 아래 → 위 차례로: { st, clip = {x0,y0,x1,y1}?, rot = {{cx,cy,deg}…}?, z, alpha, layer }
function Layout.drawList()
	if cacheList and cacheVersion == Layout.version then
		return cacheList
	end
	local out = {}
	local pg = R.playerGui
	if pg then
		local layers = collectLayers(rawget(pg, KEY), {})
		local idx = {}
		for i, l in layers do
			idx[l] = i
		end
		table.sort(layers, function(a, b)
			local da, db = P(a, "DisplayOrder"), P(b, "DisplayOrder")
			if da ~= db then
				return da < db
			end
			return idx[a] < idx[b]
		end)
		for _, layer in layers do
			ensure(layer)
			local sibling = P(layer, "ZIndexBehavior").Name == "Sibling"
			local list = {}
			local kids = guiChildren(layer, {})
			if sibling and #kids > 1 then
				local kidx = {}
				for i, k in kids do
					kidx[k] = i
				end
				table.sort(kids, function(a, b)
					local za, zb = P(a, "ZIndex"), P(b, "ZIndex")
					if za ~= zb then
						return za < zb
					end
					return kidx[a] < kidx[b]
				end)
			end
			for _, k in kids do
				visit(k, nil, list, sibling, nil, 1)
			end
			if not sibling then
				local lidx = {}
				for i, e in list do
					lidx[e] = i
				end
				table.sort(list, function(a, b)
					if a.z ~= b.z then
						return a.z < b.z
					end
					return lidx[a] < lidx[b]
				end)
			end
			for _, e in list do
				e.layer = layer
				table.insert(out, e)
			end
		end
	end
	cacheList, cacheVersion = out, Layout.version
	drain()
	return out
end

-- 그 점(Absolute 좌표)에 있는 것들: 위 → 아래
function Layout.hitList(x: number, y: number)
	local list = Layout.drawList()
	local out = {}
	for i = #list, 1, -1 do
		local e = list[i]
		local st = e.st
		if x >= st.ax and x < st.ax + st.aw and y >= st.ay and y < st.ay + st.ah then
			local c = e.clip
			if not c or (x >= c[1] and x < c[3] and y >= c[2] and y < c[4]) then
				table.insert(out, e)
			end
		end
	end
	return out
end

-- 화면에 보이는가(조상이 모두 Visible · 화면 틀이 켜져 있고 PlayerGui 아래)
function Layout.isShown(st): boolean
	local cur = st
	while cur do
		if cur.info.isGuiObject then
			if not P(cur, "Visible") then
				return false
			end
		elseif cur.info.isLayer then
			if not P(cur, "Enabled") then
				return false
			end
			local pg = R.playerGui
			return pg ~= nil and Inst.isDescendantOf(cur.self, pg)
		end
		local p = cur.parent
		cur = if p then rawget(p, KEY) else nil
	end
	return false
end

-- 한 장의 끝: 모든 마디를 셈해 AbsoluteSize · AbsolutePosition 알림이 나가게 한다
local flushedVersion = -1
function Layout.flush()
	local guard = 0
	while flushedVersion ~= Layout.version and guard < 8 do
		guard += 1
		flushedVersion = Layout.version
		local pg = R.playerGui
		if pg then
			local function walk(st)
				if st.info.isGui then
					ensure(st)
				end
				for _, ch in st.children do
					local cs = rawget(ch, KEY)
					if cs.info.isGui or cs.class == "Folder" then
						walk(cs)
					end
				end
			end
			walk(rawget(pg, KEY))
		end
		drain()
		if Sched.depth == 0 then
			Sched.flush()
		end
	end
end

return Layout
