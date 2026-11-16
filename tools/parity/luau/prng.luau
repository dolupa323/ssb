--!optimize 2
-- 씨앗 난수 (mulberry32) — js/prng.cjs 와 비트까지 같은 값을 낸다. 부른 횟수를 센다.
local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift

-- Math.imul: 32비트 곱의 아래 32비트 (부호 없는 값으로 돌려준다)
local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	-- (ah*bl + al*bh) 는 2^33 미만 → 정확. lshift 가 2^32 로 나눈 나머지를 쓴다.
	return (lshift((ah * bl + al * bh) % 4294967296, 16) + al * bl) % 4294967296
end

local M = {}

function M.makeRng(seed: number)
	local a = seed % 4294967296
	local st = { calls = 0 }
	st.next = function(): number
		st.calls += 1
		a = (a + 0x6D2B79F5) % 4294967296
		local t = imul(bxor(a, rshift(a, 15)), bor(1, a))
		t = bxor((t + imul(bxor(t, rshift(t, 7)), bor(61, t))) % 4294967296, t)
		return bxor(t, rshift(t, 14)) / 4294967296
	end
	return st
end

-- float64 → 16자리 hex (비트 그대로)
local buf = buffer.create(8)
function M.hex(x: number): string
	buffer.writef64(buf, 0, x)
	return string.format("%08x%08x", buffer.readu32(buf, 4), buffer.readu32(buf, 0))
end

M.imul = imul
return M
