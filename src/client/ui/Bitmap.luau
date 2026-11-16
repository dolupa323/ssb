--!strict
-- 구운 글자로 글을 그린다. 원본의 웹 글꼴 Do Hyeon(제목 · 이름) · VT323(전광판 숫자)은 Roblox에 없어서,
--  진짜 글꼴 파일을 그림 판으로 구워(tools/font/bake.mjs → shared/font) 글자마다 ImageLabel로 놓는다.
--  쓰는 법: 보통의 TextLabel(주인)에 Bitmap.attach를 걸면, 그 꼬리표의 Text · TextColor3 · 정렬을 따라 글자 그림이 그려진다.
--   주인의 진짜 글은 투명하게 숨긴다(TextTransparency = 1) — 흐리기는 Bitmap.setAlpha로 한다.
--   판에 없는 글자가 섞인 글은 그 꼬리표만 보통 글꼴로 되돌아간다.
--  판은 그림 판과 같은 방식으로 만든다: shared/art/AssetIds에 판 이름(font_dh_s …)의 에셋 번호가 있으면 그것, 없으면 코드에 실린 점 자료를 풀어 EditableImage로.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bitmap = {}
Bitmap.ready = false
Bitmap.failed = {} :: { string }

type Glyph = { number } -- { page, x, y, w, h, ox, oy, adv }
type Face = { em: number, asc: number, desc: number, pages: { any }, glyphs: { [number]: Glyph }, content: { [number]: any }, image: { [number]: string } }
export type Opts = { ls: number?, lh: number?, shadow: number?, shadowColor: Color3? }
type State = {
	host: TextLabel,
	kind: string, -- "display" | "led"
	fs: number, -- 글씨 크기(CSS px)
	ls: number, -- 글자 사이(em)
	lh: number?, -- 줄 높이(배수). 없으면 글꼴의 줄 높이
	alpha: number,
	shadow: number?,
	shadowColor: Color3,
	box: Frame,
	imgs: { ImageLabel },
	shades: { ImageLabel },
	cache: { { any } }, -- 칸마다 { 판, 글자 코드, x, y, 배율 }
	used: number,
	bitmap: boolean, -- 지금 구운 글자로 그리고 있는가(아니면 보통 글꼴)
}

local faces = {} :: { [string]: Face }
local states = setmetatable({}, { __mode = "k" }) :: any
local starting = false
-- 얼굴마다의 판: 작은 글씨용 · 큰 글씨용(있으면)
local PICK = { display = { small = "dh_s", large = "dh_l", from = 30 }, led = { small = "vt" } } :: { [string]: any }

-- 판을 만든다(기다린다). 두 번 불러도 한 번만
function Bitmap.init()
	if Bitmap.ready or starting then
		while not Bitmap.ready do
			task.wait()
		end
		return
	end
	starting = true
	local shared = ReplicatedStorage:WaitForChild("shared")
	local folder = shared:FindFirstChild("font")
	if not folder then
		warn("[ssb] 구운 글자(shared/font)가 없다 — 보통 글꼴로 그린다")
		Bitmap.ready = true
		return
	end
	local okA, atlas = pcall(require, folder:WaitForChild("FontAtlas"))
	if not okA or type(atlas) ~= "table" then
		warn("[ssb] 글자 치수 표를 읽지 못했다 — 보통 글꼴로 그린다: " .. tostring(atlas))
		Bitmap.ready = true
		return
	end
	local ids = {} :: { [string]: any }
	local art = shared:FindFirstChild("art")
	local idModule = art and art:FindFirstChild("AssetIds")
	if idModule and idModule:IsA("ModuleScript") then
		local ok, res = pcall(require, idModule)
		if ok and type(res) == "table" then
			ids = res
		end
	end
	local Decode = require((art :: Instance):WaitForChild("Decode")) :: any
	local pixels = folder:FindFirstChild("pixels")
	local function get(name: string)
		return require((pixels :: Instance):WaitForChild(name) :: ModuleScript)
	end
	for name, f in atlas.faces do
		local face: Face = { em = f.em, asc = f.asc, desc = f.desc, pages = f.pages, glyphs = f.glyphs, content = {}, image = {} }
		local good = true
		for i, page in f.pages do
			local id = ids[page.name]
			if type(id) == "number" then
				id = "rbxassetid://" .. id
			end
			if type(id) == "string" and id ~= "" then
				face.image[i] = id
			elseif pixels then
				local ok, err = pcall(function()
					local buf, w, h = Decode.load(get, page.name)
					local img = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
					img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
					face.content[i] = Content.fromObject(img)
				end)
				if not ok then
					good = false
					table.insert(Bitmap.failed, page.name)
					warn(("[ssb] 글자 판 %s를 만들지 못했다: %s"):format(page.name, tostring(err)))
				end
				task.wait()
			else
				good = false
			end
		end
		if good then
			faces[name] = face
		end
	end
	Bitmap.ready = true
end

-- 그 글을 그 크기로 그릴 판을 고른다(글자가 하나라도 없으면 nil)
local function faceFor(kind: string, fs: number, text: string): Face?
	local pick = PICK[kind]
	if not pick then
		return nil
	end
	local function covers(f: Face?): boolean
		if not f then
			return false
		end
		for _, c in utf8.codes(text) do
			if c ~= 10 and not f.glyphs[c] then
				return false
			end
		end
		return true
	end
	if pick.large and fs > pick.from and covers(faces[pick.large]) then
		return faces[pick.large]
	end
	local small = faces[pick.small]
	if covers(small) then
		return small
	end
	return nil
end

-- 한 줄의 폭(px)
local function lineWidth(f: Face, line: string, fs: number, ls: number): number
	local k = fs / f.em
	local w = 0
	for _, c in utf8.codes(line) do
		w += f.glyphs[c][8] * k + ls * fs
	end
	return w
end

-- 글의 크기(px): 가장 긴 줄의 폭, 줄 수 x 줄 높이. 구운 글자로 못 그리는 글이면 nil
function Bitmap.measure(kind: string, text: string, fs: number, ls: number?, lh: number?): (number?, number?)
	local f = faceFor(kind, fs, text)
	if not f then
		return nil, nil
	end
	local w, n = 0, 0
	for _, line in string.split(text, "\n") do
		n += 1
		w = math.max(w, lineWidth(f, line, fs, ls or 0))
	end
	local pitch = if lh then lh * fs else (f.asc + f.desc) * fs / f.em
	return w, n * pitch
end

function Bitmap.is(host: Instance): boolean
	return states[host] ~= nil
end

-- 주인 꼬리표의 지금 글의 크기. 구운 글자로 그리고 있지 않으면 nil
function Bitmap.size(host: Instance, text: string?): (number?, number?)
	local st = states[host] :: State?
	if not st then
		return nil, nil
	end
	return Bitmap.measure(st.kind, text or st.host.Text, st.fs, st.ls, st.lh)
end

local function newImg(parent: Instance, z: number): ImageLabel
	local im = Instance.new("ImageLabel")
	im.Name = "g"
	im.BackgroundTransparency = 1
	im.BorderSizePixel = 0
	im.ZIndex = z
	im:SetAttribute("G", true)
	im.Parent = parent
	return im
end

local function setPage(im: ImageLabel, f: Face, page: number)
	local id = f.image[page]
	if id then
		im.Image = id
	else
		im.ImageContent = f.content[page]
	end
end

local function paint(st: State)
	local host = st.host
	local color = host.TextColor3
	local tr = 1 - st.alpha
	for _, im in st.imgs do
		im.ImageColor3 = color
		im.ImageTransparency = tr
	end
	if st.shadow then
		local str = 1 - st.alpha * st.shadow
		for i = 1, #st.imgs do
			local sh = st.shades[i]
			sh.ImageColor3 = st.shadowColor
			sh.ImageTransparency = str
		end
	end
	if not st.bitmap then
		host.TextTransparency = tr
	end
end

local function render(st: State)
	local host = st.host
	local text = host.Text
	local f = faceFor(st.kind, st.fs, text)
	if not f then
		-- 판에 없는 글자가 있다: 이 꼬리표는 보통 글꼴로
		st.bitmap = false
		st.box.Visible = false
		host.TextTransparency = 1 - st.alpha
		return
	end
	st.bitmap = true
	st.box.Visible = true
	host.TextTransparency = 1
	local fs, k = st.fs, st.fs / f.em
	local lines = string.split(text, "\n")
	local pitch = if st.lh then st.lh * fs else (f.asc + f.desc) * k
	local widths = {}
	local maxW = 0
	for i, line in lines do
		widths[i] = lineWidth(f, line, fs, st.ls)
		maxW = math.max(maxW, widths[i])
	end
	local ax = if host.TextXAlignment == Enum.TextXAlignment.Left then 0 elseif host.TextXAlignment == Enum.TextXAlignment.Right then 1 else 0.5
	local ay = if host.TextYAlignment == Enum.TextYAlignment.Top then 0 elseif host.TextYAlignment == Enum.TextYAlignment.Bottom then 1 else 0.5
	local box = st.box
	box.AnchorPoint = Vector2.new(ax, ay)
	box.Position = UDim2.fromScale(ax, ay)
	box.Size = UDim2.fromOffset(maxW, #lines * pitch)
	local base = (pitch - (f.asc + f.desc) * k) / 2 + f.asc * k -- 줄 안에서 밑줄의 높이
	local n = 0
	local color, tr = host.TextColor3, 1 - st.alpha
	for li, line in lines do
		local pen = (maxW - widths[li]) * ax
		local top = (li - 1) * pitch + base
		for _, c in utf8.codes(line) do
			local g = f.glyphs[c]
			if g[4] > 0 then
				n += 1
				local im = st.imgs[n]
				if not im then
					im = newImg(box, 2)
					st.imgs[n] = im
					st.cache[n] = {}
					im.ImageColor3 = color
					im.ImageTransparency = tr
					if st.shadow then
						local sh = newImg(box, 1)
						sh.ImageColor3 = st.shadowColor
						sh.ImageTransparency = 1 - st.alpha * st.shadow
						st.shades[n] = sh
					end
				end
				local ca = st.cache[n]
				local x, y = pen + g[6] * k, top + g[7] * k
				if ca[1] ~= f or ca[2] ~= c or ca[5] ~= k then
					if ca[1] ~= f or ca[6] ~= g[1] then
						setPage(im, f, g[1])
						if st.shadow then
							setPage(st.shades[n], f, g[1])
						end
					end
					local ro, rs = Vector2.new(g[2], g[3]), Vector2.new(g[4], g[5])
					local size = UDim2.fromOffset(g[4] * k, g[5] * k)
					im.ImageRectOffset, im.ImageRectSize, im.Size = ro, rs, size
					if st.shadow then
						local sh = st.shades[n]
						sh.ImageRectOffset, sh.ImageRectSize, sh.Size = ro, rs, size
					end
					ca[1], ca[2], ca[5], ca[6] = f, c, k, g[1]
				end
				if ca[3] ~= x or ca[4] ~= y then
					im.Position = UDim2.fromOffset(x, y)
					if st.shadow then
						st.shades[n].Position = UDim2.fromOffset(x, y + 1)
					end
					ca[3], ca[4] = x, y
				end
				if n > st.used then
					im.Visible = true
					if st.shadow then
						st.shades[n].Visible = true
					end
				end
			end
			pen += g[8] * k + st.ls * fs
		end
	end
	for i = n + 1, st.used do
		st.imgs[i].Visible = false
		if st.shadow then
			st.shades[i].Visible = false
		end
	end
	st.used = n
end

-- TextLabel을 구운 글자로 그리게 한다. kind = "display"(Do Hyeon) | "led"(VT323), fs = 글씨 크기(CSS px)
function Bitmap.attach(host: TextLabel, kind: string, fs: number, opts: Opts?): boolean
	if not Bitmap.ready or not PICK[kind] or not faces[PICK[kind].small] then
		return false
	end
	local o: Opts = opts or {}
	local box = Instance.new("Frame")
	box.Name = "glyphs"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box:SetAttribute("G", true)
	box.Parent = host
	local st: State = {
		host = host,
		kind = kind,
		fs = fs,
		ls = o.ls or 0,
		lh = o.lh,
		alpha = 1 - host.TextTransparency,
		shadow = o.shadow,
		shadowColor = o.shadowColor or Color3.new(0, 0, 0),
		box = box,
		imgs = {},
		shades = {},
		cache = {},
		used = 0,
		bitmap = true,
	}
	states[host] = st
	render(st)
	host:GetPropertyChangedSignal("Text"):Connect(function()
		render(st)
	end)
	host:GetPropertyChangedSignal("TextColor3"):Connect(function()
		paint(st)
	end)
	host:GetPropertyChangedSignal("TextXAlignment"):Connect(function()
		render(st)
	end)
	return true
end

-- 흐리기(0..1). 주인의 TextTransparency 대신 이것을 쓴다
function Bitmap.setAlpha(host: Instance, alpha: number)
	local st = states[host] :: State?
	if st and st.alpha ~= alpha then
		st.alpha = alpha
		paint(st)
	end
end

function Bitmap.alpha(host: Instance): number
	local st = states[host] :: State?
	return if st then st.alpha else 1
end

-- 글씨 크기를 바꾼다
function Bitmap.setSize(host: Instance, fs: number)
	local st = states[host] :: State?
	if st and st.fs ~= fs then
		st.fs = fs
		render(st)
	end
end

return Bitmap
