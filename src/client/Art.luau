--!strict
-- 구운 그림 판(아틀라스)을 게임에서 쓰게 해 주는 모듈.
--  · AssetIds 모듈(src/shared/art/AssetIds.luau)에 판의 에셋 번호가 있으면 그것을 쓰고,
--    없으면 코드에 실린 점 자료를 풀어 EditableImage로 만든다.
--  · 원본에 없는 도움 그림(prim/grad · prim/soft… · prim/ring…)은 여기서 셈으로 그려 판 하나를 더 만든다.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("shared")
local artFolder = shared:WaitForChild("art")
local Atlas = require(artFolder:WaitForChild("Atlas")) :: any
local Decode = require(artFolder:WaitForChild("Decode")) :: any

export type Info = { page: number, x: number, y: number, w: number, h: number, ox: number, oy: number, s: number }

local Art = {}
Art.ready = false
Art.failed = {} :: { string } -- 만들지 못한 판의 이름
Art.atlas = Atlas

local sprites = Atlas.sprites :: { [string]: Info }
local extra = {} :: { [string]: Info } -- 셈으로 그린 도움 그림
local pageContent = {} :: { [number]: any } -- Content (EditableImage)
local pageImage = {} :: { [number]: string } -- "rbxassetid://…"
local starting = false

-- ---------- 셈으로 그리는 도움 그림 판 ----------
local PRIM_W, PRIM_H = 280, 168
local PRIM_PAGE = #Atlas.pages + 1
local function buildPrims(): buffer
	local buf = buffer.create(PRIM_W * PRIM_H * 4)
	-- (x, y)부터 w×h에 fn(u, v) → 알파, r, g, b(없으면 흰색)를 쓴다. 바깥 2점에는 가장자리 값을 덧댄다(늘일 때 옆 그림이 비치지 않게)
	local function put(name: string, x: number, y: number, w: number, h: number, s: number, fn: (number, number) -> (number, number?, number?, number?), ox: number?, oy: number?)
		for py = -2, h + 1 do
			local v = (math.clamp(py, 0, h - 1) + 0.5) / h
			for px = -2, w + 1 do
				local u = (math.clamp(px, 0, w - 1) + 0.5) / w
				local a, r, g, b = fn(u, v)
				a = math.clamp(a, 0, 1)
				local o = ((y + py) * PRIM_W + (x + px)) * 4
				buffer.writeu8(buf, o, math.floor((r or 1) * 255 + 0.5))
				buffer.writeu8(buf, o + 1, math.floor((g or 1) * 255 + 0.5))
				buffer.writeu8(buf, o + 2, math.floor((b or 1) * 255 + 0.5))
				buffer.writeu8(buf, o + 3, math.floor(a * 255 + 0.5))
			end
		end
		extra[name] = { page = PRIM_PAGE, x = x, y = y, w = w, h = h, ox = ox or w / s / 2, oy = oy or h / s / 2, s = s }
	end
	local function ring(r: number, lw: number)
		return function(u: number, v: number): number
			local d = math.sqrt((u - 0.5) ^ 2 + (v - 0.5) ^ 2) * 96
			return lw / 2 + 0.5 - math.abs(d - r)
		end
	end
	local function soft(v: number): number
		local t = 1 - math.abs(v - 0.5) * 2
		return t * t * (3 - 2 * t)
	end
	put("prim/ring", 2, 2, 96, 96, 1, ring(45, 3)) -- 가는 고리 (반지름 45 · 굵기 3)
	put("prim/ringb", 102, 2, 96, 96, 1, ring(40, 10)) -- 굵은 고리 (반지름 40 · 굵기 10)
	put("prim/grad", 2, 102, 64, 8, 1, function(u)
		return 1 - u
	end) -- 왼쪽이 진하고 오른쪽으로 사라지는 띠
	put("prim/softgrad", 2, 116, 64, 32, 1, function(u, v)
		return soft(v) * (1 - u)
	end) -- 가장자리가 부드럽고 오른쪽으로 사라지는 띠
	put("prim/soft", 70, 116, 8, 32, 1, function(_, v)
		return soft(v)
	end) -- 가장자리가 부드러운 띠
	-- 퍼진 빛: 원본의 둥근 빛(fx/glow)을 「더하기 섞기」로 밝은 바닥에 얹으면 가운데 넓은 곳이 하얗게 날아간다 — 그 모양(가운데가 넓게 꽉 찬 빛)
	put("prim/glow2", 116, 102, 64, 64, 1, function(u, v)
		local r = math.sqrt((u - 0.5) ^ 2 + (v - 0.5) ^ 2) * 2
		local g = if r < 0.35 then 1 - r / 0.35 * 0.55 elseif r < 1 then 0.45 * (1 - (r - 0.35) / 0.65) else 0
		return math.min(1, 2.2 * g)
	end)
	-- 열린 열차 문으로 드는 빛(위쪽 문): 문(폭 68)에서 통로 쪽(폭 156)으로 퍼지며 옅어지는 사다리꼴. 기준점 = (문 가운데, 열차 가운데 y=0)
	put("prim/cone", 186, 102, 78, 61, 0.5, function(u, v)
		local x = (u - 0.5) * 156
		local hw = 34 + 44 * v
		return math.clamp((hw - math.abs(x)) / 3 + 0.5, 0, 1) * (1 - v)
	end, 78, 132)
	-- 혜성 꼬리: 왼쪽(머리)이 굵고 진하며 오른쪽(꼬리 끝)으로 가늘어지며 사라진다 — 원본의 카드 꼬리(토막마다 굵기 11f · 투명도 0.6f)를 한 장에
	put("prim/comet", 206, 4, 64, 16, 1, function(u, v)
		local f = 1 - u
		local d = math.abs(v - 0.5) * 2
		local e = math.clamp((f - d) / 0.25, 0, 1) -- 폭이 f에 비례 · 가장자리는 부드럽게
		return f * e
	end)
	-- 음파 고리의 단면(바깥 +10.5 ~ 안 −17.5 · 원본의 네 겹 선을 한 장에): 옅은 넓은 띠 20 · 진한 띠 6 · 흰 심 2 · 안쪽 16에 가는 줄 3
	local WAVES = {
		{ name = "prim/wave/nag", c1 = { 255, 110, 30 }, c2 = { 255, 180, 60 } },
		{ name = "prim/wave/push", c1 = { 235, 50, 60 }, c2 = { 255, 130, 120 } },
		{ name = "prim/wave/bass", c1 = { 225, 50, 200 }, c2 = { 255, 120, 215 } },
	}
	for i, wv in WAVES do
		local c1, c2 = wv.c1, wv.c2
		put(wv.name, 84 + (i - 1) * 10, 104, 4, 56, 2, function(_, v)
			local rho = 10.5 - 28 * v
			local a, r, g, b = 0, 1, 1, 1
			local function over(sa: number, sr: number, sg: number, sb: number)
				local na = sa + a * (1 - sa)
				if na > 0 then
					r = (sr * sa + r * a * (1 - sa)) / na
					g = (sg * sa + g * a * (1 - sa)) / na
					b = (sb * sa + b * a * (1 - sa)) / na
				end
				a = na
			end
			if math.abs(rho) <= 10 then
				over(0.22, c1[1] / 255, c1[2] / 255, c1[3] / 255)
			end
			if math.abs(rho) <= 3 then
				over(0.95, c2[1] / 255, c2[2] / 255, c2[3] / 255)
			end
			if math.abs(rho) <= 1 then
				over(0.9, 1, 1, 1)
			end
			if math.abs(rho + 16) <= 1.5 then
				over(0.35, c2[1] / 255, c2[2] / 255, c2[3] / 255)
			end
			return a, r, g, b
		end)
	end
	return buf
end

local function makeImage(w: number, h: number, buf: buffer): any
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
	return Content.fromObject(img)
end

-- 판을 만든다. 여러 장에 걸쳐 풀 수 있다(기다린다). 두 번 불러도 한 번만 한다.
function Art.init()
	if Art.ready then
		return
	end
	if starting then
		while not Art.ready do
			task.wait()
		end
		return
	end
	starting = true
	local ids: { [string]: any } = {}
	local idModule = artFolder:FindFirstChild("AssetIds")
	if idModule and idModule:IsA("ModuleScript") then
		local ok, res = pcall(require, idModule)
		if ok and type(res) == "table" then
			ids = res
		elseif not ok then
			warn("[Art] AssetIds를 읽지 못했다: " .. tostring(res))
		end
	end
	local pixels = artFolder:FindFirstChild("pixels")
	local function get(name: string)
		return require((pixels :: Instance):WaitForChild(name) :: ModuleScript)
	end
	for i, page in Atlas.pages do
		local id = ids[page.name]
		if type(id) == "number" then
			id = "rbxassetid://" .. id
		end
		if type(id) == "string" and id ~= "" then
			pageImage[i] = id
		elseif pixels then
			local ok, err = pcall(function()
				local buf, w, h = Decode.load(get, page.name)
				pageContent[i] = makeImage(w, h, buf)
			end)
			if not ok then
				table.insert(Art.failed, page.name)
				warn(("[Art] 판 %s를 만들지 못했다: %s"):format(page.name, tostring(err)))
			end
			task.wait() -- 한 장에 한 판씩
		else
			table.insert(Art.failed, page.name)
			warn(("[Art] 판 %s: 에셋 번호도 점 자료도 없다"):format(page.name))
		end
	end
	-- 올린 판은 다 받아질 때까지 기다린다(그림이 늦게 뜨지 않게). 실패해도 그냥 간다
	local uploaded = {}
	for _, id in pageImage do
		table.insert(uploaded, id)
	end
	if #uploaded > 0 then
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(uploaded)
		end)
	end
	local okP, errP = pcall(function()
		pageContent[PRIM_PAGE] = makeImage(PRIM_W, PRIM_H, buildPrims())
	end)
	if not okP then
		table.insert(Art.failed, "prims")
		warn("[Art] 도움 그림 판을 만들지 못했다: " .. tostring(errP))
	end
	Art.ready = true
end

function Art.has(name: string): boolean
	return sprites[name] ~= nil or extra[name] ~= nil
end

function Art.info(name: string): Info
	local e = sprites[name] or extra[name]
	if not e then
		error("Art: 없는 그림 이름 " .. tostring(name), 2)
	end
	return e
end

-- 세계 단위 크기
function Art.size(name: string): (number, number)
	local e = Art.info(name)
	return e.w / e.s, e.h / e.s
end

-- 판만 갈아 끼운다 (화면 코드가 판이 바뀔 때만 부른다)
function Art.setPage(label: ImageLabel, page: number)
	local id = pageImage[page]
	if id then
		label.Image = id
	else
		local c = pageContent[page]
		if c then
			label.ImageContent = c
		else
			label.Image = ""
		end
	end
end

-- 자르는 네모만 정한다 (flip = 좌우 뒤집기: 폭을 음수로)
function Art.setRect(label: ImageLabel, e: Info, flip: boolean?)
	if flip then
		label.ImageRectOffset = Vector2.new(e.x + e.w, e.y)
		label.ImageRectSize = Vector2.new(-e.w, e.h)
	else
		label.ImageRectOffset = Vector2.new(e.x, e.y)
		label.ImageRectSize = Vector2.new(e.w, e.h)
	end
end

-- 그림을 입힌다. Size · Position은 건드리지 않는다
function Art.set(label: ImageLabel, name: string, flip: boolean?): Info
	local e = Art.info(name)
	Art.setPage(label, e.page)
	Art.setRect(label, e, flip)
	return e
end

-- 판 전체를 그대로 쓰는 그림(바닥 무늬)에: 판만 입히고 자르지 않는다
function Art.setWhole(label: ImageLabel, name: string): Info
	local e = Art.info(name)
	Art.setPage(label, e.page)
	label.ImageRectOffset = Vector2.zero
	label.ImageRectSize = Vector2.zero
	return e
end

return Art
