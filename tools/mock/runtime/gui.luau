-- 화면 클래스의 나머지 동작: 그림 · 글꼴 속성의 짝 맞추기, EditableImage, 흉내 내지 않는 클래스 알림.
local R = require("./rt")
R.mark()
local Types = require("./types")
local Inst = require("./inst")
local raise = R.raise
local V2 = Types.V2

local Gui = {}
R.Gui = Gui

-- ---------- Image ↔ ImageContent ----------
for _, cls in { "ImageLabel", "ImageButton" } do
	local h = Inst.hook(cls)
	h.after.Image = function(st, _, value)
		st.props.ImageContent = if value == "" then Types.Content.none else Types.Content.fromUri(value)
	end
	h.after.ImageContent = function(st, _, value)
		st.props.Image = value.Uri or ""
	end
	h.get.IsLoaded = function()
		return true
	end
end

-- ---------- Font ↔ FontFace ----------
for _, cls in { "TextLabel", "TextButton", "TextBox" } do
	local h = Inst.hook(cls)
	h.after.Font = function(st, _, value)
		st.props.FontFace = Types.Font.fromEnum(value)
		R.Layout.bump()
	end
	h.after.FontFace = function(st, _, value)
		st.props.Font = Types.fontToEnum(value)
	end
end

-- ---------- ScreenGui: IgnoreGuiInset ↔ ScreenInsets ----------
do
	local h = Inst.hook("ScreenGui")
	h.after.IgnoreGuiInset = function(st, _, value)
		st.props.ScreenInsets = Types.enumItem("ScreenInsets", if value then "DeviceSafeInsets" else "CoreUISafeInsets")
	end
	h.after.ScreenInsets = function(st, _, value)
		st.props.IgnoreGuiInset = value.Name ~= "CoreUISafeInsets"
	end
end

-- ---------- EditableImage ----------
do
	local h = Inst.hook("EditableImage")
	h.init = function(st)
		st.w, st.h, st.ver = 0, 0, 0
		st.buf = false
	end
	h.get.Size = function(st)
		return V2(st.w, st.h)
	end
	local function alive(st, what: string)
		if not st.buf then
			raise("EditableImage:" .. what .. ": 이미 Destroy된 그림판이다")
		end
	end
	local function region(st, what: string, pos, size): (number, number, number, number)
		local x, y, w, h2 = pos.X, pos.Y, size.X, size.Y
		if x % 1 ~= 0 or y % 1 ~= 0 or w % 1 ~= 0 or h2 % 1 ~= 0 then
			raise("EditableImage:" .. what .. ": 자리 · 크기는 정수여야 한다 (자리 " .. tostring(pos) .. " · 크기 " .. tostring(size) .. ")")
		end
		if w <= 0 or h2 <= 0 or x < 0 or y < 0 or x + w > st.w or y + h2 > st.h then
			raise("EditableImage:" .. what .. ": 네모(자리 " .. tostring(pos) .. " · 크기 " .. tostring(size) .. ")가 그림판(" .. st.w .. "x" .. st.h .. ") 밖으로 나간다")
		end
		return x, y, w, h2
	end
	h.methods.WritePixelsBuffer = function(st, _, pos, size, buf)
		alive(st, "WritePixelsBuffer")
		local x, y, w, h2 = region(st, "WritePixelsBuffer", pos, size)
		local need = w * h2 * 4
		if buffer.len(buf) ~= need then
			raise("EditableImage:WritePixelsBuffer: 버퍼의 길이가 " .. buffer.len(buf) .. "바이트다 — 크기 " .. tostring(size) .. "에는 " .. need .. "바이트(폭 x 높이 x 4)가 맞다")
		end
		if x == 0 and w == st.w then
			buffer.copy(st.buf, y * st.w * 4, buf, 0, need)
		else
			for row = 0, h2 - 1 do
				buffer.copy(st.buf, ((y + row) * st.w + x) * 4, buf, row * w * 4, w * 4)
			end
		end
		st.ver += 1
	end
	h.methods.ReadPixelsBuffer = function(st, _, pos, size)
		alive(st, "ReadPixelsBuffer")
		local x, y, w, h2 = region(st, "ReadPixelsBuffer", pos, size)
		local out = buffer.create(w * h2 * 4)
		for row = 0, h2 - 1 do
			buffer.copy(out, row * w * 4, st.buf, ((y + row) * st.w + x) * 4, w * 4)
		end
		return out
	end
	h.methods.DrawRectangle = function(st, _, pos, size, color, transparency, combine)
		alive(st, "DrawRectangle")
		local x0, y0 = math.max(0, math.floor(pos.X)), math.max(0, math.floor(pos.Y))
		local x1, y1 = math.min(st.w, math.floor(pos.X + size.X)), math.min(st.h, math.floor(pos.Y + size.Y))
		local r, g, b = math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)
		local a = math.clamp(math.floor((1 - transparency) * 255 + 0.5), 0, 255)
		local blend = combine.Name ~= "Overwrite"
		local buf = st.buf
		for yy = y0, y1 - 1 do
			for xx = x0, x1 - 1 do
				local i = (yy * st.w + xx) * 4
				if blend and a < 255 then
					local da = buffer.readu8(buf, i + 3)
					local rest = da * (255 - a) / 255
					local oa = a + rest
					if oa > 0 then
						buffer.writeu8(buf, i, math.floor((r * a + buffer.readu8(buf, i) * rest) / oa + 0.5))
						buffer.writeu8(buf, i + 1, math.floor((g * a + buffer.readu8(buf, i + 1) * rest) / oa + 0.5))
						buffer.writeu8(buf, i + 2, math.floor((b * a + buffer.readu8(buf, i + 2) * rest) / oa + 0.5))
						buffer.writeu8(buf, i + 3, math.floor(oa + 0.5))
					end
				else
					buffer.writeu8(buf, i, r)
					buffer.writeu8(buf, i + 1, g)
					buffer.writeu8(buf, i + 2, b)
					buffer.writeu8(buf, i + 3, a)
				end
			end
		end
		st.ver += 1
	end
	h.methods.DrawImage = function(st, _, pos, image, combine)
		alive(st, "DrawImage")
		local src = Inst.st(image)
		if not src.buf then
			raise("EditableImage:DrawImage: 그릴 그림이 이미 Destroy되었다")
		end
		local blend = combine.Name ~= "Overwrite"
		local ox, oy = math.floor(pos.X), math.floor(pos.Y)
		local buf, sbuf = st.buf, src.buf
		for sy = 0, src.h - 1 do
			local dy = oy + sy
			if dy >= 0 and dy < st.h then
				for sx = 0, src.w - 1 do
					local dx = ox + sx
					if dx >= 0 and dx < st.w then
						local si, di = (sy * src.w + sx) * 4, (dy * st.w + dx) * 4
						local a = buffer.readu8(sbuf, si + 3)
						if not blend or a == 255 then
							buffer.writeu32(buf, di, buffer.readu32(sbuf, si))
						elseif a > 0 then
							local da = buffer.readu8(buf, di + 3)
							local rest = da * (255 - a) / 255
							local oa = a + rest
							for c = 0, 2 do
								buffer.writeu8(buf, di + c, math.floor((buffer.readu8(sbuf, si + c) * a + buffer.readu8(buf, di + c) * rest) / oa + 0.5))
							end
							buffer.writeu8(buf, di + 3, math.floor(oa + 0.5))
						end
					end
				end
			end
		end
		st.ver += 1
	end
	h.methods.Destroy = function(st)
		st.buf = false
	end
end

function Gui.newEditableImage(w: number, h: number)
	local inst = Inst.create("EditableImage")
	local st = Inst.st(inst)
	st.w, st.h = w, h
	st.buf = buffer.create(w * h * 4)
	return inst
end

-- ---------- 흉내 내지 않는 화면 클래스 ----------
local INERT = {
	UIPageLayout = "UIPageLayout(쪽 넘김 배치)",
	UITableLayout = "UITableLayout(표 배치)",
	UIFlexItem = "UIFlexItem(늘어나는 칸)",
	UIDragDetector = "UIDragDetector(끌기)",
	ViewportFrame = "ViewportFrame(3D 미리보기) — 빈 네모로 그린다",
	VideoFrame = "VideoFrame(영상) — 빈 네모로 그린다",
	BillboardGui = "BillboardGui(3D 공간의 화면 틀) — 그리지 않는다",
	SurfaceGui = "SurfaceGui(면에 붙는 화면 틀) — 그리지 않는다",
	Path2D = "Path2D(곡선)",
}
R.onCreate = function(_, className: string)
	local what = INERT[className]
	if what then
		R.note("inert:" .. className, what .. " 는 mock이 흉내 내지 않는다(만들 수는 있지만 화면 · 자리에 아무 영향이 없다)")
	end
end

return Gui
