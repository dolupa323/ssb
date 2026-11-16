--!native
--!optimize 2
--!strict
-- 구운 그림 판의 점 자료를 푼다 (로블록스 API를 쓰지 않는다 — tools/luau/luau.exe로도 돈다).
--
--   local head = require(pixels.chars1)                      -- { v, w, h, n, raw, z, parts, data }
--   local buf, w, h = Decode.page(head, { require(pixels.chars1_2), ... })   -- parts가 1이면 둘째 인자는 없어도 된다
--   또는  Decode.load(function(name) return require(pixels[name]) end, "chars1")
--   buf = RGBA8 · w*h*4 바이트 · 윗줄부터 · 곧은(곱하지 않은) 알파 → EditableImage:WritePixelsBuffer에 그대로 넣는다.
--
-- 형식 (v = 1):  글자 5개 = 4바이트(85진 · 문자 33~117 · 작은 쪽 먼저인 32비트 수)
--   → z 바이트의 deflate 자료(머리 없는 raw) → 풀면 raw 바이트 = 팔레트 n색 × 4바이트(RGBA) + 점마다 1바이트 팔레트 번호(w*h개).
--   n이 256을 넘으면 번호는 2바이트: 아랫자리 바이트 면(w*h개) 뒤에 윗자리 바이트 면(w*h개)이 따로 온다.
--   팔레트 0번은 언제나 완전 투명(0,0,0,0)이다.

local Decode = {}

local readu8, readu16, readu32 = buffer.readu8, buffer.readu16, buffer.readu32
local writeu8, writeu32 = buffer.writeu8, buffer.writeu32
local band, rshift, lshift = bit32.band, bit32.rshift, bit32.lshift

-- 85진 글자 조각들 → 바이트 (끝에 여유 8바이트를 둔다: 비트를 미리 읽어도 넘치지 않게)
local function unpack85(chunks: { string }, nbytes: number): buffer
	local out = buffer.create(nbytes + 12)
	local op = 0
	for _, s in chunks do
		local src = buffer.fromstring(s)
		for i = 0, #s - 5, 5 do
			if op >= nbytes then
				break
			end
			-- 다섯 글자의 값에서 33씩을 한꺼번에 뺀다 (33 × (85⁴+85³+85²+85+1) = 1743128013)
			writeu32(
				out,
				op,
				readu8(src, i) * 52200625
					+ readu8(src, i + 1) * 614125
					+ readu8(src, i + 2) * 7225
					+ readu8(src, i + 3) * 85
					+ readu8(src, i + 4)
					- 1743128013
			)
			op += 4
		end
	end
	return out
end

local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORD = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local FAST = 10 -- 이 비트 수까지의 부호는 표 한 번으로 푼다
local FASTN = 1024
local FASTM = 1023

-- 허프만 표. lens[기호+1] = 부호 길이(0 = 안 씀).
-- fast[(뒤집은 부호 비트)+1] = 기호*16 + 길이 (0이면 긴 부호 → count/symbol로 한 비트씩 푼다)
type Huff = { fast: { number }, count: { number }, symbol: { number } }
local function build(lens: { number }, n: number): Huff
	local count = table.create(16, 0)
	for i = 1, n do
		count[lens[i] + 1] += 1
	end
	count[1] = 0
	local offs = table.create(16, 0)
	local nextCode = table.create(16, 0)
	local code = 0
	for len = 1, 15 do
		offs[len + 1] = offs[len] + count[len]
		code = (code + count[len]) * 2
		nextCode[len + 1] = code
	end
	local symbol = table.create(n, 0)
	local fast = table.create(FASTN, 0)
	for sym = 0, n - 1 do
		local l = lens[sym + 1]
		if l ~= 0 then
			offs[l + 1] += 1
			symbol[offs[l + 1]] = sym
			local c = nextCode[l + 1]
			nextCode[l + 1] = c + 1
			if l <= FAST then
				-- 부호를 뒤집는다 (deflate는 부호의 높은 비트부터 내보낸다)
				local r = 0
				for _ = 1, l do
					r = r * 2 + c % 2
					c = c // 2
				end
				local e = sym * 16 + l
				local step = lshift(1, l)
				for k = r, FASTM, step do
					fast[k + 1] = e
				end
			end
		end
	end
	return { fast = fast, count = count, symbol = symbol }
end

-- 긴 부호를 한 비트씩 푼다. 돌려주는 값: 기호, 쓴 비트 수
local function slow(h: Huff, bits: number): (number, number)
	local count, symbol = h.count, h.symbol
	local code, first, index = 0, 0, 0
	for len = 1, 15 do
		code += bits % 2
		bits = bits // 2
		local c = count[len + 1]
		if code - c < first then
			return symbol[index + (code - first) + 1], len
		end
		index += c
		first = (first + c) * 2
		code *= 2
	end
	error("Decode: 잘못된 허프만 부호")
end

local fixedLit: Huff? = nil
local fixedDist: Huff? = nil

-- deflate(raw)를 푼다: src의 0번 바이트부터 → dst에 dstLen 바이트
local function inflate(src: buffer, dst: buffer, dstLen: number)
	local pos, bitbuf, bitcnt, op = 0, 0, 0, 0
	local lens = table.create(320, 0)
	while true do
		if bitcnt < 16 then
			bitbuf += lshift(readu16(src, pos), bitcnt)
			pos += 2
			bitcnt += 16
		end
		local final = bitbuf % 2
		local kind = band(rshift(bitbuf, 1), 3)
		bitbuf = rshift(bitbuf, 3)
		bitcnt -= 3
		if kind == 0 then
			-- 압축하지 않은 덩어리: 바이트 경계로 가서 길이를 읽고 그대로 옮긴다
			pos -= bitcnt // 8
			bitbuf = 0
			bitcnt = 0
			local len = readu16(src, pos)
			pos += 4
			buffer.copy(dst, op, src, pos, len)
			op += len
			pos += len
		else
			local lit: Huff, dist: Huff
			if kind == 1 then
				if not fixedLit then
					local l = table.create(288, 8)
					for i = 145, 256 do
						l[i] = 9
					end
					for i = 257, 280 do
						l[i] = 7
					end
					fixedLit = build(l, 288)
					fixedDist = build(table.create(30, 5), 30)
				end
				lit = fixedLit :: Huff
				dist = fixedDist :: Huff
			elseif kind == 2 then
				if bitcnt < 16 then
					bitbuf += lshift(readu16(src, pos), bitcnt)
					pos += 2
					bitcnt += 16
				end
				local hlit = band(bitbuf, 31) + 257
				local hdist = band(rshift(bitbuf, 5), 31) + 1
				local hclen = band(rshift(bitbuf, 10), 15) + 4
				bitbuf = rshift(bitbuf, 14)
				bitcnt -= 14
				local cl = table.create(19, 0)
				for i = 1, hclen do
					if bitcnt < 16 then
						bitbuf += lshift(readu16(src, pos), bitcnt)
						pos += 2
						bitcnt += 16
					end
					cl[CLORD[i] + 1] = band(bitbuf, 7)
					bitbuf = rshift(bitbuf, 3)
					bitcnt -= 3
				end
				local ch = build(cl, 19)
				local chFast = ch.fast
				local i, total, prev = 1, hlit + hdist, 0
				while i <= total do
					if bitcnt < 16 then
						bitbuf += lshift(readu16(src, pos), bitcnt)
						pos += 2
						bitcnt += 16
					end
					local e = chFast[band(bitbuf, FASTM) + 1]
					local l = band(e, 15)
					local sym = rshift(e, 4)
					bitbuf = rshift(bitbuf, l)
					bitcnt -= l
					if sym < 16 then
						lens[i] = sym
						prev = sym
						i += 1
					else
						local rep, val
						if sym == 16 then
							rep = 3 + band(bitbuf, 3)
							val = prev
							bitbuf = rshift(bitbuf, 2)
							bitcnt -= 2
						elseif sym == 17 then
							rep = 3 + band(bitbuf, 7)
							val = 0
							bitbuf = rshift(bitbuf, 3)
							bitcnt -= 3
						else
							rep = 11 + band(bitbuf, 127)
							val = 0
							bitbuf = rshift(bitbuf, 7)
							bitcnt -= 7
						end
						for _ = 1, rep do
							lens[i] = val
							i += 1
						end
						prev = val
					end
				end
				lit = build(lens, hlit)
				local dl = table.create(hdist, 0)
				for k = 1, hdist do
					dl[k] = lens[hlit + k]
				end
				dist = build(dl, hdist)
			else
				error("Decode: 잘못된 deflate 덩어리")
			end
			local litFast, distFast = lit.fast, dist.fast
			while true do
				if bitcnt < 16 then
					bitbuf += lshift(readu16(src, pos), bitcnt)
					pos += 2
					bitcnt += 16
				end
				local e = litFast[band(bitbuf, FASTM) + 1]
				local sym
				if e ~= 0 then
					local l = band(e, 15)
					bitbuf = rshift(bitbuf, l)
					bitcnt -= l
					sym = rshift(e, 4)
				else
					local l
					sym, l = slow(lit, bitbuf)
					bitbuf = rshift(bitbuf, l)
					bitcnt -= l
				end
				if sym < 256 then
					writeu8(dst, op, sym)
					op += 1
				elseif sym == 256 then
					break
				else
					sym -= 256
					local len = LBASE[sym]
					local eb = LEXT[sym]
					if eb > 0 then
						if bitcnt < 16 then
							bitbuf += lshift(readu16(src, pos), bitcnt)
							pos += 2
							bitcnt += 16
						end
						len += band(bitbuf, lshift(1, eb) - 1)
						bitbuf = rshift(bitbuf, eb)
						bitcnt -= eb
					end
					if bitcnt < 16 then
						bitbuf += lshift(readu16(src, pos), bitcnt)
						pos += 2
						bitcnt += 16
					end
					local de = distFast[band(bitbuf, FASTM) + 1]
					local ds
					if de ~= 0 then
						local l = band(de, 15)
						bitbuf = rshift(bitbuf, l)
						bitcnt -= l
						ds = rshift(de, 4)
					else
						local l
						ds, l = slow(dist, bitbuf)
						bitbuf = rshift(bitbuf, l)
						bitcnt -= l
					end
					local d = DBASE[ds + 1]
					eb = DEXT[ds + 1]
					if eb > 0 then
						if bitcnt < 16 then
							bitbuf += lshift(readu16(src, pos), bitcnt)
							pos += 2
							bitcnt += 16
						end
						d += band(bitbuf, lshift(1, eb) - 1)
						bitbuf = rshift(bitbuf, eb)
						bitcnt -= eb
					end
					if d >= len then
						buffer.copy(dst, op, dst, op - d, len)
						op += len
					elseif d == 1 then
						buffer.fill(dst, op, readu8(dst, op - 1), len)
						op += len
					else
						-- 겹치는 복사: 이미 쓴 만큼씩 불려 가며 옮긴다
						local from = op - d
						while len > 0 do
							local n = op - from
							if n > len then
								n = len
							end
							buffer.copy(dst, op, dst, from, n)
							op += n
							len -= n
						end
					end
				end
			end
		end
		if final == 1 then
			break
		end
	end
	if op ~= dstLen then
		error(`Decode: 푼 길이가 다릅니다 ({op} / {dstLen})`)
	end
end

-- 256색을 넘는 판: 번호의 아랫자리 면(w*h바이트) 뒤에 윗자리 면(w*h바이트)이 온다
local function expand16(raw: buffer, pal: { number }, base: number, npx: number): buffer
	local out = buffer.create(npx * 4)
	local hi = base + npx
	local i = 0
	local lim = npx - 3
	while i < lim do
		local a = readu32(raw, base + i)
		local b = readu32(raw, hi + i)
		if b == 0 then
			if a ~= 0 then
				local o = i * 4
				writeu32(out, o, pal[readu8(raw, base + i) + 1])
				writeu32(out, o + 4, pal[readu8(raw, base + i + 1) + 1])
				writeu32(out, o + 8, pal[readu8(raw, base + i + 2) + 1])
				writeu32(out, o + 12, pal[readu8(raw, base + i + 3) + 1])
			end
		else
			local o = i * 4
			writeu32(out, o, pal[readu8(raw, base + i) + readu8(raw, hi + i) * 256 + 1])
			writeu32(out, o + 4, pal[readu8(raw, base + i + 1) + readu8(raw, hi + i + 1) * 256 + 1])
			writeu32(out, o + 8, pal[readu8(raw, base + i + 2) + readu8(raw, hi + i + 2) * 256 + 1])
			writeu32(out, o + 12, pal[readu8(raw, base + i + 3) + readu8(raw, hi + i + 3) * 256 + 1])
		end
		i += 4
	end
	while i < npx do
		writeu32(out, i * 4, pal[readu8(raw, base + i) + readu8(raw, hi + i) * 256 + 1])
		i += 1
	end
	return out
end

export type PageData = { v: number, w: number, h: number, n: number, raw: number, z: number, parts: number, data: string }

-- 판 한 장을 푼다. extra = 둘째 조각부터의 글 (head.parts가 1이면 없어도 된다)
function Decode.page(head: PageData, extra: { string }?): (buffer, number, number)
	if head.v ~= 1 then
		error("Decode: 모르는 형식 v=" .. tostring(head.v))
	end
	local chunks = { head.data }
	if extra then
		for _, s in extra do
			table.insert(chunks, s)
		end
	end
	if #chunks ~= head.parts then
		error(`Decode: 조각 수가 다릅니다 ({#chunks} / {head.parts})`)
	end
	local w, h, n = head.w, head.h, head.n
	local z = unpack85(chunks, head.z)
	local raw = buffer.create(head.raw)
	inflate(z, raw, head.raw)

	local pal = table.create(n, 0)
	for i = 0, n - 1 do
		pal[i + 1] = readu32(raw, i * 4)
	end
	local npx = w * h
	local base = n * 4
	if n > 256 then
		return expand16(raw, pal, base, npx), w, h
	end
	local out = buffer.create(npx * 4)
	local i = 0
	-- 네 점씩 본다. 넷 다 0번(완전 투명)이면 건너뛴다 — 새 buffer는 0으로 차 있다.
	local lim = npx - 3
	while i < lim do
		if readu32(raw, base + i) ~= 0 then
			local o = i * 4
			writeu32(out, o, pal[readu8(raw, base + i) + 1])
			writeu32(out, o + 4, pal[readu8(raw, base + i + 1) + 1])
			writeu32(out, o + 8, pal[readu8(raw, base + i + 2) + 1])
			writeu32(out, o + 12, pal[readu8(raw, base + i + 3) + 1])
		end
		i += 4
	end
	while i < npx do
		writeu32(out, i * 4, pal[readu8(raw, base + i) + 1])
		i += 1
	end
	return out, w, h
end

-- get(이름) = 그 이름의 점 자료 모듈이 돌려준 값. 조각이 여럿이면 「이름_2」, 「이름_3」…을 차례로 가져와 푼다.
function Decode.load(get: (string) -> any, name: string): (buffer, number, number)
	local head = get(name) :: PageData
	local extra = {}
	for i = 2, head.parts do
		table.insert(extra, get(name .. "_" .. i) :: string)
	end
	return Decode.page(head, extra)
end

return Decode
