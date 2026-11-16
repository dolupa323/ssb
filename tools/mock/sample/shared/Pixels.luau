--!strict
-- 견본 그림: 16x16 조각 넷을 가로로 이은 64x16 판(오른쪽을 보는 사람 · 화살표 · 동전 · 바둑무늬)을 점으로 만든다.
--  돌려주는 것: { w, h, buf(RGBA) }
local Pixels = {}

local W, H = 64, 16

local function put(buf: buffer, x: number, y: number, r: number, g: number, b: number, a: number)
	if x < 0 or y < 0 or x >= W or y >= H then
		return
	end
	local i = (y * W + x) * 4
	buffer.writeu8(buf, i, r)
	buffer.writeu8(buf, i + 1, g)
	buffer.writeu8(buf, i + 2, b)
	buffer.writeu8(buf, i + 3, a)
end

function Pixels.make()
	local buf = buffer.create(W * H * 4)
	-- 0: 사람(오른쪽을 본다 — 코가 오른쪽에 튀어나와 있다)
	for y = 2, 13 do
		for x = 4, 10 do
			put(buf, x, y, 240, 200, 160, 255)
		end
	end
	for y = 5, 7 do
		put(buf, 11, y, 240, 200, 160, 255) -- 코
		put(buf, 12, y, 240, 200, 160, 255)
	end
	put(buf, 9, 4, 20, 20, 30, 255) -- 눈
	for x = 4, 10 do
		put(buf, x, 2, 60, 40, 30, 255) -- 머리카락
		put(buf, x, 3, 60, 40, 30, 255)
	end
	for y = 10, 13 do
		for x = 4, 10 do
			put(buf, x, y, 40, 80, 200, 255) -- 옷(파랑)
		end
	end
	-- 1: 화살표(오른쪽을 가리킨다 · 빨강)
	for x = 2, 10 do
		for y = 6, 9 do
			put(buf, 16 + x, y, 220, 50, 50, 255)
		end
	end
	for i = 0, 5 do
		for y = 2 + i, 13 - i do
			put(buf, 16 + 9 + i, y, 220, 50, 50, 255)
		end
	end
	-- 2: 동전(노랑 동그라미)
	for y = 0, 15 do
		for x = 0, 15 do
			local dx, dy = x - 7.5, y - 7.5
			local d = dx * dx + dy * dy
			if d <= 42 then
				local edge = d > 30
				put(buf, 32 + x, y, if edge then 180 else 250, if edge then 130 else 210, 30, 255)
			end
		end
	end
	-- 3: 바둑무늬(반은 비친다)
	for y = 0, 15 do
		for x = 0, 15 do
			local on = ((x // 4) + (y // 4)) % 2 == 0
			put(buf, 48 + x, y, if on then 255 else 30, if on then 255 else 200, if on then 255 else 120, if on then 255 else 128)
		end
	end
	return { w = W, h = H, buf = buf }
end

return Pixels
