-- Roblox 자료형 흉내: Vector2 · Vector3 · UDim · UDim2 · Color3 · Rect · NumberRange · NumberSequence · ColorSequence ·
--  TweenInfo · Font · Content · Enum · Random · DateTime · CFrame(자리만) · BrickColor(이름만).
--  값은 얼린 표 + 메타테이블. type()/typeof()는 스크립트마다 가려 씌운 함수(Types.type / Types.typeof)가 Roblox처럼 답한다.
local R = require("./rt")
R.mark()
local API = require("./apidump")
local Types = {}
R.Types = Types
local TYPEOF = R.TYPEOF
local raise = R.raise

local function num(v: any, what: string, def: number?): number
	if v == nil and def ~= nil then
		return def
	end
	if type(v) ~= "number" then
		local n = if type(v) == "string" then tonumber(v) else nil
		if n then
			return n
		end
		raise(what .. ": 수가 와야 하는데 " .. Types.typeof(v) .. "이(가) 왔다")
	end
	return v
end

local function fmt(n: number): string
	if n ~= n then
		return "nan"
	end
	if n % 1 == 0 and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	local s = string.format("%.6g", n)
	return s
end

-- 자료형의 메타테이블 틀
local function newType(name: string, methods: { [string]: any }, getters: { [string]: (any) -> any })
	local mt = {}
	mt.__index = function(self, k)
		local g = getters[k]
		if g then
			return g(self)
		end
		local m = methods[k]
		if m ~= nil then
			return m
		end
		raise(tostring(k) .. " is not a valid member of " .. name .. R.hint(k, methods) .. R.hint(k, getters))
	end
	mt.__newindex = function(_, k)
		raise(tostring(k) .. " cannot be assigned to (" .. name .. ")")
	end
	TYPEOF[mt] = name
	return mt
end

local function is(v: any, mt: any): boolean
	return type(v) == "table" and getmetatable(v) == mt
end

-- ---------- typeof / type ----------
function Types.typeof(v: any): string
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt then
			local n = TYPEOF[mt]
			if n then
				if type(n) == "function" then
					return n(v)
				end
				return n
			end
		end
		return "table"
	end
	return t
end

function Types.type(v: any): string
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt and TYPEOF[mt] then
			return "userdata"
		end
	end
	return t
end

-- ---------- Vector2 ----------
local V2MT
local V2M, V2G = {}, {}
local function V2(x: number, y: number)
	return table.freeze(setmetatable({ X = x, Y = y }, V2MT))
end
Types.V2 = V2
V2MT = newType("Vector2", V2M, V2G)
V2G.x = function(s)
	return s.X
end
V2G.y = function(s)
	return s.Y
end
V2G.Magnitude = function(s)
	return math.sqrt(s.X * s.X + s.Y * s.Y)
end
V2G.magnitude = V2G.Magnitude
V2G.Unit = function(s)
	local m = math.sqrt(s.X * s.X + s.Y * s.Y)
	if m == 0 then
		return V2(0 / 0, 0 / 0)
	end
	return V2(s.X / m, s.Y / m)
end
V2G.unit = V2G.Unit
local function asV2(v: any, what: string)
	if not is(v, V2MT) then
		raise(what .. ": Vector2가 와야 하는데 " .. Types.typeof(v) .. "이(가) 왔다")
	end
	return v
end
function V2M.Lerp(a, b, t)
	asV2(b, "Vector2:Lerp")
	return V2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
V2M.lerp = V2M.Lerp
function V2M.Dot(a, b)
	asV2(b, "Vector2:Dot")
	return a.X * b.X + a.Y * b.Y
end
function V2M.Cross(a, b)
	asV2(b, "Vector2:Cross")
	return a.X * b.Y - a.Y * b.X
end
function V2M.Abs(a)
	return V2(math.abs(a.X), math.abs(a.Y))
end
function V2M.Ceil(a)
	return V2(math.ceil(a.X), math.ceil(a.Y))
end
function V2M.Floor(a)
	return V2(math.floor(a.X), math.floor(a.Y))
end
function V2M.Sign(a)
	return V2(math.sign(a.X), math.sign(a.Y))
end
function V2M.Angle(a, b, isSigned)
	asV2(b, "Vector2:Angle")
	local ang = math.atan2(a.X * b.Y - a.Y * b.X, a.X * b.X + a.Y * b.Y)
	return if isSigned then ang else math.abs(ang)
end
function V2M.Max(a, ...)
	local x, y = a.X, a.Y
	for _, o in { ... } do
		asV2(o, "Vector2:Max")
		x, y = math.max(x, o.X), math.max(y, o.Y)
	end
	return V2(x, y)
end
function V2M.Min(a, ...)
	local x, y = a.X, a.Y
	for _, o in { ... } do
		asV2(o, "Vector2:Min")
		x, y = math.min(x, o.X), math.min(y, o.Y)
	end
	return V2(x, y)
end
function V2M.FuzzyEq(a, b, eps)
	asV2(b, "Vector2:FuzzyEq")
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
V2MT.__add = function(a, b)
	if not is(a, V2MT) or not is(b, V2MT) then
		raise("attempt to perform arithmetic (add) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return V2(a.X + b.X, a.Y + b.Y)
end
V2MT.__sub = function(a, b)
	if not is(a, V2MT) or not is(b, V2MT) then
		raise("attempt to perform arithmetic (sub) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return V2(a.X - b.X, a.Y - b.Y)
end
V2MT.__mul = function(a, b)
	if type(a) == "number" then
		return V2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return V2(a.X * b, a.Y * b)
	elseif is(a, V2MT) and is(b, V2MT) then
		return V2(a.X * b.X, a.Y * b.Y)
	end
	raise("attempt to perform arithmetic (mul) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
end
V2MT.__div = function(a, b)
	if type(a) == "number" then
		return V2(a / b.X, a / b.Y)
	elseif type(b) == "number" then
		return V2(a.X / b, a.Y / b)
	elseif is(a, V2MT) and is(b, V2MT) then
		return V2(a.X / b.X, a.Y / b.Y)
	end
	raise("attempt to perform arithmetic (div) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
end
V2MT.__idiv = function(a, b)
	if type(b) == "number" then
		return V2(a.X // b, a.Y // b)
	elseif is(a, V2MT) and is(b, V2MT) then
		return V2(a.X // b.X, a.Y // b.Y)
	end
	raise("attempt to perform arithmetic (idiv) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
end
V2MT.__unm = function(a)
	return V2(-a.X, -a.Y)
end
V2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2MT.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y)
end
local Vector2 = {}
function Vector2.new(x, y)
	return V2(num(x, "Vector2.new", 0), num(y, "Vector2.new", 0))
end
Vector2.zero = V2(0, 0)
Vector2.one = V2(1, 1)
Vector2.xAxis = V2(1, 0)
Vector2.yAxis = V2(0, 1)
Types.Vector2 = Vector2
Types.V2MT = V2MT

-- ---------- Vector3 (기본만) ----------
local V3MT
local V3M, V3G = {}, {}
local function V3(x: number, y: number, z: number)
	return table.freeze(setmetatable({ X = x, Y = y, Z = z }, V3MT))
end
Types.V3 = V3
V3MT = newType("Vector3", V3M, V3G)
V3G.x = function(s)
	return s.X
end
V3G.y = function(s)
	return s.Y
end
V3G.z = function(s)
	return s.Z
end
V3G.Magnitude = function(s)
	return math.sqrt(s.X * s.X + s.Y * s.Y + s.Z * s.Z)
end
V3G.magnitude = V3G.Magnitude
V3G.Unit = function(s)
	local m = math.sqrt(s.X * s.X + s.Y * s.Y + s.Z * s.Z)
	return V3(s.X / m, s.Y / m, s.Z / m)
end
V3G.unit = V3G.Unit
function V3M.Lerp(a, b, t)
	return V3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3M.Cross(a, b)
	return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3M.Abs(a)
	return V3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3M.Floor(a)
	return V3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3M.Ceil(a)
	return V3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3M.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
V3MT.__add = function(a, b)
	if not is(a, V3MT) or not is(b, V3MT) then
		raise("attempt to perform arithmetic (add) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3MT.__sub = function(a, b)
	if not is(a, V3MT) or not is(b, V3MT) then
		raise("attempt to perform arithmetic (sub) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3MT.__mul = function(a, b)
	if type(a) == "number" then
		return V3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return V3(a.X * b, a.Y * b, a.Z * b)
	elseif is(a, V3MT) and is(b, V3MT) then
		return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	raise("attempt to perform arithmetic (mul) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
end
V3MT.__div = function(a, b)
	if type(b) == "number" then
		return V3(a.X / b, a.Y / b, a.Z / b)
	elseif type(a) == "number" then
		return V3(a / b.X, a / b.Y, a / b.Z)
	elseif is(a, V3MT) and is(b, V3MT) then
		return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	raise("attempt to perform arithmetic (div) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
end
V3MT.__unm = function(a)
	return V3(-a.X, -a.Y, -a.Z)
end
V3MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3MT.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y) .. ", " .. fmt(a.Z)
end
local Vector3 = {}
function Vector3.new(x, y, z)
	return V3(num(x, "Vector3.new", 0), num(y, "Vector3.new", 0), num(z, "Vector3.new", 0))
end
Vector3.zero = V3(0, 0, 0)
Vector3.one = V3(1, 1, 1)
Vector3.xAxis = V3(1, 0, 0)
Vector3.yAxis = V3(0, 1, 0)
Vector3.zAxis = V3(0, 0, 1)
Types.Vector3 = Vector3
Types.V3MT = V3MT

-- ---------- UDim ----------
local UDimMT
local UDimM, UDimG = {}, {}
local function UD(scale: number, offset: number)
	return table.freeze(setmetatable({ Scale = scale, Offset = offset }, UDimMT))
end
Types.UD = UD
UDimMT = newType("UDim", UDimM, UDimG)
UDimMT.__add = function(a, b)
	if not is(a, UDimMT) or not is(b, UDimMT) then
		raise("attempt to perform arithmetic (add) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return UD(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMT.__sub = function(a, b)
	if not is(a, UDimMT) or not is(b, UDimMT) then
		raise("attempt to perform arithmetic (sub) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return UD(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDimMT.__unm = function(a)
	return UD(-a.Scale, -a.Offset)
end
UDimMT.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimMT.__tostring = function(a)
	return fmt(a.Scale) .. ", " .. fmt(a.Offset)
end
local UDim = {}
function UDim.new(scale, offset)
	return UD(num(scale, "UDim.new", 0), num(offset, "UDim.new", 0))
end
Types.UDim = UDim
Types.UDimMT = UDimMT

-- ---------- UDim2 (안쪽은 { xs, xo, ys, yo } 네 칸) ----------
local UD2MT
local UD2M, UD2G = {}, {}
local function UD2(xs: number, xo: number, ys: number, yo: number)
	return table.freeze(setmetatable({ xs, xo, ys, yo }, UD2MT))
end
Types.UD2 = UD2
UD2MT = newType("UDim2", UD2M, UD2G)
UD2G.X = function(s)
	return UD(s[1], s[2])
end
UD2G.Y = function(s)
	return UD(s[3], s[4])
end
UD2G.Width = UD2G.X
UD2G.Height = UD2G.Y
function UD2M.Lerp(a, b, t)
	if not is(b, UD2MT) then
		raise("UDim2:Lerp: UDim2가 와야 하는데 " .. Types.typeof(b) .. "이(가) 왔다")
	end
	return UD2(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t)
end
UD2MT.__add = function(a, b)
	if not is(a, UD2MT) or not is(b, UD2MT) then
		raise("attempt to perform arithmetic (add) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return UD2(a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4] + b[4])
end
UD2MT.__sub = function(a, b)
	if not is(a, UD2MT) or not is(b, UD2MT) then
		raise("attempt to perform arithmetic (sub) on " .. Types.typeof(a) .. " and " .. Types.typeof(b))
	end
	return UD2(a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4] - b[4])
end
UD2MT.__unm = function(a)
	return UD2(-a[1], -a[2], -a[3], -a[4])
end
UD2MT.__eq = function(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end
UD2MT.__tostring = function(a)
	return "{" .. fmt(a[1]) .. ", " .. fmt(a[2]) .. "}, {" .. fmt(a[3]) .. ", " .. fmt(a[4]) .. "}"
end
local UDim2 = {}
function UDim2.new(a, b, c, d)
	if a == nil and b == nil and c == nil and d == nil then
		return UD2(0, 0, 0, 0)
	end
	if is(a, UDimMT) or is(b, UDimMT) then
		if not is(a, UDimMT) or not is(b, UDimMT) then
			raise("UDim2.new: (UDim, UDim) 또는 (수, 수, 수, 수)가 와야 한다")
		end
		return UD2(a.Scale, a.Offset, b.Scale, b.Offset)
	end
	return UD2(num(a, "UDim2.new", 0), num(b, "UDim2.new", 0), num(c, "UDim2.new", 0), num(d, "UDim2.new", 0))
end
function UDim2.fromScale(x, y)
	return UD2(num(x, "UDim2.fromScale", 0), 0, num(y, "UDim2.fromScale", 0), 0)
end
function UDim2.fromOffset(x, y)
	return UD2(0, num(x, "UDim2.fromOffset", 0), 0, num(y, "UDim2.fromOffset", 0))
end
Types.UDim2 = UDim2
Types.UD2MT = UD2MT

-- ---------- Color3 ----------
local C3MT
local C3M, C3G = {}, {}
local function C3(r: number, g: number, b: number)
	return table.freeze(setmetatable({ R = r, G = g, B = b }, C3MT))
end
Types.C3 = C3
C3MT = newType("Color3", C3M, C3G)
C3G.r = function(s)
	return s.R
end
C3G.g = function(s)
	return s.G
end
C3G.b = function(s)
	return s.B
end
function C3M.Lerp(a, b, t)
	if not is(b, C3MT) then
		raise("Color3:Lerp: Color3가 와야 하는데 " .. Types.typeof(b) .. "이(가) 왔다")
	end
	return C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
C3M.lerp = C3M.Lerp
function C3M.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if mx == 0 then 0 else d / mx
	return h, s, mx
end
function C3M.ToHex(c)
	local function b8(v)
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("%02x%02x%02x", b8(c.R), b8(c.G), b8(c.B))
end
C3MT.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3MT.__tostring = function(a)
	return fmt(a.R) .. ", " .. fmt(a.G) .. ", " .. fmt(a.B)
end
local Color3 = {}
function Color3.new(r, g, b)
	return C3(num(r, "Color3.new", 0), num(g, "Color3.new", 0), num(b, "Color3.new", 0))
end
function Color3.fromRGB(r, g, b)
	return C3(num(r, "Color3.fromRGB", 0) / 255, num(g, "Color3.fromRGB", 0) / 255, num(b, "Color3.fromRGB", 0) / 255)
end
function Color3.fromHSV(h, s, v)
	h, s, v = num(h, "Color3.fromHSV", 0), num(s, "Color3.fromHSV", 0), num(v, "Color3.fromHSV", 0)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then
		return C3(v, t, p)
	elseif i == 1 then
		return C3(q, v, p)
	elseif i == 2 then
		return C3(p, v, t)
	elseif i == 3 then
		return C3(p, q, v)
	elseif i == 4 then
		return C3(t, p, v)
	end
	return C3(v, p, q)
end
function Color3.fromHex(hex)
	if type(hex) ~= "string" then
		raise("Color3.fromHex: 문자열이 와야 하는데 " .. Types.typeof(hex) .. "이(가) 왔다")
	end
	local h = string.gsub(hex, "^#", "")
	if #h == 3 then
		h = string.rep(string.sub(h, 1, 1), 2) .. string.rep(string.sub(h, 2, 2), 2) .. string.rep(string.sub(h, 3, 3), 2)
	end
	if #h ~= 6 or string.find(h, "[^%x]") then
		raise('Color3.fromHex: 잘못된 16진 색 "' .. hex .. '"')
	end
	return C3(tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255)
end
function Color3.toHSV(c)
	return C3M.ToHSV(c)
end
Types.Color3 = Color3
Types.C3MT = C3MT

-- ---------- Rect ----------
local RectMT
local RectM, RectG = {}, {}
local function RC(x0: number, y0: number, x1: number, y1: number)
	return table.freeze(setmetatable({ Min = V2(x0, y0), Max = V2(x1, y1) }, RectMT))
end
Types.RC = RC
RectMT = newType("Rect", RectM, RectG)
RectG.Width = function(s)
	return s.Max.X - s.Min.X
end
RectG.Height = function(s)
	return s.Max.Y - s.Min.Y
end
RectMT.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
RectMT.__tostring = function(a)
	return fmt(a.Min.X) .. ", " .. fmt(a.Min.Y) .. ", " .. fmt(a.Max.X) .. ", " .. fmt(a.Max.Y)
end
local Rect = {}
function Rect.new(a, b, c, d)
	if is(a, V2MT) then
		if not is(b, V2MT) then
			raise("Rect.new: (Vector2, Vector2) 또는 (수, 수, 수, 수)가 와야 한다")
		end
		return RC(a.X, a.Y, b.X, b.Y)
	end
	return RC(num(a, "Rect.new", 0), num(b, "Rect.new", 0), num(c, "Rect.new", 0), num(d, "Rect.new", 0))
end
Types.Rect = Rect
Types.RectMT = RectMT

-- ---------- NumberRange ----------
local NRMT = newType("NumberRange", {}, {})
NRMT.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
NRMT.__tostring = function(a)
	return fmt(a.Min) .. " " .. fmt(a.Max)
end
local NumberRange = {}
function NumberRange.new(a, b)
	a = num(a, "NumberRange.new")
	b = num(b, "NumberRange.new", a)
	if a > b then
		raise("NumberRange.new: 작은 값이 큰 값보다 크다")
	end
	return table.freeze(setmetatable({ Min = a, Max = b }, NRMT))
end
Types.NumberRange = NumberRange
Types.NRMT = NRMT

-- ---------- NumberSequence · ColorSequence ----------
local NSKMT = newType("NumberSequenceKeypoint", {}, {})
NSKMT.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NSKMT.__tostring = function(a)
	return fmt(a.Time) .. " " .. fmt(a.Value) .. " " .. fmt(a.Envelope)
end
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v, e)
	return table.freeze(setmetatable({ Time = num(t, "NumberSequenceKeypoint.new"), Value = num(v, "NumberSequenceKeypoint.new"), Envelope = num(e, "NumberSequenceKeypoint.new", 0) }, NSKMT))
end
Types.NumberSequenceKeypoint = NumberSequenceKeypoint

local function checkKeys(kps: { any }, mt: any, what: string)
	if #kps < 2 then
		raise(what .. ": 점이 둘 이상 있어야 한다")
	end
	for i, k in kps do
		if not is(k, mt) then
			raise(what .. ": " .. i .. "번째 것이 Keypoint가 아니다")
		end
		if i > 1 and k.Time < kps[i - 1].Time then
			raise(what .. ": 점의 Time이 차례대로가 아니다")
		end
	end
	if kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
		raise(what .. ": 첫 점의 Time은 0, 끝 점은 1이어야 한다")
	end
end

local NSMT = newType("NumberSequence", {}, {})
NSMT.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in a.Keypoints do
		if k ~= b.Keypoints[i] then
			return false
		end
	end
	return true
end
NSMT.__tostring = function(a)
	local parts = {}
	for _, k in a.Keypoints do
		table.insert(parts, tostring(k))
	end
	return table.concat(parts, " ")
end
local NumberSequence = {}
function NumberSequence.new(a, b)
	local kps
	if type(a) == "number" then
		kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, if b == nil then a else num(b, "NumberSequence.new")) }
	elseif type(a) == "table" and not getmetatable(a) then
		kps = table.clone(a)
		checkKeys(kps, NSKMT, "NumberSequence.new")
	else
		raise("NumberSequence.new: 수 · (수, 수) · Keypoint의 배열이 와야 한다")
	end
	return table.freeze(setmetatable({ Keypoints = table.freeze(kps) }, NSMT))
end
Types.NumberSequence = NumberSequence
Types.NSMT = NSMT

local CSKMT = newType("ColorSequenceKeypoint", {}, {})
CSKMT.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value
end
CSKMT.__tostring = function(a)
	return fmt(a.Time) .. " " .. tostring(a.Value)
end
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, c)
	if not is(c, C3MT) then
		raise("ColorSequenceKeypoint.new: Color3가 와야 하는데 " .. Types.typeof(c) .. "이(가) 왔다")
	end
	return table.freeze(setmetatable({ Time = num(t, "ColorSequenceKeypoint.new"), Value = c }, CSKMT))
end
Types.ColorSequenceKeypoint = ColorSequenceKeypoint

local CSMT = newType("ColorSequence", {}, {})
CSMT.__eq = NSMT.__eq
CSMT.__tostring = NSMT.__tostring
local ColorSequence = {}
function ColorSequence.new(a, b)
	local kps
	if is(a, C3MT) then
		if b ~= nil and not is(b, C3MT) then
			raise("ColorSequence.new: 둘째 것도 Color3여야 한다")
		end
		kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	elseif type(a) == "table" and not getmetatable(a) then
		kps = table.clone(a)
		checkKeys(kps, CSKMT, "ColorSequence.new")
	else
		raise("ColorSequence.new: Color3 · (Color3, Color3) · Keypoint의 배열이 와야 한다")
	end
	return table.freeze(setmetatable({ Keypoints = table.freeze(kps) }, CSMT))
end
Types.ColorSequence = ColorSequence
Types.CSMT = CSMT

-- ---------- Enum ----------
local EnumItemMT, EnumTypeMT, EnumsMT = {}, {}, {}
TYPEOF[EnumItemMT] = "EnumItem"
TYPEOF[EnumTypeMT] = "Enum"
TYPEOF[EnumsMT] = "Enums"
Types.EnumItemMT = EnumItemMT
local enumTypes = {} -- 이름 → 열거형
local enumMeta = {} -- 열거형 → { name, items(차례), byValue }

local function enumItemIsA(self, name)
	return name == "EnumItem" or name == enumMeta[self.EnumType].name
end
EnumItemMT.__index = function(self, k)
	if k == "IsA" then
		return enumItemIsA
	end
	raise(tostring(k) .. " is not a valid member of EnumItem (Name · Value · EnumType)")
end
EnumItemMT.__newindex = function(_, k)
	raise(tostring(k) .. " cannot be assigned to (EnumItem)")
end
EnumItemMT.__tostring = function(self)
	return "Enum." .. enumMeta[self.EnumType].name .. "." .. self.Name
end

local enumTypeMethods = {}
function enumTypeMethods.GetEnumItems(self)
	return table.clone(enumMeta[self].items)
end
function enumTypeMethods.FromName(self, name)
	local it = rawget(self, name)
	return if is(it, EnumItemMT) then it else nil
end
function enumTypeMethods.FromValue(self, value)
	return enumMeta[self].byValue[value]
end
EnumTypeMT.__index = function(self, k)
	local m = enumTypeMethods[k]
	if m then
		return m
	end
	local meta = enumMeta[self]
	local names = {}
	for _, it in meta.items do
		names[it.Name] = true
	end
	raise(tostring(k) .. ' is not a valid member of "Enum.' .. meta.name .. '"' .. R.hint(k, names))
end
EnumTypeMT.__newindex = function(self, k)
	raise(tostring(k) .. " cannot be assigned to (Enum)")
end
EnumTypeMT.__tostring = function(self)
	return enumMeta[self].name
end

local function buildEnum(name: string)
	local raw = API.enums[name]
	if not raw then
		return nil
	end
	local et = {}
	local meta = { name = name, items = {}, byValue = {} }
	enumMeta[et] = meta
	for _, part in string.split(raw, ",") do
		local names = string.split(part, "~")
		local n, v = string.match(names[1], "^(.-)=(-?%d+)$")
		local item = table.freeze(setmetatable({ Name = n, Value = tonumber(v), EnumType = et }, EnumItemMT))
		et[n] = item
		table.insert(meta.items, item)
		if meta.byValue[item.Value] == nil then
			meta.byValue[item.Value] = item
		end
		for i = 2, #names do
			et[names[i]] = item -- 옛 이름
		end
	end
	setmetatable(et, EnumTypeMT)
	table.freeze(et)
	enumTypes[name] = et
	return et
end

function Types.enumType(name: string)
	return enumTypes[name] or buildEnum(name)
end
function Types.enumName(item: any): string?
	if is(item, EnumItemMT) then
		return enumMeta[item.EnumType].name
	end
	return nil
end
function Types.enumItem(enumName: string, itemName: string)
	local et = Types.enumType(enumName)
	return et and rawget(et, itemName)
end
function Types.enumFirst(enumName: string)
	local et = Types.enumType(enumName)
	if not et then
		return nil
	end
	local meta = enumMeta[et]
	return meta.byValue[0] or meta.items[1]
end
function Types.isEnumItem(v: any, enumName: string?): boolean
	if not is(v, EnumItemMT) then
		return false
	end
	return enumName == nil or enumMeta[v.EnumType].name == enumName
end

local Enum = setmetatable({}, EnumsMT)
EnumsMT.__index = function(_, k)
	if k == "GetEnums" then
		return function()
			local list = {}
			for n in API.enums do
				table.insert(list, Types.enumType(n))
			end
			return list
		end
	end
	local et = if type(k) == "string" then Types.enumType(k) else nil
	if not et then
		raise(tostring(k) .. ' is not a valid member of "Enum"' .. R.hint(k, API.enums))
	end
	return et
end
EnumsMT.__newindex = function(_, k)
	raise(tostring(k) .. " cannot be assigned to (Enums)")
end
EnumsMT.__tostring = function()
	return "Enums"
end
Types.Enum = Enum

-- ---------- TweenInfo ----------
local TIMT = newType("TweenInfo", {}, {})
TIMT.__eq = function(a, b)
	return a.Time == b.Time and a.EasingStyle == b.EasingStyle and a.EasingDirection == b.EasingDirection and a.RepeatCount == b.RepeatCount and a.Reverses == b.Reverses and a.DelayTime == b.DelayTime
end
TIMT.__tostring = function(a)
	return "Time:" .. fmt(a.Time) .. " DelayTime:" .. fmt(a.DelayTime) .. " RepeatCount:" .. fmt(a.RepeatCount) .. " Reverses:" .. (if a.Reverses then "True" else "False") .. " EasingDirection:" .. a.EasingDirection.Name .. " EasingStyle:" .. a.EasingStyle.Name
end
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	if style ~= nil and not Types.isEnumItem(style, "EasingStyle") then
		raise("TweenInfo.new: 둘째 인자는 Enum.EasingStyle이어야 하는데 " .. Types.typeof(style) .. " " .. tostring(style) .. "이(가) 왔다")
	end
	if direction ~= nil and not Types.isEnumItem(direction, "EasingDirection") then
		raise("TweenInfo.new: 셋째 인자는 Enum.EasingDirection이어야 하는데 " .. Types.typeof(direction) .. " " .. tostring(direction) .. "이(가) 왔다")
	end
	if reverses ~= nil and type(reverses) ~= "boolean" then
		raise("TweenInfo.new: 다섯째 인자(reverses)는 boolean이어야 한다")
	end
	return table.freeze(setmetatable({
		Time = num(time, "TweenInfo.new", 1),
		EasingStyle = style or Types.enumItem("EasingStyle", "Quad"),
		EasingDirection = direction or Types.enumItem("EasingDirection", "Out"),
		RepeatCount = num(repeatCount, "TweenInfo.new", 0),
		Reverses = reverses == true,
		DelayTime = num(delayTime, "TweenInfo.new", 0),
	}, TIMT))
end
Types.TweenInfo = TweenInfo
Types.TIMT = TIMT

-- ---------- Font ----------
local FontMT = {}
TYPEOF[FontMT] = "Font"
FontMT.__index = function(self, k)
	if k == "Bold" then
		return rawget(self, "Weight").Value >= 600
	end
	raise(tostring(k) .. " is not a valid member of Font (Family · Weight · Style · Bold)")
end
FontMT.__newindex = function(self, k, v)
	if k == "Bold" then
		rawset(self, "Weight", Types.enumItem("FontWeight", if v then "Bold" else "Regular"))
		return
	end
	raise(tostring(k) .. " is not a valid member of Font")
end
FontMT.__eq = function(a, b)
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end
FontMT.__tostring = function(a)
	return "Font { Family = " .. a.Family .. ", Weight = " .. a.Weight.Name .. ", Style = " .. a.Style.Name .. " }"
end
local Font = {}
local function mkFont(family: string, weight: any, style: any, what: string)
	if type(family) ~= "string" then
		raise(what .. ": 글꼴 자리는 문자열이어야 하는데 " .. Types.typeof(family) .. "이(가) 왔다")
	end
	if weight ~= nil and not Types.isEnumItem(weight, "FontWeight") then
		raise(what .. ": weight는 Enum.FontWeight여야 하는데 " .. Types.typeof(weight) .. " " .. tostring(weight) .. "이(가) 왔다")
	end
	if style ~= nil and not Types.isEnumItem(style, "FontStyle") then
		raise(what .. ": style은 Enum.FontStyle이어야 하는데 " .. Types.typeof(style) .. " " .. tostring(style) .. "이(가) 왔다")
	end
	return setmetatable({ Family = family, Weight = weight or Types.enumItem("FontWeight", "Regular"), Style = style or Types.enumItem("FontStyle", "Normal") }, FontMT)
end
function Font.new(family, weight, style)
	return mkFont(family, weight, style, "Font.new")
end
function Font.fromName(name, weight, style)
	if type(name) ~= "string" then
		raise("Font.fromName: 이름은 문자열이어야 한다")
	end
	return mkFont("rbxasset://fonts/families/" .. name .. ".json", weight, style, "Font.fromName")
end
function Font.fromId(id, weight, style)
	return mkFont("rbxassetid://" .. fmt(num(id, "Font.fromId")), weight, style, "Font.fromId")
end
-- Enum.Font → (글꼴 파일, 굵기, 모양)
local FONT_BASE = {
	Legacy = "LegacyArial",
	Arial = "Arial",
	ArialBold = "Arial",
	SourceSans = "SourceSansPro",
	SourceSansBold = "SourceSansPro",
	SourceSansLight = "SourceSansPro",
	SourceSansItalic = "SourceSansPro",
	SourceSansSemibold = "SourceSansPro",
	Gotham = "GothamSSm",
	GothamMedium = "GothamSSm",
	GothamBold = "GothamSSm",
	GothamBlack = "GothamSSm",
	Code = "Inconsolata",
	SciFi = "Zekton",
	Arcade = "PressStart2P",
	Fantasy = "Balthazar",
	Antique = "RomanAntique",
	Cartoon = "ComicNeueAngular",
	Bodoni = "AccanthisADFStd",
	Garamond = "Guru",
	Fredoka = "FredokaOne",
	AmaticSC = "AmaticSC",
	Highway = "HighwayGothic",
}
local FONT_WEIGHT = {
	ArialBold = "Bold",
	SourceSansBold = "Bold",
	SourceSansLight = "Light",
	SourceSansSemibold = "SemiBold",
	GothamMedium = "Medium",
	GothamBold = "Bold",
	GothamBlack = "Heavy",
	BuilderSansMedium = "Medium",
	BuilderSansBold = "Bold",
	BuilderSansExtraBold = "ExtraBold",
	MontserratMedium = "Medium",
	MontserratBold = "Bold",
	MontserratBlack = "Heavy",
	ArimoBold = "Bold",
	NunitoBold = "Bold",
}
local FONT_STRIP = { "ExtraBold", "Medium", "Bold", "Black" }
function Font.fromEnum(item)
	if not Types.isEnumItem(item, "Font") then
		raise("Font.fromEnum: Enum.Font가 와야 하는데 " .. Types.typeof(item) .. " " .. tostring(item) .. "이(가) 왔다")
	end
	local name = item.Name
	local base = FONT_BASE[name]
	if not base then
		base = name
		if FONT_WEIGHT[name] then
			for _, suffix in FONT_STRIP do
				if string.sub(base, -#suffix) == suffix then
					base = string.sub(base, 1, -#suffix - 1)
					break
				end
			end
		end
	end
	local f = mkFont("rbxasset://fonts/families/" .. base .. ".json", Types.enumItem("FontWeight", FONT_WEIGHT[name] or "Regular"), Types.enumItem("FontStyle", if name == "SourceSansItalic" then "Italic" else "Normal"), "Font.fromEnum")
	return f
end
-- FontFace → Enum.Font (맞는 것이 없으면 Unknown)
local fontBack: { [string]: any }? = nil
function Types.fontToEnum(font: any)
	if not fontBack then
		fontBack = {}
		for _, it in Types.enumType("Font"):GetEnumItems() do
			if it.Name ~= "Unknown" then
				local f = Font.fromEnum(it)
				local key = f.Family .. "|" .. f.Weight.Name .. "|" .. f.Style.Name
				if not fontBack[key] then
					fontBack[key] = it
				end
			end
		end
	end
	return (fontBack :: any)[font.Family .. "|" .. font.Weight.Name .. "|" .. font.Style.Name] or Types.enumItem("Font", "Unknown")
end
function Types.cloneFont(f: any)
	return setmetatable({ Family = f.Family, Weight = f.Weight, Style = f.Style }, FontMT)
end
Types.Font = Font
Types.FontMT = FontMT

-- ---------- Content ----------
local ContentMT = newType("Content", {}, {})
ContentMT.__eq = function(a, b)
	return a.SourceType == b.SourceType and a.Uri == b.Uri and rawequal(a.Object, b.Object)
end
ContentMT.__tostring = function(a)
	if a.Uri then
		return "Content(" .. a.Uri .. ")"
	elseif a.Object then
		return "Content(Object)"
	end
	return "Content(none)"
end
local Content = {}
local function mkContent(kind: string, uri: string?, obj: any)
	local t = { SourceType = Types.enumItem("ContentSourceType", kind) }
	-- (없는 칸을 읽어도 오류가 나지 않게: false 대신 메타테이블의 __index를 탄다 → Uri · Object는 nil을 돌려준다)
	if uri then
		t.Uri = uri
	end
	if obj then
		t.Object = obj
	end
	return table.freeze(setmetatable(t, ContentMT))
end
ContentMT.__index = function(_, k)
	if k == "Uri" or k == "Object" then
		return nil
	end
	raise(tostring(k) .. " is not a valid member of Content (SourceType · Uri · Object)")
end
function Content.fromUri(uri)
	if type(uri) ~= "string" then
		raise("Content.fromUri: 문자열이 와야 하는데 " .. Types.typeof(uri) .. "이(가) 왔다")
	end
	if uri == "" then
		return Content.none
	end
	return mkContent("Uri", uri, nil)
end
function Content.fromAssetId(id)
	return mkContent("Uri", "rbxassetid://" .. fmt(num(id, "Content.fromAssetId")), nil)
end
function Content.fromObject(obj)
	if Types.typeof(obj) ~= "Object" and Types.typeof(obj) ~= "Instance" then
		raise("Content.fromObject: Object(EditableImage 등)가 와야 하는데 " .. Types.typeof(obj) .. "이(가) 왔다")
	end
	return mkContent("Object", nil, obj)
end
Content.none = mkContent("None", nil, nil)
Types.Content = Content
Types.ContentMT = ContentMT

-- ---------- CFrame (자리만) · BrickColor (이름만) ----------
local CFMT
local CFM, CFG = {}, {}
CFMT = newType("CFrame", CFM, CFG)
local function CF(x, y, z)
	return table.freeze(setmetatable({ X = x, Y = y, Z = z, Position = V3(x, y, z) }, CFMT))
end
CFG.p = function(s)
	return s.Position
end
CFMT.__eq = function(a, b)
	return a.Position == b.Position
end
CFMT.__add = function(a, b)
	return CF(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFMT.__sub = function(a, b)
	return CF(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
CFMT.__mul = function(a, b)
	if is(b, CFMT) then
		return CF(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFMT.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y) .. ", " .. fmt(a.Z) .. ", 1, 0, 0, 0, 1, 0, 0, 0, 1"
end
local CFrame = {}
function CFrame.new(x, y, z)
	if is(x, V3MT) then
		return CF(x.X, x.Y, x.Z)
	end
	R.note("CFrame", "CFrame은 자리(Position)만 흉내 낸다 — 회전은 없다")
	return CF(num(x, "CFrame.new", 0), num(y, "CFrame.new", 0), num(z, "CFrame.new", 0))
end
CFrame.identity = CF(0, 0, 0)
function CFrame.Angles()
	R.note("CFrame", "CFrame은 자리(Position)만 흉내 낸다 — 회전은 없다")
	return CFrame.identity
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromOrientation = CFrame.Angles
function CFrame.lookAt(at)
	R.note("CFrame", "CFrame은 자리(Position)만 흉내 낸다 — 회전은 없다")
	return CF(at.X, at.Y, at.Z)
end
Types.CFrame = CFrame
Types.CFMT = CFMT

local BCMT = newType("BrickColor", {}, {})
BCMT.__eq = function(a, b)
	return a.Name == b.Name
end
BCMT.__tostring = function(a)
	return a.Name
end
local BrickColor = {}
local function BC(name: string, c: any)
	return table.freeze(setmetatable({ Name = name, Color = c, Number = 194, r = c.R, g = c.G, b = c.B }, BCMT))
end
function BrickColor.new(a, b, c)
	R.note("BrickColor", "BrickColor는 이름과 색 몇 가지만 흉내 낸다")
	if is(a, C3MT) then
		return BC("Medium stone grey", a)
	elseif type(a) == "number" and b ~= nil then
		return BC("Medium stone grey", C3(a, b, c))
	end
	local known = { White = C3(0.95, 0.95, 0.95), Black = C3(0.1, 0.1, 0.1), ["Really black"] = C3(0, 0, 0), ["Really red"] = C3(1, 0, 0), ["Bright red"] = C3(0.77, 0.16, 0.11), ["Bright blue"] = C3(0.05, 0.41, 0.67), ["Bright green"] = C3(0.29, 0.59, 0.29), ["Bright yellow"] = C3(0.96, 0.8, 0.19) }
	local name = if type(a) == "string" then a else "Medium stone grey"
	return BC(name, known[name] or C3(0.639216, 0.635294, 0.647059))
end
function BrickColor.White()
	return BrickColor.new("White")
end
function BrickColor.Black()
	return BrickColor.new("Black")
end
function BrickColor.Red()
	return BrickColor.new("Bright red")
end
function BrickColor.Blue()
	return BrickColor.new("Bright blue")
end
function BrickColor.Green()
	return BrickColor.new("Bright green")
end
function BrickColor.Yellow()
	return BrickColor.new("Bright yellow")
end
function BrickColor.Gray()
	return BrickColor.new("Medium stone grey")
end
function BrickColor.random()
	return BrickColor.new("Medium stone grey")
end
Types.BrickColor = BrickColor
Types.BCMT = BCMT

-- ---------- Random (정해진 씨앗에 정해진 수열 — Roblox의 수열과는 다르다) ----------
local RandomMT
local RandomM = {}
RandomMT = newType("Random", RandomM, {})
local function imul(a: number, b: number): number
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	return bit32.band(al * bl + bit32.lshift(bit32.band(ah * bl + al * bh, 0xFFFF), 16), 0xFFFFFFFF)
end
local randomState = setmetatable({}, { __mode = "k" })
local function nextU(self): number
	local s = bit32.band(randomState[self] + 0x6D2B79F5, 0xFFFFFFFF)
	randomState[self] = s
	local t = imul(bit32.bxor(s, bit32.rshift(s, 15)), bit32.bor(s, 1))
	t = bit32.bxor(t, bit32.band(t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61)), 0xFFFFFFFF))
	return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
end
function RandomM.NextNumber(self, a, b)
	local u = nextU(self)
	if a == nil then
		return u
	end
	return a + (b - a) * u
end
function RandomM.NextInteger(self, a, b)
	if type(a) ~= "number" or type(b) ~= "number" then
		raise("Random:NextInteger: 두 정수가 와야 한다")
	end
	if a > b then
		raise("Random:NextInteger: 구간이 비었다 (min > max)")
	end
	return a + math.floor(nextU(self) * (b - a + 1))
end
function RandomM.NextUnitVector(self)
	local z = nextU(self) * 2 - 1
	local a = nextU(self) * math.pi * 2
	local r = math.sqrt(1 - z * z)
	return V3(r * math.cos(a), r * math.sin(a), z)
end
function RandomM.Shuffle(self, t)
	for i = #t, 2, -1 do
		local j = 1 + math.floor(nextU(self) * i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomM.Clone(self)
	local o = setmetatable({}, RandomMT)
	randomState[o] = randomState[self]
	return o
end
local Random = {}
local autoSeed = 12345
function Random.new(seed)
	R.note("Random", "Random.new의 수열은 Roblox의 것과 다르다(씨앗이 같으면 mock 안에서는 늘 같다)")
	local o = setmetatable({}, RandomMT)
	if seed == nil then
		autoSeed += 7919
		seed = autoSeed
	end
	randomState[o] = bit32.band(math.floor(num(seed, "Random.new")), 0xFFFFFFFF)
	return o
end
Types.Random = Random

-- ---------- DateTime (가상 시계) ----------
local DTMT
local DTM = {}
DTMT = newType("DateTime", DTM, {})
local function DT(ms: number)
	return table.freeze(setmetatable({ UnixTimestampMillis = ms, UnixTimestamp = math.floor(ms / 1000) }, DTMT))
end
function DTM.ToUniversalTime(self)
	local d = os.date("!*t", self.UnixTimestamp)
	return { Year = d.year, Month = d.month, Day = d.day, Hour = d.hour, Minute = d.min, Second = d.sec, Millisecond = self.UnixTimestampMillis % 1000 }
end
DTM.ToLocalTime = DTM.ToUniversalTime
function DTM.ToIsoDate(self)
	return os.date("!%Y-%m-%dT%H:%M:%SZ", self.UnixTimestamp)
end
function DTM.FormatUniversalTime(self, format, _locale)
	R.note("DateTime.Format", "DateTime:FormatUniversalTime/FormatLocalTime은 ISO 날짜를 돌려줄 뿐이다")
	return os.date("!%Y-%m-%d %H:%M:%S", self.UnixTimestamp)
end
DTM.FormatLocalTime = DTM.FormatUniversalTime
DTMT.__eq = function(a, b)
	return a.UnixTimestampMillis == b.UnixTimestampMillis
end
DTMT.__lt = function(a, b)
	return a.UnixTimestampMillis < b.UnixTimestampMillis
end
DTMT.__le = function(a, b)
	return a.UnixTimestampMillis <= b.UnixTimestampMillis
end
DTMT.__tostring = function(a)
	return tostring(a.UnixTimestampMillis)
end
local DateTime = {}
function DateTime.now()
	return DT(math.floor((R.opts.epoch + R.Sched.now) * 1000))
end
function DateTime.fromUnixTimestamp(s)
	return DT(num(s, "DateTime.fromUnixTimestamp") * 1000)
end
function DateTime.fromUnixTimestampMillis(ms)
	return DT(num(ms, "DateTime.fromUnixTimestampMillis"))
end
function DateTime.fromUniversalTime(y, mo, d, h, mi, s, ms)
	local t = os.time({ year = y or 1970, month = mo or 1, day = d or 1, hour = h or 0, min = mi or 0, sec = s or 0 })
	return DT(t * 1000 + (ms or 0))
end
DateTime.fromLocalTime = DateTime.fromUniversalTime
Types.DateTime = DateTime

-- 속성 기본값 문자열(API 덤프의 Default)을 값으로
function Types.parseDefault(tcode: string, s: string): any
	if tcode == "bool" then
		return s == "true"
	elseif tcode == "int" or tcode == "int64" or tcode == "float" or tcode == "double" then
		if s == "inf" or s == "+inf" then
			return math.huge
		elseif s == "-inf" then
			return -math.huge
		end
		return tonumber(s) or 0
	elseif tcode == "string" or tcode == "ContentId" then
		return s
	end
	local parts = {}
	for n in string.gmatch(s, "[%-%+%w%.]+") do
		if n == "inf" or n == "+inf" then
			table.insert(parts, math.huge)
		elseif n == "-inf" then
			table.insert(parts, -math.huge)
		else
			table.insert(parts, tonumber(n) or 0)
		end
	end
	if tcode == "Vector2" then
		return V2(parts[1] or 0, parts[2] or 0)
	elseif tcode == "Vector3" then
		return V3(parts[1] or 0, parts[2] or 0, parts[3] or 0)
	elseif tcode == "Color3" then
		return C3(parts[1] or 0, parts[2] or 0, parts[3] or 0)
	elseif tcode == "UDim" then
		return UD(parts[1] or 0, parts[2] or 0)
	elseif tcode == "UDim2" then
		return UD2(parts[1] or 0, parts[2] or 0, parts[3] or 0, parts[4] or 0)
	elseif tcode == "Rect" then
		return RC(parts[1] or 0, parts[2] or 0, parts[3] or 0, parts[4] or 0)
	elseif tcode == "NumberRange" then
		return NumberRange.new(parts[1] or 0, parts[2] or parts[1] or 0)
	end
	return nil
end

-- 형마다의 「빈 값」(기본값이 적혀 있지 않을 때)
function Types.zero(tcode: string): any
	if tcode == "bool" then
		return false
	elseif tcode == "int" or tcode == "int64" or tcode == "float" or tcode == "double" then
		return 0
	elseif tcode == "string" or tcode == "ContentId" or tcode == "BinaryString" or tcode == "ProtectedString" then
		return ""
	elseif tcode == "Vector2" then
		return Vector2.zero
	elseif tcode == "Vector3" then
		return Vector3.zero
	elseif tcode == "Color3" then
		return C3(0, 0, 0)
	elseif tcode == "UDim" then
		return UD(0, 0)
	elseif tcode == "UDim2" then
		return UD2(0, 0, 0, 0)
	elseif tcode == "Rect" then
		return RC(0, 0, 0, 0)
	elseif tcode == "NumberRange" then
		return NumberRange.new(0, 0)
	elseif tcode == "NumberSequence" then
		return NumberSequence.new(0)
	elseif tcode == "ColorSequence" then
		return ColorSequence.new(C3(1, 1, 1))
	elseif tcode == "Content" then
		return Content.none
	elseif tcode == "Font" then
		return Font.fromEnum(Types.enumItem("Font", "Legacy"))
	elseif tcode == "CFrame" or tcode == "CoordinateFrame" then
		return CFrame.identity
	elseif tcode == "TweenInfo" then
		return TweenInfo.new()
	elseif tcode == "BrickColor" then
		return BC("Medium stone grey", C3(0.639216, 0.635294, 0.647059))
	end
	return nil
end

-- 형 이름 → 메타테이블 (값의 형을 볼 때)
Types.MT = {
	Vector2 = V2MT,
	Vector3 = V3MT,
	UDim = UDimMT,
	UDim2 = UD2MT,
	Color3 = C3MT,
	Rect = RectMT,
	NumberRange = NRMT,
	NumberSequence = NSMT,
	ColorSequence = CSMT,
	Content = ContentMT,
	Font = FontMT,
	CFrame = CFMT,
	CoordinateFrame = CFMT,
	TweenInfo = TIMT,
	BrickColor = BCMT,
	DateTime = DTMT,
}
Types.is = is

return Types
