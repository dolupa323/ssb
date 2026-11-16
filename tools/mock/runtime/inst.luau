-- 인스턴스: API 덤프에 적힌 클래스 · 속성 · 메서드 · 이벤트만 받는다(오타는 그 자리에서 오류).
--  인스턴스 = 빈 표 + 메타테이블. 안쪽 상태(st)는 비공개 열쇠 아래에 둔다.
--  클래스마다의 동작은 다른 모듈이 Inst.hook("클래스")에 걸어 둔다(초기화 · 읽기 · 쓰기 · 메서드).
local R = require("./rt")
R.mark()
local API = require("./apidump")
local Types = require("./types")
local Sched = require("./sched")
local Signal = Sched.Signal
local raise = R.raise

local Inst = {}
R.Inst = Inst

local KEY = table.freeze({ "mock instance state" })
local InstMT = {}
Inst.MT = InstMT
Inst.KEY = KEY

local infos = {} :: { [string]: any }
local hooks = {} :: { [string]: any }
local nextId = 0
local ancestryListeners = 0

-- ---------- 클래스에 거는 것 ----------
function Inst.hook(className: string)
	local h = hooks[className]
	if not h then
		if infos[className] then
			error("mock 안쪽 오류: 클래스 " .. className .. " 는 이미 쓰였다(훅은 먼저 걸어야 한다)")
		end
		h = { defaults = {}, get = {}, set = {}, after = {}, methods = {}, layout = {}, sigCheck = {} }
		hooks[className] = h
	end
	return h
end

-- ---------- 값의 형 검사 ----------
local checkers = {} :: { [string]: any }
local function prettyType(tcode: string): string
	if string.sub(tcode, 1, 2) == "E:" then
		return "Enum." .. string.sub(tcode, 3)
	elseif string.sub(tcode, 1, 2) == "C:" then
		return string.sub(tcode, 3)
	elseif tcode == "bool" then
		return "boolean"
	elseif tcode == "int" or tcode == "int64" or tcode == "float" or tcode == "double" then
		return "number"
	elseif tcode == "ContentId" or tcode == "BinaryString" or tcode == "ProtectedString" then
		return "string"
	end
	return tcode
end
Inst.prettyType = prettyType

local function describe(v: any): string
	local t = Types.typeof(v)
	if t == "string" then
		local s = v
		if #s > 40 then
			s = string.sub(s, 1, 40) .. "…"
		end
		return 'string "' .. s .. '"'
	elseif t == "number" or t == "boolean" or t == "EnumItem" then
		return t .. " " .. tostring(v)
	elseif t == "Instance" then
		return "Instance(" .. rawget(v, KEY).class .. ")"
	end
	return t
end
Inst.describe = describe

-- 돌려주는 것: ok, 바꾼 값
local function getChecker(tcode: string)
	local c = checkers[tcode]
	if c then
		return c
	end
	local optional = false
	local base = tcode
	if string.sub(base, -1) == "?" then
		optional = true
		base = string.sub(base, 1, -2)
	end
	local f
	if base == "bool" then
		f = function(v)
			return type(v) == "boolean", v
		end
	elseif base == "int" or base == "int64" then
		f = function(v)
			if type(v) == "number" then
				if v % 1 ~= 0 then
					v = if v >= 0 then math.floor(v) else math.ceil(v)
				end
				return true, v
			elseif type(v) == "string" and tonumber(v) then
				return true, math.floor(tonumber(v) :: number)
			end
			return false, v
		end
	elseif base == "float" or base == "double" then
		f = function(v)
			if type(v) == "number" then
				return true, v
			elseif type(v) == "string" and tonumber(v) then
				return true, tonumber(v)
			end
			return false, v
		end
	elseif base == "string" or base == "ContentId" or base == "BinaryString" or base == "ProtectedString" then
		f = function(v)
			if type(v) == "string" then
				return true, v
			elseif type(v) == "number" then
				return true, tostring(v)
			end
			return false, v
		end
	elseif string.sub(base, 1, 2) == "E:" then
		local en = string.sub(base, 3)
		f = function(v)
			if Types.isEnumItem(v, en) then
				return true, v
			end
			if not R.opts.strictEnums then
				-- Roblox는 맞는 이름의 문자열 · 값의 수도 받아 준다
				local et = Types.enumType(en)
				if et then
					if type(v) == "string" then
						local it = et:FromName(v)
						if it then
							return true, it
						end
					elseif type(v) == "number" then
						local it = et:FromValue(v)
						if it then
							return true, it
						end
					end
				end
			end
			return false, v
		end
	elseif string.sub(base, 1, 2) == "C:" then
		local cn = string.sub(base, 3)
		f = function(v)
			if v == nil then
				return true, v
			end
			if type(v) == "table" and getmetatable(v) == InstMT then
				return rawget(v, KEY).info.isA[cn] == true, v
			end
			return false, v
		end
		optional = true
	elseif Types.MT[base] then
		local mt = Types.MT[base]
		if base == "Font" then
			f = function(v)
				if type(v) == "table" and getmetatable(v) == mt then
					return true, Types.cloneFont(v)
				end
				return false, v
			end
		else
			f = function(v)
				return type(v) == "table" and getmetatable(v) == mt, v
			end
		end
	elseif base == "Function" then
		f = function(v)
			return type(v) == "function", v
		end
	elseif base == "G:Array" or base == "G:Dictionary" or base == "G:Map" or base == "Instances" or base == "Objects" then
		f = function(v)
			return type(v) == "table", v
		end
	elseif base == "buffer" then
		f = function(v)
			return type(v) == "buffer", v
		end
	else
		f = function(v)
			return true, v -- 모르는 형 · Variant: 무엇이든
		end
		optional = true
	end
	c = { f = f, optional = optional, any = base == "G:Variant" or base == "G:Tuple" }
	checkers[tcode] = c
	return c
end
Inst.getChecker = getChecker

-- ---------- 클래스 정보 ----------
local function parseParams(s: string)
	local list = {}
	if s == "" then
		return list
	end
	for _, part in string.split(s, ",") do
		local name, t = string.match(part, "^(.-):(.*)$")
		local hasDefault = false
		if string.sub(t, -1) == "=" then
			hasDefault = true
			t = string.sub(t, 1, -2)
		end
		table.insert(list, { name = name, tcode = t, optional = hasDefault or string.sub(t, -1) == "?", tuple = t == "G:Tuple" })
	end
	return list
end

local function getInfo(className: string): any
	local info = infos[className]
	if info then
		return info
	end
	local raw = API.classes[className]
	if not raw then
		return nil
	end
	local lines = string.split(raw, "\n")
	local head = string.split(lines[1], "\t")
	local super = if head[1] ~= "" then getInfo(head[1]) else nil
	local tags = {}
	for _, t in string.split(head[2] or "", ",") do
		if t ~= "" then
			tags[t] = true
		end
	end
	info = {
		name = className,
		super = super,
		tags = tags,
		members = if super then table.clone(super.members) else {},
		isA = if super then table.clone(super.isA) else {},
		defaults = if super then table.clone(super.defaults) else {},
		inits = if super then table.clone(super.inits) else {},
		ancestry = if super then table.clone(super.ancestry) else {},
		clones = if super then table.clone(super.clones) else {},
		destroys = if super then table.clone(super.destroys) else {},
		sigCheck = if super then table.clone(super.sigCheck) else {},
	}
	info.isA[className] = true
	local members = info.members
	local dlines = nil :: { any }?
	for i = 2, #lines do
		local f = string.split(lines[i], "\t")
		local kind, name = f[1], f[2]
		if kind == "P" then
			local tcode, flags = f[3], f[4]
			local m = {
				kind = 1,
				name = name,
				owner = className,
				tcode = tcode,
				check = getChecker(tcode),
				readonly = string.find(flags, "r", 1, true) ~= nil,
				deprecated = string.find(flags, "d", 1, true) ~= nil,
				writeonly = string.find(flags, "w", 1, true) ~= nil,
				readSec = if f[5] ~= "" then f[5] else nil,
				writeSec = if f[6] ~= "" then f[6] else nil,
				preferred = if f[7] ~= "" then f[7] else nil,
				get = false,
				set = false,
				after = false,
				layout = false,
				guard = false,
			}
			m.guard = m.deprecated or m.writeonly or m.readSec ~= nil
			local def
			if string.find(flags, "D", 1, true) then
				if string.sub(tcode, 1, 2) == "E:" then
					def = Types.enumItem(string.sub(tcode, 3), f[8])
				else
					def = Types.parseDefault(tcode, f[8])
				end
			end
			if def == nil then
				if string.sub(tcode, 1, 2) == "E:" then
					def = Types.enumFirst(string.sub(tcode, 3))
				else
					def = Types.zero(tcode)
				end
			end
			info.defaults[name] = def
			if tcode == "Font" then
				m.get = function(st)
					local v = st.props[name]
					if v == nil then
						v = st.info.defaults[name]
					end
					return Types.cloneFont(v)
				end
			end
			members[name] = m
		elseif kind == "F" then
			members[name] = { kind = 2, name = name, owner = className, flags = f[3], sec = if f[4] ~= "" then f[4] else nil, paramText = f[5] or "", preferred = if f[6] and f[6] ~= "" then f[6] else nil, fn = false, call = false, deprecated = string.find(f[3], "d", 1, true) ~= nil, yields = string.find(f[3], "y", 1, true) ~= nil }
		elseif kind == "E" then
			members[name] = { kind = 3, name = name, owner = className, sec = if f[4] ~= "" then f[4] else nil, paramText = f[5] or "", deprecated = string.find(f[3], "d", 1, true) ~= nil, preferred = if f[6] and f[6] ~= "" then f[6] else nil }
		elseif kind == "D" then
			-- 이 클래스의 기본 속성 값(물려받은 속성 포함 — rbx-dom의 자료): 아래에서 넣는다
			if not dlines then
				dlines = {}
			end
			table.insert(dlines, f)
		else
			members[name] = { kind = 4, name = name, owner = className }
		end
	end
	-- 걸어 둔 것
	local h = hooks[className]
	if h then
		for k, v in h.defaults do
			if not members[k] or members[k].kind ~= 1 then
				error("mock 안쪽 오류: " .. className .. "." .. k .. " 는 속성이 아니다")
			end
			info.defaults[k] = v
		end
		local function own(name: string, kind: number)
			local m = members[name]
			if not m or m.kind ~= kind then
				error("mock 안쪽 오류: " .. className .. "." .. name .. " 가 API 덤프에 없다(종류 " .. kind .. ")")
			end
			if m.owner ~= className or m.hookedBy ~= className then
				m = table.clone(m)
				m.hookedBy = className
				m.call = false
				members[name] = m
			end
			return m
		end
		for k, fn in h.get do
			own(k, 1).get = fn
		end
		for k, fn in h.set do
			own(k, 1).set = fn
		end
		for k, fn in h.after do
			own(k, 1).after = fn
		end
		for _, k in h.layout do
			own(k, 1).layout = true
		end
		for k, fn in h.methods do
			own(k, 2).fn = fn
		end
		for k, fn in h.sigCheck do
			info.sigCheck[k] = fn
		end
		if h.init then
			table.insert(info.inits, h.init)
		end
		if h.ancestry then
			table.insert(info.ancestry, h.ancestry)
		end
		if h.clone then
			table.insert(info.clones, h.clone)
		end
		if h.destroy then
			table.insert(info.destroys, h.destroy)
		end
	end
	if dlines then
		for _, f in dlines do
			local m = members[f[2]]
			if m and m.kind == 1 then
				local text = f[3] or ""
				local v
				if string.sub(m.tcode, 1, 2) == "E:" then
					local et = Types.enumType(string.sub(m.tcode, 3))
					v = et and et:FromValue(tonumber(string.sub(text, 2)))
				else
					v = Types.parseDefault(m.tcode, text)
				end
				if v ~= nil then
					info.defaults[f[2]] = v
				end
			end
		end
	end
	info.isInstance = info.isA.Instance == true
	info.isGui = info.isA.GuiBase2d == true
	info.isGuiObject = info.isA.GuiObject == true
	info.isLayer = info.isA.LayerCollector == true
	info.isUI = info.isA.UIBase == true
	info.valueBase = info.isA.ValueBase == true
	info.hasAncestry = #info.ancestry > 0
	infos[className] = info
	return info
end
Inst.getInfo = getInfo

function Inst.classExists(name: string): boolean
	return API.classes[name] ~= nil
end

R.TYPEOF[InstMT] = function(v)
	return if rawget(v, KEY).info.isInstance then "Instance" else "Object"
end

-- ---------- 이름 · 길 ----------
local function fullName(st): string
	local parts = { st.name }
	local p = st.parent
	while p do
		local ps = rawget(p, KEY)
		if ps.class == "DataModel" then
			break
		end
		table.insert(parts, 1, ps.name)
		p = ps.parent
	end
	return table.concat(parts, ".")
end
Inst.fullName = fullName

local function notMember(st, key: any): never
	local hintText = ""
	if type(key) == "string" then
		hintText = R.hint(key, st.info.members)
	end
	raise(tostring(key) .. " is not a valid member of " .. st.class .. ' "' .. fullName(st) .. '"' .. hintText)
end

-- ---------- 신호 ----------
local function getSignal(st, m)
	local sigs = st.sig
	if not sigs then
		sigs = {}
		st.sig = sigs
	end
	local s = sigs[m.name]
	if not s then
		s = Signal.new(st.class .. "." .. m.name)
		local chk = st.info.sigCheck[m.name]
		if chk then
			s._check = chk
		end
		if m.name == "AncestryChanged" then
			s._onCount = function(d)
				ancestryListeners += d
			end
		end
		sigs[m.name] = s
	end
	return s
end

function Inst.signal(inst: any, name: string)
	local st = rawget(inst, KEY)
	local m = st.info.members[name]
	if not m or m.kind ~= 3 then
		error("mock 안쪽 오류: " .. st.class .. "." .. name .. " 는 이벤트가 아니다")
	end
	return getSignal(st, m)
end

-- 이벤트를 낸다(건 것이 없으면 아무 일도 없다)
function Inst.fire(inst: any, name: string, ...)
	local st = rawget(inst, KEY)
	local sigs = st.sig
	if sigs then
		local s = sigs[name]
		if s then
			Signal.fire(s, ...)
		end
	end
end
function Inst.hasListeners(inst: any, name: string): boolean
	local st = rawget(inst, KEY)
	local s = st.sig and st.sig[name]
	if not s then
		return false
	end
	return #s._h > 0 or s._w ~= false
end

local function fireChanged(st, key: string, value: any)
	local ps = st.psig
	if ps then
		local s = ps[key]
		if s then
			Signal.fire(s, value)
		end
	end
	local sigs = st.sig
	if sigs then
		local s = sigs.Changed
		if s then
			if st.info.valueBase then
				if key == "Value" then
					Signal.fire(s, value)
				end
			else
				Signal.fire(s, key)
			end
		end
	end
end
Inst.fireChanged = fireChanged

-- 엔진이 바꾸는 속성(읽기 전용 포함): 값이 달라졌으면 넣고 알린다
function Inst.setRaw(inst: any, key: string, value: any)
	local st = rawget(inst, KEY)
	local old = st.props[key]
	if old == nil then
		old = st.info.defaults[key]
	end
	if old == value then
		return false
	end
	st.props[key] = value
	if st.sig or st.psig then
		fireChanged(st, key, value)
	end
	return true
end

function Inst.getRaw(inst: any, key: string): any
	local st = rawget(inst, KEY)
	local v = st.props[key]
	if v == nil then
		v = st.info.defaults[key]
	end
	return v
end

-- ---------- 부모 바꾸기 ----------
local function eachDescendant(st, fn)
	local ch = st.children
	for i = 1, #ch do
		local cs = rawget(ch[i], KEY)
		fn(cs, ch[i])
		if #cs.children > 0 then
			eachDescendant(cs, fn)
		end
	end
end
Inst.eachDescendant = eachDescendant

local function wakeWaiters(pst, child, name: string)
	local ws = pst.waiters
	if ws then
		local list = ws[name]
		if list then
			ws[name] = nil
			for _, w in list do
				if not w.done then
					w.done = true
					Sched.deferEntry({ f = w.co, n = 1, child })
				end
			end
			if Sched.depth == 0 then
				Sched.flush()
			end
		end
	end
end

local function setParent(st, inst, newParent, internal: boolean?)
	local oldParent = st.parent
	if oldParent == newParent then
		return
	end
	if not internal then
		if st.destroyed then
			raise("The Parent property of " .. st.name .. " is locked, current parent: NULL, new parent " .. (if newParent then rawget(newParent, KEY).name else "NULL") .. " (이미 Destroy된 인스턴스)")
		end
		if st.parentLocked then
			raise("The Parent property of " .. st.name .. " is locked (" .. st.class .. ")")
		end
	end
	local nst = nil
	if newParent then
		nst = rawget(newParent, KEY)
		if newParent == inst then
			raise("Attempt to set " .. fullName(st) .. " as its own parent")
		end
		if nst.destroyed and not internal then
			-- Roblox는 받아 주지만 거의 늘 실수다
			R.note("parent-destroyed:" .. nst.class, "Destroy된 인스턴스(" .. nst.class .. " " .. nst.name .. ")를 부모로 삼았다")
		end
		local a = nst.parent
		while a do
			if a == inst then
				raise("Attempt to set parent of " .. fullName(st) .. " to " .. fullName(nst) .. " would result in circular reference")
			end
			a = rawget(a, KEY).parent
		end
	end
	-- 옛 부모에서 뗀다
	if oldParent then
		local ost = rawget(oldParent, KEY)
		-- 조상의 DescendantRemoving
		local a = oldParent
		while a do
			local as = rawget(a, KEY)
			local s = as.sig and as.sig.DescendantRemoving
			if s then
				Signal.fire(s, inst)
				eachDescendant(st, function(_, d)
					Signal.fire(s, d)
				end)
			end
			a = as.parent
		end
		local ch = ost.children
		if ch[#ch] == inst then
			ch[#ch] = nil
		else
			local i = table.find(ch, inst)
			if i then
				table.remove(ch, i)
			end
		end
		if st.info.isUI then
			ost.comps = nil
		end
		st.parent = nil
		local s = ost.sig and ost.sig.ChildRemoved
		if s then
			Signal.fire(s, inst)
		end
	end
	st.parent = newParent
	if nst then
		table.insert(nst.children, inst)
		if st.info.isUI then
			nst.comps = nil
		end
	end
	if st.info.isGui or st.info.isUI then
		R.Layout.bump()
	end
	-- 스크립트 · 화면 틀 같은 것: 조상이 바뀌었다
	if st.info.hasAncestry then
		for _, fn in st.info.ancestry do
			fn(st, inst)
		end
	end
	if #st.children > 0 then
		eachDescendant(st, function(ds, d)
			if ds.info.hasAncestry then
				for _, fn in ds.info.ancestry do
					fn(ds, d)
				end
			end
		end)
	end
	if nst then
		local s = nst.sig and nst.sig.ChildAdded
		if s then
			Signal.fire(s, inst)
		end
		local a = newParent
		while a do
			local as = rawget(a, KEY)
			local ds = as.sig and as.sig.DescendantAdded
			if ds then
				Signal.fire(ds, inst)
				eachDescendant(st, function(_, d)
					Signal.fire(ds, d)
				end)
			end
			a = as.parent
		end
		wakeWaiters(nst, inst, st.name)
	end
	if ancestryListeners > 0 then
		local s = st.sig and st.sig.AncestryChanged
		if s then
			Signal.fire(s, inst, newParent)
		end
		eachDescendant(st, function(ds, d)
			local s2 = ds.sig and ds.sig.AncestryChanged
			if s2 then
				Signal.fire(s2, inst, newParent)
			end
		end)
	end
	if st.sig or st.psig then
		fireChanged(st, "Parent", newParent)
	end
end
Inst.setParentRaw = function(inst, parent)
	setParent(rawget(inst, KEY), inst, parent, true)
end

-- ---------- 만들기 ----------
local function create(className: string): any
	local info = getInfo(className)
	if not info then
		error("mock 안쪽 오류: 없는 클래스 " .. tostring(className))
	end
	nextId += 1
	local st = {
		info = info,
		class = className,
		name = className,
		id = nextId,
		props = {},
		parent = nil,
		children = {},
		sig = false,
		psig = false,
		attrs = false,
		tags = false,
		waiters = false,
		callbacks = false,
		destroyed = false,
		parentLocked = false,
		comps = nil,
		lv = 0,
	}
	local inst = setmetatable({ [KEY] = st }, InstMT)
	st.self = inst
	for _, fn in info.inits do
		fn(st, inst)
	end
	return inst
end
Inst.create = create

function Inst.st(inst: any)
	return rawget(inst, KEY)
end
function Inst.is(v: any): boolean
	return type(v) == "table" and getmetatable(v) == InstMT
end
function Inst.isA(v: any, className: string): boolean
	return type(v) == "table" and getmetatable(v) == InstMT and rawget(v, KEY).info.isA[className] == true
end

local NOT_NEW = { DataModel = true, Player = true, PlayerGui = true, PlayerScripts = true }
function Inst.new(className: any, parent: any)
	if type(className) ~= "string" then
		raise("Instance.new: 클래스 이름(문자열)이 와야 하는데 " .. describe(className) .. "이(가) 왔다")
	end
	local info = getInfo(className)
	if not info then
		raise('Unable to create an Instance of type "' .. className .. '" (없는 클래스)' .. R.hint(className, API.classes))
	end
	if info.tags.NotCreatable or info.tags.Service or NOT_NEW[className] or not info.isInstance then
		raise('Unable to create an Instance of type "' .. className .. '" (Instance.new로 만들 수 없는 클래스)')
	end
	if parent ~= nil and not Inst.is(parent) then
		raise("Instance.new: 둘째 인자(부모)는 Instance여야 하는데 " .. describe(parent) .. "이(가) 왔다")
	end
	local inst = create(className)
	if R.onCreate then
		R.onCreate(inst, className)
	end
	if parent then
		setParent(rawget(inst, KEY), inst, parent)
	end
	return inst
end

-- ---------- 메서드 부르기 ----------
local function unimplemented(st, m)
	R.note("method:" .. m.owner .. "." .. m.name, m.owner .. ":" .. m.name .. "() 은 mock이 흉내 내지 않는다 — 아무것도 하지 않고 nil을 돌려준다")
	return nil
end

-- API 덤프에 「없어도 된다」고 적혀 있지 않지만 실제로는 빼도 되는 인자
local OPTIONAL_ARGS = {
	["Instance.WaitForChild"] = { [2] = true },
	["GlobalDataStore.GetAsync"] = { [2] = true },
	["RunService.BindToRenderStep"] = {},
}

local function makeCall(m)
	local plist = parseParams(m.paramText)
	local nparams = #plist
	local opt = OPTIONAL_ARGS[m.owner .. "." .. m.name]
	for i, p in plist do
		p.check = getChecker(p.tcode)
		if opt and opt[i] then
			p.optional = true
		end
	end
	local owner = m.owner
	local name = m.name
	local call = function(self, ...)
		if type(self) ~= "table" or getmetatable(self) ~= InstMT then
			raise("Expected ':' not '.' calling member function " .. name)
		end
		local st = rawget(self, KEY)
		if not st.info.isA[owner] then
			raise("Expected ':' not '.' calling member function " .. name .. " (" .. st.class .. "는 " .. owner .. "가 아니다)")
		end
		if m.sec then
			raise("The current thread cannot call '" .. name .. "' (lacking capability " .. m.sec .. ")")
		end
		if m.deprecated then
			R.note("deprecated:" .. owner .. "." .. name, owner .. ":" .. name .. " 은 이제 쓰지 않는(deprecated) 메서드다" .. (if m.preferred then " — " .. m.preferred .. " 를 쓴다" else ""))
		end
		if nparams > 0 then
			local argc = select("#", ...)
			for i = 1, nparams do
				local p = plist[i]
				if p.tuple then
					break
				end
				local v = if i <= argc then (select(i, ...)) else nil
				local chk = p.check
				if v == nil then
					if not (p.optional or chk.optional) then
						raise("Argument " .. i .. " missing or nil (" .. st.class .. ":" .. name .. " 의 " .. p.name .. ": " .. prettyType(p.tcode) .. ")")
					end
				elseif not chk.f(v) then
					raise(st.class .. ":" .. name .. " 의 인자 " .. i .. "(" .. p.name .. "): " .. prettyType(p.tcode) .. "이(가) 와야 하는데 " .. describe(v) .. "이(가) 왔다")
				end
			end
		end
		-- 구현은 그 인스턴스의 클래스에서 찾는다(아래 클래스가 다시 걸었을 수 있다)
		local mm = st.info.members[name]
		local fn = mm.fn
		if not fn and mm.preferred then
			local pm = st.info.members[mm.preferred]
			fn = pm and pm.kind == 2 and pm.fn
		end
		if not fn then
			return unimplemented(st, mm)
		end
		return fn(st, self, ...)
	end
	m.call = call
	return call
end

-- ---------- 읽기 · 쓰기 ----------
local function guardRead(st, m)
	if m.readSec then
		raise("The current thread cannot access '" .. fullName(st) .. "." .. m.name .. "' (lacking capability " .. m.readSec .. ")")
	end
	if m.writeonly then
		raise(m.name .. " is a write-only member of " .. st.class)
	end
	if m.deprecated then
		R.note("deprecated:" .. m.owner .. "." .. m.name, m.owner .. "." .. m.name .. " 은 이제 쓰지 않는(deprecated) 속성이다" .. (if m.preferred then " — " .. m.preferred .. " 를 쓴다" else ""))
	end
end

InstMT.__index = function(self, key)
	local st = rawget(self, KEY)
	local m = st.info.members[key]
	if m then
		local kind = m.kind
		if kind == 1 then
			if m.guard then
				guardRead(st, m)
			end
			local g = m.get
			if g then
				return g(st, self, m)
			end
			local v = st.props[key]
			if v == nil then
				v = st.info.defaults[key]
			end
			return v
		elseif kind == 2 then
			return m.call or makeCall(m)
		elseif kind == 3 then
			if m.sec then
				raise("The current thread cannot access '" .. fullName(st) .. "." .. m.name .. "' (lacking capability " .. m.sec .. ")")
			end
			return getSignal(st, m)
		else
			raise(tostring(key) .. " is a callback member of " .. st.class .. "; you can only set the callback value, get is not available")
		end
	end
	-- 아이의 이름
	local ch = st.children
	for i = 1, #ch do
		local c = ch[i]
		if rawget(c, KEY).name == key then
			return c
		end
	end
	return notMember(st, key)
end

InstMT.__newindex = function(self, key, value)
	local st = rawget(self, KEY)
	local m = st.info.members[key]
	if not m then
		notMember(st, key)
	end
	if m.kind ~= 1 then
		if m.kind == 4 then
			if value ~= nil and type(value) ~= "function" then
				raise("Unable to assign callback " .. key .. ". function expected, got " .. describe(value))
			end
			local chk = st.info.sigCheck[key]
			if chk then
				chk(Sched.ctx, nil)
			end
			if not st.callbacks then
				st.callbacks = {}
			end
			st.callbacks[key] = if value then { fn = value, ctx = Sched.ctx } else nil
			local ws = st.cbWaiters and st.cbWaiters[key]
			if ws and value then
				st.cbWaiters[key] = nil
				for _, co in ws do
					Sched.deferEntry({ f = co, n = 0 })
				end
			end
			return
		end
		raise(tostring(key) .. " is not a valid member of " .. st.class .. ' "' .. fullName(st) .. '" (' .. (if m.kind == 2 then "메서드" else "이벤트") .. "에는 값을 넣을 수 없다)")
	end
	if m.readonly then
		raise("Unable to assign property " .. key .. ". Property is read only")
	end
	if m.writeSec then
		raise("The current thread cannot write '" .. fullName(st) .. "." .. key .. "' (lacking capability " .. m.writeSec .. ")")
	end
	if m.deprecated then
		R.note("deprecated:" .. m.owner .. "." .. m.name, m.owner .. "." .. m.name .. " 은 이제 쓰지 않는(deprecated) 속성이다" .. (if m.preferred then " — " .. m.preferred .. " 를 쓴다" else ""))
	end
	local chk = m.check
	if value == nil then
		if not chk.optional then
			raise("Unable to assign property " .. key .. ". " .. prettyType(m.tcode) .. " expected, got nil")
		end
	else
		local ok, v = chk.f(value)
		if not ok then
			local extra = ""
			if string.sub(m.tcode, 1, 2) == "E:" and Types.typeof(value) == "EnumItem" then
				extra = " (다른 열거형의 값이다)"
			elseif string.sub(m.tcode, 1, 2) == "E:" and R.opts.strictEnums and (type(value) == "string" or type(value) == "number") then
				extra = " (Roblox는 맞는 이름의 문자열 · 수를 받아 주지만 mock은 막는다 — --lenient-enums 로 풀 수 있다)"
			end
			raise("Unable to assign property " .. key .. ". " .. prettyType(m.tcode) .. " expected, got " .. describe(value) .. extra)
		end
		value = v
	end
	local setter = m.set
	if setter then
		setter(st, self, value, m)
		return
	end
	local props = st.props
	local old = props[key]
	if old == nil then
		old = st.info.defaults[key]
	end
	if old == value then
		return
	end
	props[key] = value
	local after = m.after
	if after then
		after(st, self, value, old, m)
	end
	if m.layout then
		R.Layout.bump()
	end
	if st.sig or st.psig then
		fireChanged(st, key, value)
	end
end

InstMT.__tostring = function(self)
	return rawget(self, KEY).name
end

-- ---------- Object · Instance의 기본 동작 ----------
local OBJ = Inst.hook("Object")
OBJ.get.ClassName = function(st)
	return st.class
end
OBJ.get.className = OBJ.get.ClassName

local function knownClass(name: any, what: string)
	if type(name) == "string" and not API.classes[name] then
		R.note("class:" .. name, what .. ': "' .. name .. '" 은 없는 클래스 이름이다' .. R.hint(name, API.classes))
	end
end

OBJ.methods.IsA = function(st, _, className)
	knownClass(className, "IsA")
	return st.info.isA[className] == true
end
OBJ.methods.GetPropertyChangedSignal = function(st, _, prop)
	local m = st.info.members[prop]
	if not m or m.kind ~= 1 then
		raise(tostring(prop) .. " is not a valid property name. (" .. st.class .. ")" .. R.hint(prop, st.info.members))
	end
	local ps = st.psig
	if not ps then
		ps = {}
		st.psig = ps
	end
	local s = ps[prop]
	if not s then
		s = Signal.new(st.class .. "." .. prop .. " changed")
		ps[prop] = s
	end
	return s
end

local INS = Inst.hook("Instance")
INS.defaults.Archivable = true
INS.get.Name = function(st)
	return st.name
end
INS.set.Name = function(st, inst, value)
	if st.name == value then
		return
	end
	st.name = value
	if st.info.isGui then
		R.Layout.bump()
	end
	if st.sig or st.psig then
		fireChanged(st, "Name", value)
	end
	if st.parent then
		wakeWaiters(rawget(st.parent, KEY), inst, value)
	end
end
INS.get.Parent = function(st)
	return st.parent
end
INS.set.Parent = function(st, inst, value)
	setParent(st, inst, value)
end

local function findChild(st, name: string, recursive: boolean?)
	local ch = st.children
	for i = 1, #ch do
		if rawget(ch[i], KEY).name == name then
			return ch[i]
		end
	end
	if recursive then
		for i = 1, #ch do
			local r = findChild(rawget(ch[i], KEY), name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
Inst.findChild = function(inst, name, recursive)
	return findChild(rawget(inst, KEY), name, recursive)
end

INS.methods.FindFirstChild = function(st, _, name, recursive)
	return findChild(st, name, recursive)
end
INS.methods.FindFirstDescendant = function(st, _, name)
	return findChild(st, name, true)
end
INS.methods.GetChildren = function(st)
	return table.clone(st.children)
end
local function collect(st, out)
	local ch = st.children
	for i = 1, #ch do
		table.insert(out, ch[i])
		local cs = rawget(ch[i], KEY)
		if #cs.children > 0 then
			collect(cs, out)
		end
	end
	return out
end
INS.methods.GetDescendants = function(st)
	return collect(st, {})
end
INS.methods.FindFirstChildOfClass = function(st, _, className)
	knownClass(className, "FindFirstChildOfClass")
	for _, c in st.children do
		if rawget(c, KEY).class == className then
			return c
		end
	end
	return nil
end
local function findWhichIsA(st, className: string, recursive: boolean?)
	for _, c in st.children do
		if rawget(c, KEY).info.isA[className] then
			return c
		end
	end
	if recursive then
		for _, c in st.children do
			local r = findWhichIsA(rawget(c, KEY), className, true)
			if r then
				return r
			end
		end
	end
	return nil
end
INS.methods.FindFirstChildWhichIsA = function(st, _, className, recursive)
	knownClass(className, "FindFirstChildWhichIsA")
	return findWhichIsA(st, className, recursive)
end
INS.methods.FindFirstAncestor = function(st, _, name)
	local p = st.parent
	while p do
		local ps = rawget(p, KEY)
		if ps.name == name then
			return p
		end
		p = ps.parent
	end
	return nil
end
INS.methods.FindFirstAncestorOfClass = function(st, _, className)
	knownClass(className, "FindFirstAncestorOfClass")
	local p = st.parent
	while p do
		local ps = rawget(p, KEY)
		if ps.class == className then
			return p
		end
		p = ps.parent
	end
	return nil
end
INS.methods.FindFirstAncestorWhichIsA = function(st, _, className)
	knownClass(className, "FindFirstAncestorWhichIsA")
	local p = st.parent
	while p do
		local ps = rawget(p, KEY)
		if ps.info.isA[className] then
			return p
		end
		p = ps.parent
	end
	return nil
end
local function isDescendantOf(st, ancestor): boolean
	local p = st.parent
	while p do
		if p == ancestor then
			return true
		end
		p = rawget(p, KEY).parent
	end
	return false
end
Inst.isDescendantOf = function(inst, ancestor)
	return isDescendantOf(rawget(inst, KEY), ancestor)
end
INS.methods.IsDescendantOf = function(st, _, ancestor)
	if ancestor == nil then
		return false
	end
	return isDescendantOf(st, ancestor)
end
INS.methods.IsAncestorOf = function(_, inst, descendant)
	if descendant == nil then
		return false
	end
	return isDescendantOf(rawget(descendant, KEY), inst)
end
INS.methods.GetFullName = function(st)
	return fullName(st)
end

INS.methods.WaitForChild = function(st, inst, name, timeout)
	local found = findChild(st, name, false)
	if found then
		return found
	end
	if timeout ~= nil and timeout <= 0 then
		return nil
	end
	Sched.mustYield(st.name .. ':WaitForChild("' .. tostring(name) .. '")')
	local co = coroutine.running()
	local w = { co = co, done = false }
	if not st.waiters then
		st.waiters = {}
	end
	local list = st.waiters[name]
	if not list then
		list = {}
		st.waiters[name] = list
	end
	table.insert(list, w)
	local where = debug.traceback("", 2)
	if timeout then
		Sched.after(timeout, nil, function()
			if not w.done then
				w.done = true
				Sched.resume(co, nil)
			end
		end)
	else
		Sched.after(5, nil, function()
			if not w.done then
				R.warn("Infinite yield possible on '" .. fullName(st) .. ':WaitForChild("' .. tostring(name) .. "\")'", R.cleanTrace(where))
			end
		end)
	end
	return coroutine.yield()
end

local function destroy(st, inst)
	if st.destroyed then
		return
	end
	local s = st.sig and st.sig.Destroying
	if s then
		Signal.fireForced(s)
	end
	st.destroyed = true
	setParent(st, inst, nil, true)
	for _, fn in st.info.destroys do
		fn(st, inst)
	end
	local ch = table.clone(st.children)
	for i = 1, #ch do
		destroy(rawget(ch[i], KEY), ch[i])
	end
	if st.sig then
		for _, sg in st.sig do
			Signal.disconnectAll(sg)
		end
	end
	if st.psig then
		for _, sg in st.psig do
			Signal.disconnectAll(sg)
		end
	end
end
Inst.destroy = function(inst)
	destroy(rawget(inst, KEY), inst)
end
INS.methods.Destroy = function(st, inst)
	if st.parentLocked then
		raise("The Parent property of " .. st.name .. " is locked (" .. st.class .. "는 Destroy할 수 없다)")
	end
	destroy(st, inst)
end
INS.methods.Remove = function(st, inst)
	setParent(st, inst, nil)
end
INS.methods.ClearAllChildren = function(st)
	local ch = table.clone(st.children)
	for i = 1, #ch do
		local cs = rawget(ch[i], KEY)
		if not cs.parentLocked then
			destroy(cs, ch[i])
		end
	end
end

local function clone(st, map)
	local v = st.props.Archivable
	if v == false then
		return nil
	end
	local copy = create(st.class)
	local cs = rawget(copy, KEY)
	cs.name = st.name
	cs.props = table.clone(st.props)
	if st.attrs then
		cs.attrs = table.clone(st.attrs)
	end
	if st.tags then
		cs.tags = table.clone(st.tags)
	end
	map[st.self] = copy
	for _, fn in st.info.clones do
		fn(st, cs, copy)
	end
	for _, c in st.children do
		local cc = clone(rawget(c, KEY), map)
		if cc then
			local ccs = rawget(cc, KEY)
			ccs.parent = copy
			table.insert(cs.children, cc)
		end
	end
	return copy
end
INS.methods.Clone = function(st, inst)
	local map = {}
	local copy = clone(st, map)
	if not copy then
		return nil
	end
	-- 복사한 나무 안을 가리키던 것은 복사본을 가리키게
	local function fix(cs)
		for k, v in cs.props do
			if type(v) == "table" and getmetatable(v) == InstMT and map[v] then
				cs.props[k] = map[v]
			end
		end
		for _, c in cs.children do
			fix(rawget(c, KEY))
		end
	end
	fix(rawget(copy, KEY))
	if R.onCreate then
		R.onCreate(copy, st.class)
	end
	return copy
end

-- 속성(Attribute)
local ATTR_TYPES = { string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true, Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Rect = true, Font = true, EnumItem = true }
local function attrSignal(st, name: string)
	if not st.asig then
		st.asig = {}
	end
	local s = st.asig[name]
	if not s then
		s = Signal.new(st.class .. " attribute " .. name)
		st.asig[name] = s
	end
	return s
end
INS.methods.SetAttribute = function(st, inst, name, value)
	if #name == 0 or #name > 100 or string.find(name, "[^%w_]") then
		raise('Attribute name "' .. name .. '" 은 쓸 수 없다(영문 · 숫자 · 밑줄, 100자까지)')
	end
	if string.sub(name, 1, 3) == "RBX" then
		raise('Attribute name "' .. name .. '": RBX로 시작하는 이름은 쓸 수 없다')
	end
	local t = Types.typeof(value)
	if value ~= nil and not ATTR_TYPES[t] then
		raise(t .. " is not a supported attribute type (" .. st.class .. ':SetAttribute("' .. name .. '"))')
	end
	if not st.attrs then
		st.attrs = {}
	end
	if st.attrs[name] == value then
		return
	end
	st.attrs[name] = value
	if st.asig and st.asig[name] then
		Signal.fire(st.asig[name])
	end
	local s = st.sig and st.sig.AttributeChanged
	if s then
		Signal.fire(s, name)
	end
end
INS.methods.GetAttribute = function(st, _, name)
	return if st.attrs then st.attrs[name] else nil
end
INS.methods.GetAttributes = function(st)
	return if st.attrs then table.clone(st.attrs) else {}
end
INS.methods.GetAttributeChangedSignal = function(st, _, name)
	return attrSignal(st, name)
end

-- 꼬리표(Tag)
Inst.tagged = {} :: { [string]: { [any]: boolean } }
Inst.tagSignals = {} :: { [string]: any }
INS.methods.AddTag = function(st, inst, tag)
	if not st.tags then
		st.tags = {}
	end
	if st.tags[tag] then
		return
	end
	st.tags[tag] = true
	local set = Inst.tagged[tag]
	if not set then
		set = {}
		Inst.tagged[tag] = set
	end
	set[inst] = true
	local s = Inst.tagSignals["+" .. tag]
	if s then
		Signal.fire(s, inst)
	end
end
INS.methods.RemoveTag = function(st, inst, tag)
	if st.tags and st.tags[tag] then
		st.tags[tag] = nil
		if Inst.tagged[tag] then
			Inst.tagged[tag][inst] = nil
		end
		local s = Inst.tagSignals["-" .. tag]
		if s then
			Signal.fire(s, inst)
		end
	end
end
INS.methods.HasTag = function(st, _, tag)
	return st.tags ~= false and st.tags[tag] == true
end
INS.methods.GetTags = function(st)
	local out = {}
	if st.tags then
		for t in st.tags do
			table.insert(out, t)
		end
		table.sort(out)
	end
	return out
end
INS.clone = function(src, dst, copy)
	if src.tags then
		for t in src.tags do
			local set = Inst.tagged[t]
			if set then
				set[copy] = true
			end
		end
	end
end

-- 콜백(OnInvoke 같은 것)을 읽는다
function Inst.callback(inst: any, name: string)
	local st = rawget(inst, KEY)
	return st.callbacks and st.callbacks[name]
end

-- 길로 찾기: "A.B.C" (root 아래)
function Inst.byPath(root: any, path: string): any
	local cur = root
	for part in string.gmatch(path, "[^%.]+") do
		if cur == nil then
			return nil
		end
		cur = findChild(rawget(cur, KEY), part, false)
	end
	return cur
end

return Inst
