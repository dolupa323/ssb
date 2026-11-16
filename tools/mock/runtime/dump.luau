-- 화면 찍기: 보이는 화면 틀을 그리는 차례대로 JSON으로 적어 낸다(바깥의 shot.mjs가 HTML로 바꿔 Chrome으로 찍는다).
--  EditableImage의 점은 base64로 따로 한 번씩만 내보낸다.
local R = require("./rt")
R.mark()
local Types = require("./types")
local Inst = require("./inst")
local Layout = require("./layout")
local Sched = require("./sched")
local P = Layout.P

local Dump = {}
R.Dump = Dump

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64codes = table.create(64, 0)
for i = 1, 64 do
	b64codes[i] = string.byte(B64, i)
end
local function base64(buf: buffer, len: number): string
	local outLen = ((len + 2) // 3) * 4
	local out = buffer.create(outLen)
	local o = 0
	local i = 0
	while i + 2 < len do
		local a, b, c = buffer.readu8(buf, i), buffer.readu8(buf, i + 1), buffer.readu8(buf, i + 2)
		buffer.writeu8(out, o, b64codes[bit32.rshift(a, 2) + 1])
		buffer.writeu8(out, o + 1, b64codes[bit32.bor(bit32.lshift(bit32.band(a, 3), 4), bit32.rshift(b, 4)) + 1])
		buffer.writeu8(out, o + 2, b64codes[bit32.bor(bit32.lshift(bit32.band(b, 15), 2), bit32.rshift(c, 6)) + 1])
		buffer.writeu8(out, o + 3, b64codes[bit32.band(c, 63) + 1])
		i += 3
		o += 4
	end
	local rest = len - i
	if rest == 1 then
		local a = buffer.readu8(buf, i)
		buffer.writeu8(out, o, b64codes[bit32.rshift(a, 2) + 1])
		buffer.writeu8(out, o + 1, b64codes[bit32.lshift(bit32.band(a, 3), 4) + 1])
		buffer.writeu8(out, o + 2, 61)
		buffer.writeu8(out, o + 3, 61)
	elseif rest == 2 then
		local a, b = buffer.readu8(buf, i), buffer.readu8(buf, i + 1)
		buffer.writeu8(out, o, b64codes[bit32.rshift(a, 2) + 1])
		buffer.writeu8(out, o + 1, b64codes[bit32.bor(bit32.lshift(bit32.band(a, 3), 4), bit32.rshift(b, 4)) + 1])
		buffer.writeu8(out, o + 2, b64codes[bit32.lshift(bit32.band(b, 15), 2) + 1])
		buffer.writeu8(out, o + 3, 61)
	end
	return buffer.tostring(out)
end

local function rgb(c: any)
	return { math.clamp(math.floor(c.R * 255 + 0.5), 0, 255), math.clamp(math.floor(c.G * 255 + 0.5), 0, 255), math.clamp(math.floor(c.B * 255 + 0.5), 0, 255) }
end
local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local sentImages = {} :: { [number]: number } -- 그림판 번호 → 내보낸 판 번호

local function imageSource(st, item)
	local content = P(st, "ImageContent")
	local kind = content.SourceType.Name
	if kind == "Object" then
		local obj = content.Object
		local os = Inst.st(obj)
		if os.class ~= "EditableImage" or not os.buf then
			return nil
		end
		if sentImages[os.id] ~= os.ver then
			sentImages[os.id] = os.ver
			R.emit("img", { id = os.id, ver = os.ver, w = os.w, h = os.h, b64 = base64(os.buf, os.w * os.h * 4) })
		end
		item.ei = os.id
		item.ver = os.ver
		item.iw, item.ih = os.w, os.h
		return true
	elseif kind == "Uri" then
		item.src = content.Uri
		return true
	end
	return nil
end

local function fontOf(st)
	local f = P(st, "FontFace")
	return { fam = f.Family, weight = f.Weight.Value, italic = f.Style.Name == "Italic" }
end

local function describeItem(e, top: number)
	local st = e.st
	local c = Layout.comps(st)
	local item: any = {
		n = st.name,
		c = st.class,
		id = st.id,
		x = r2(st.ax),
		y = r2(st.ay + top),
		w = r2(st.aw),
		h = r2(st.ah),
		z = e.z,
	}
	if e.clip then
		item.clip = { r2(e.clip[1]), r2(e.clip[2] + top), r2(e.clip[3]), r2(e.clip[4] + top) }
	end
	if e.rot then
		local chain = {}
		for _, r in e.rot do
			table.insert(chain, { r2(r[1]), r2(r[2] + top), r[3] })
		end
		item.rot = chain
	end
	if e.alpha ~= 1 then
		item.a = e.alpha
	end
	local bt = P(st, "BackgroundTransparency")
	if st.class == "CanvasGroup" then
		bt = 1 - (1 - bt) * (1 - P(st, "GroupTransparency"))
	end
	if bt < 1 then
		item.bg = rgb(P(st, "BackgroundColor3"))
		item.bt = bt
	end
	local bs = P(st, "BorderSizePixel")
	if bs > 0 and bt < 1 then
		item.bs = bs
		item.bc = rgb(P(st, "BorderColor3"))
		item.bm = P(st, "BorderMode").Name
	end
	local corner = c.UICorner
	if corner then
		local cr = P(corner, "CornerRadius")
		item.cr = r2(cr.Scale * math.min(st.aw, st.ah) + cr.Offset * st.asc)
	end
	local isText = st.info.members.TextBounds ~= nil
	local stroke = c.UIStroke
	if stroke and P(stroke, "Enabled") then
		local mode = P(stroke, "ApplyStrokeMode").Name
		local s: any = { c = rgb(P(stroke, "Color")), t = r2(P(stroke, "Thickness") * st.asc), tr = P(stroke, "Transparency"), join = P(stroke, "LineJoinMode").Name }
		s.text = isText and mode == "Contextual"
		item.st = s
	end
	local grad = c.UIGradient
	if grad and P(grad, "Enabled") then
		local cs, ts = {}, {}
		for _, k in P(grad, "Color").Keypoints do
			local col = rgb(k.Value)
			table.insert(cs, { k.Time, col[1], col[2], col[3] })
		end
		for _, k in P(grad, "Transparency").Keypoints do
			table.insert(ts, { k.Time, k.Value })
		end
		local off = P(grad, "Offset")
		item.gr = { rot = P(grad, "Rotation"), off = { off.X, off.Y }, cs = cs, ts = ts }
	end
	if st.info.members.ImageRectOffset then
		local img: any = {}
		if imageSource(st, img) then
			local ro, rs = P(st, "ImageRectOffset"), P(st, "ImageRectSize")
			img.rx, img.ry, img.rw, img.rh = ro.X, ro.Y, rs.X, rs.Y
			img.col = rgb(P(st, "ImageColor3"))
			img.tr = P(st, "ImageTransparency")
			img.scale = P(st, "ScaleType").Name
			img.resample = P(st, "ResampleMode").Name
			if img.scale == "Slice" then
				local sc = P(st, "SliceCenter")
				img.slice = { sc.Min.X, sc.Min.Y, sc.Max.X, sc.Max.Y }
				img.sliceScale = P(st, "SliceScale") * st.asc
			elseif img.scale == "Tile" then
				local ts = P(st, "TileSize")
				img.tile = { r2(ts[1] * st.aw + ts[2] * st.asc), r2(ts[3] * st.ah + ts[4] * st.asc) }
			end
			if img.tr < 1 then
				item.img = img
			end
		end
	end
	if isText then
		local text = P(st, "Text")
		local placeholder = false
		if text == "" and st.class == "TextBox" then
			text = P(st, "PlaceholderText")
			placeholder = true
		end
		local tt = P(st, "TextTransparency")
		if text ~= "" and tt < 1 then
			local ti = Layout.textInfo(st)
			local t: any = {
				s = text,
				size = r2(ti.size),
				col = rgb(if placeholder then P(st, "PlaceholderColor3") else P(st, "TextColor3")),
				tr = tt,
				ax = P(st, "TextXAlignment").Name,
				ay = P(st, "TextYAlignment").Name,
				wrap = P(st, "TextWrapped") or P(st, "TextScaled"),
				rich = P(st, "RichText"),
				font = fontOf(st),
				lh = P(st, "LineHeight"),
				trunc = P(st, "TextTruncate").Name,
				bw = r2(ti.w),
				bh = r2(ti.h),
			}
			local sTr = P(st, "TextStrokeTransparency")
			if sTr < 1 then
				t.sc = rgb(P(st, "TextStrokeColor3"))
				t.str = sTr
			end
			item.txt = t
		end
	end
	return item
end

-- 지금 화면을 적은 표(화면 좌표 — 왼쪽 위가 0, 0)
function Dump.capture()
	Layout.flush()
	local top = R.opts.insetTop
	local items = {}
	for _, e in Layout.drawList() do
		table.insert(items, describeItem(e, top))
	end
	return { w = R.opts.viewW, h = R.opts.viewH, inset = top, time = Sched.now, frame = Sched.frame, items = items }
end

function Dump.shot(file: string)
	local data = Dump.capture()
	data.file = file
	R.emit("shot", data)
end

-- 화면 나무를 글로(사람이 읽는 용)
function Dump.tree(root: any, maxDepth: number?): string
	local out = {}
	local function walk(inst, depth: number)
		local st = Inst.st(inst)
		local line = string.rep("  ", depth) .. st.class .. ' "' .. st.name .. '"'
		if st.info.isGui then
			Layout.ensure(st)
			line ..= string.format(" [%g,%g %gx%g]", r2(st.ax), r2(st.ay), r2(st.aw), r2(st.ah))
			if st.info.isGuiObject then
				if not P(st, "Visible") then
					line ..= " 숨김"
				end
				local z = P(st, "ZIndex")
				if z ~= 1 then
					line ..= " z=" .. z
				end
				if P(st, "ClipsDescendants") then
					line ..= " 자름"
				end
			end
			if st.info.members.TextBounds then
				local t = P(st, "Text")
				local len = utf8.len(t)
				if len and len > 24 then
					t = string.sub(t, 1, (utf8.offset(t, 25) :: number) - 1) .. "…"
				elseif not len and #t > 30 then
					t = string.sub(t, 1, 30) .. "…"
				end
				line ..= ' 글="' .. string.gsub(t, "\n", "\\n") .. '" 크기=' .. tostring(P(st, "TextSize"))
			end
			if st.info.members.ImageRectOffset then
				local content = P(st, "ImageContent")
				local kind = content.SourceType.Name
				line ..= " 그림=" .. (if kind == "Uri" then content.Uri elseif kind == "Object" then "EditableImage" else "(없음)")
				local rs = P(st, "ImageRectSize")
				if rs.X ~= 0 or rs.Y ~= 0 then
					line ..= " 자르기=(" .. tostring(P(st, "ImageRectOffset")) .. " / " .. tostring(rs) .. ")"
				end
			end
		elseif st.class == "UIScale" then
			line ..= " x" .. tostring(P(st, "Scale"))
		end
		table.insert(out, line)
		if maxDepth and depth >= maxDepth then
			return
		end
		for _, ch in st.children do
			walk(ch, depth + 1)
		end
	end
	walk(root, 0)
	Layout.drain()
	return table.concat(out, "\n")
end

return Dump
