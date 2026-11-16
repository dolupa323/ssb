--!optimize 2
-- 견줌용 수학 함수 — js/softmath.cjs 와 "같은 순서의 +,-,*,/" 만으로 쓴 sin/cos/atan2/exp/pow.
-- 두 파일은 한 줄씩 짝이 맞아야 한다 (run.mjs 의 softmath 검사가 비트까지 견준다).
local floor = math.floor
local INF = math.huge
local NAN = 0 / 0
local INV_PIO2, PIO2_1, PIO2_2, PIO2_3 = 0.6366197723675814, 1.5707963267341256, 6.077100506303966e-11, 2.0222662487111665e-21
local S1, S2, S3, S4, S5, S6 = -0.16666666666666632, 0.00833333333332249, -0.0001984126982985795, 0.0000027557313707070068, -2.5050760253406863e-8, 1.58969099521155e-10
local C1, C2, C3, C4, C5, C6 = 0.0416666666666666, -0.001388888888887411, 0.00002480158728947673, -2.7557314351390663e-7, 2.087572321298175e-9, -1.1359647557788195e-11
local AH0, AH1, AH2, AH3 = 0.4636476090008061, 0.7853981633974483, 0.982793723247329, 1.5707963267948966
local AL0, AL1, AL2, AL3 = 2.2698777452961687e-17, 3.061616997868383e-17, 1.3903311031230998e-17, 6.123233995736766e-17
local T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10 = 0.3333333333333293, -0.19999999999876483, 0.14285714272503466, -0.11111110405462356, 0.09090887133436507, -0.0769187620504483, 0.06661073137387531, -0.058335701337905735, 0.049768779946159324, -0.036531572744216916, 0.016285820115365782
local PI, PIO2, PI_LO = 3.141592653589793, 1.5707963267948966, 1.2246467991473532e-16
local LN2HI, LN2LO, INVLN2 = 0.6931471803691238, 1.9082149292705877e-10, 1.4426950408889634
local P1, P2, P3, P4, P5 = 0.16666666666666602, -0.0027777777777015593, 0.00006613756321437934, -0.0000016533902205465252, 4.1381367970572385e-8
local TINY, BIG = 1.862645149230957e-9, 7.378697629483821e19

local function ksin(r: number): number
	local z = r * r
	local v = z * r
	local rr = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
	return r + v * (S1 + z * rr)
end
local function kcos(r: number): number
	local z = r * r
	local rr = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
	return 1 - (0.5 * z - z * rr)
end
local function sin(x: number): number
	if x ~= x or x == INF or x == -INF then
		return NAN
	end
	if x == 0 then
		return x
	end
	local n = floor(x * INV_PIO2 + 0.5)
	local r = ((x - n * PIO2_1) - n * PIO2_2) - n * PIO2_3
	local q = n - 4 * floor(n / 4)
	if q == 0 then
		return ksin(r)
	end
	if q == 1 then
		return kcos(r)
	end
	if q == 2 then
		return -ksin(r)
	end
	return -kcos(r)
end
local function cos(x: number): number
	if x ~= x or x == INF or x == -INF then
		return NAN
	end
	local n = floor(x * INV_PIO2 + 0.5)
	local r = ((x - n * PIO2_1) - n * PIO2_2) - n * PIO2_3
	local q = n - 4 * floor(n / 4)
	if q == 0 then
		return kcos(r)
	end
	if q == 1 then
		return -ksin(r)
	end
	if q == 2 then
		return -kcos(r)
	end
	return ksin(r)
end
local function atan(x: number): number
	if x ~= x then
		return NAN
	end
	local neg = x < 0
	if neg then
		x = -x
	end
	local id
	if x < 0.4375 then
		if x < TINY then
			return if neg then -x else x
		end
		id = -1
	elseif x < 1.1875 then
		if x < 0.6875 then
			id = 0
			x = (2 * x - 1) / (2 + x)
		else
			id = 1
			x = (x - 1) / (x + 1)
		end
	elseif x < 2.4375 then
		id = 2
		x = (x - 1.5) / (1 + 1.5 * x)
	elseif x > BIG then
		return if neg then -AH3 else AH3
	else
		id = 3
		x = -1 / x
	end
	local z = x * x
	local w = z * z
	local s1 = z * (T0 + w * (T2 + w * (T4 + w * (T6 + w * (T8 + w * T10)))))
	local s2 = w * (T1 + w * (T3 + w * (T5 + w * (T7 + w * T9))))
	local r
	if id < 0 then
		r = x - x * (s1 + s2)
	elseif id == 0 then
		r = AH0 - ((x * (s1 + s2) - AL0) - x)
	elseif id == 1 then
		r = AH1 - ((x * (s1 + s2) - AL1) - x)
	elseif id == 2 then
		r = AH2 - ((x * (s1 + s2) - AL2) - x)
	else
		r = AH3 - ((x * (s1 + s2) - AL3) - x)
	end
	return if neg then -r else r
end
local function atan2(y: number, x: number): number
	if x ~= x or y ~= y then
		return NAN
	end
	if y == 0 then
		if x > 0 or (x == 0 and 1 / x > 0) then
			return y
		end
		return if 1 / y > 0 then PI else -PI
	end
	if x == 0 then
		return if y > 0 then PIO2 else -PIO2
	end
	local q = y / x
	if q < 0 then
		q = -q
	end
	local z = atan(q)
	if x > 0 then
		return if y > 0 then z else -z
	end
	return if y > 0 then PI - (z - PI_LO) else (z - PI_LO) - PI
end
local function exp(x: number): number
	if x ~= x then
		return NAN
	end
	if x > 709.782712893384 then
		return INF
	end
	if x < -745.1332191019411 then
		return 0
	end
	local k = floor(x * INVLN2 + 0.5)
	local hi = x - k * LN2HI
	local lo = k * LN2LO
	local r = hi - lo
	local t = r * r
	local c = r - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
	local y = 1 - ((lo - (r * c) / (2 - c)) - hi)
	if k == 0 then
		return y
	end
	local p = 1
	if k > 0 then
		for _ = 1, k do
			p = p * 2
		end
	else
		for _ = 1, -k do
			p = p * 0.5
		end
	end
	return y * p
end
-- 게임은 정수 지수만 쓴다 (x^2, 1.16^n)
local function pow(x: number, y: number): number
	if y ~= floor(y) or y > 1024 or y < -1024 then
		error("softmath.pow: 정수 지수만 지원 (" .. tostring(y) .. ")")
	end
	local n = if y < 0 then -y else y
	local r, b = 1, x
	while n > 0 do
		if n - 2 * floor(n / 2) == 1 then
			r = r * b
		end
		n = floor(n / 2)
		if n > 0 then
			b = b * b
		end
	end
	return if y < 0 then 1 / r else r
end
return { sin = sin, cos = cos, atan2 = atan2, exp = exp, pow = pow }
