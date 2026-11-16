-- 서비스 흉내: DataModel(game) · Players · RunService · StarterGui · TweenService · 원격 이벤트 · DataStore ·
--  HttpService · TextService · ContentProvider · Sound · Workspace · AssetService · 그 밖의 것(빈 껍데기).
local R = require("./rt")
R.mark()
local API = require("./apidump")
local Types = require("./types")
local Sched = require("./sched")
local Inst = require("./inst")
local Layout = require("./layout")
local Gui = require("./gui")
local Json = require("./json")
local Signal = Sched.Signal
local raise = R.raise
local V2 = Types.V2
local E = Types.enumItem

local Services = {}
R.Services = Services

local function ctxName(): string
	return if Sched.ctx then Sched.ctx.name else "?"
end
local function isServer(): boolean
	return Sched.ctx ~= nil and Sched.ctx.server
end
local function isClient(): boolean
	return Sched.ctx ~= nil and Sched.ctx.client
end
local function serverOnly(what: string)
	if not isServer() then
		raise(what .. " 은 서버에서만 쓸 수 있다(지금: " .. ctxName() .. ")")
	end
end
local function clientOnly(what: string)
	if not isClient() then
		raise(what .. " 은 클라이언트(LocalScript)에서만 쓸 수 있다(지금: " .. ctxName() .. ")")
	end
end

-- ================= DataModel =================
local game
local EAGER = { "Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Chat", "Teams", "TextChatService", "LocalizationService", "TestService" }
local SERVICE_NAME = { RunService = "Run Service" }
local services = {} :: { [string]: any }

local function makeService(className: string)
	local inst = Inst.create(className)
	local st = Inst.st(inst)
	st.name = SERVICE_NAME[className] or className
	Inst.setParentRaw(inst, game)
	st.parentLocked = true
	services[className] = inst
	return inst
end

local function getService(className: any)
	if type(className) ~= "string" then
		raise("GetService: 서비스 이름(문자열)이 와야 하는데 " .. Inst.describe(className) .. "이(가) 왔다")
	end
	local s = services[className]
	if s then
		return s
	end
	local info = Inst.getInfo(className)
	if not info or not info.tags.Service then
		local names = {}
		for n, raw in API.classes do
			if string.find(string.match(raw, "^[^\n]*") or "", "Service", 1, true) then
				names[n] = true
			end
		end
		raise("'" .. className .. "' is not a valid Service name" .. R.hint(className, names))
	end
	return makeService(className)
end
Services.get = getService

do
	local h = Inst.hook("ServiceProvider")
	h.methods.GetService = function(_, _, name)
		return getService(name)
	end
	h.methods.FindService = function(_, _, name)
		return services[name]
	end
	local dm = Inst.hook("DataModel")
	dm.get.Workspace = function()
		return services.Workspace
	end
	dm.get.workspace = dm.get.Workspace
	dm.get.RunService = function()
		return getService("RunService")
	end
	dm.methods.IsLoaded = function()
		return true
	end
	dm.methods.BindToClose = function(_, _, fn)
		serverOnly("game:BindToClose")
		table.insert(Services.closeBinds, { fn = fn, ctx = Sched.ctx })
	end
end
Services.closeBinds = {}

-- ================= 스크립트 =================
local sources = {} :: { any } -- { file, src, fn }
Services.sources = sources
local PREFIX = "local script,require,typeof,type=...;"

local function compile(index: number)
	local s = sources[index]
	if s.fn ~= nil then
		return s.fn
	end
	-- 첫 「--!」 아닌 줄의 맨 앞에 넣는다(줄 번호가 밀리지 않게)
	local src = s.src
	local at = 1
	while string.sub(src, at, at + 2) == "--!" do
		local nl = string.find(src, "\n", at, true)
		if not nl then
			at = #src + 1
			break
		end
		at = nl + 1
	end
	local text = string.sub(src, 1, at - 1) .. PREFIX .. string.sub(src, at)
	local fn, err = loadstring(text, "=" .. s.file)
	if not fn then
		s.fn = false
		R.onError({ message = tostring(err), traceback = "", ctx = "compile", note = "문법 오류" })
		return false
	end
	s.fn = fn
	return fn
end

local function resolveString(from, path: string)
	local cur
	local rest
	if string.sub(path, 1, 6) == "@self/" then
		cur, rest = from, string.sub(path, 7)
	elseif path == "@self" then
		return from
	elseif string.sub(path, 1, 6) == "@game/" then
		cur, rest = game, string.sub(path, 7)
	elseif string.sub(path, 1, 2) == "./" then
		cur, rest = from.Parent, string.sub(path, 3)
	elseif string.sub(path, 1, 3) == "../" then
		cur, rest = from.Parent, path
	else
		raise('require("' .. path .. '"): 길은 ./ · ../ · @self/ · @game/ 로 시작해야 한다')
	end
	for part in string.gmatch(rest, "[^/]+") do
		if cur == nil then
			break
		end
		if part == ".." then
			cur = cur.Parent
		elseif part ~= "." then
			local name = string.gsub(part, "%.luau?$", "")
			cur = Inst.findChild(cur, name, false)
		end
	end
	if cur == nil then
		raise('require("' .. path .. '"): ' .. from:GetFullName() .. " 에서 그 길의 모듈을 찾지 못했다")
	end
	return cur
end

local function doRequire(from, target)
	if type(target) == "string" then
		target = resolveString(from, target)
	elseif type(target) == "number" then
		raise("require(" .. target .. "): 에셋 번호로 부르는 것은 mock이 흉내 내지 않는다")
	end
	if not Inst.isA(target, "ModuleScript") then
		raise("Attempted to call require with invalid argument(s). (" .. Inst.describe(target) .. " — ModuleScript가 와야 한다)")
	end
	local ctx = Sched.ctx or Sched.contexts.harness
	local cache = ctx.modules
	local entry = cache[target]
	if entry then
		if entry.done then
			if entry.failed then
				raise("Requested module experienced an error while loading (" .. target:GetFullName() .. ")")
			end
			return entry.value
		end
		if entry.thread == coroutine.running() then
			raise("Requested module was required recursively (" .. target:GetFullName() .. " ← " .. from:GetFullName() .. ")")
		end
		-- 다른 스레드가 읽는 중: 끝날 때까지 기다린다
		Sched.mustYield("require(" .. target.Name .. ")")
		table.insert(entry.waiters, coroutine.running())
		coroutine.yield()
		if entry.failed then
			raise("Requested module experienced an error while loading (" .. target:GetFullName() .. ")")
		end
		return entry.value
	end
	local st = Inst.st(target)
	if not st.source then
		raise("require: " .. target:GetFullName() .. " 에는 소스가 없다(코드로 만든 빈 ModuleScript)")
	end
	local fn = compile(st.source)
	if not fn then
		cache[target] = { done = true, failed = true }
		raise("Requested module experienced an error while loading (" .. target:GetFullName() .. " — 문법 오류)")
	end
	entry = { done = false, thread = coroutine.running(), waiters = {} }
	cache[target] = entry
	local results = table.pack(xpcall(fn, function(e)
		-- 모듈 안에서 난 오류의 자리를 적어 둔다(다시 던지면 역추적이 끊긴다)
		Sched.keepTrace(e, debug.traceback("", 2))
		return e
	end, target, function(t)
		return doRequire(target, t)
	end, Types.typeof, Types.type))
	entry.done = true
	local function wake()
		for _, co in entry.waiters do
			Sched.deferEntry({ f = co, n = 0 })
		end
	end
	if not results[1] then
		entry.failed = true
		wake()
		error(results[2], 0)
	end
	if results.n ~= 2 then
		entry.failed = true
		wake()
		raise("Module code did not return exactly one value (" .. target:GetFullName() .. " — 돌려준 값 " .. (results.n - 1) .. "개)")
	end
	entry.value = results[2]
	wake()
	return entry.value
end
Services.require = doRequire

Services.running = { server = false, client = false }

local function scriptSide(st, inst): string?
	-- 이 스크립트가 지금 자리에서 어느 쪽으로 도는가 (nil = 돌지 않는다)
	if Layout.P(st, "Disabled") or Layout.P(st, "Enabled") == false then
		return nil
	end
	local rc = Layout.P(st, "RunContext").Name
	local function under(className: string): boolean
		local p = st.parent
		while p do
			local ps = Inst.st(p)
			if ps.class == className then
				return true
			end
			p = ps.parent
		end
		return false
	end
	if not Inst.isDescendantOf(inst, game) then
		return nil
	end
	if st.class == "LocalScript" or rc == "Client" then
		if under("PlayerScripts") or under("PlayerGui") or under("Backpack") or under("ReplicatedFirst") then
			return "client"
		end
		if rc == "Client" and (under("ReplicatedStorage") or under("Workspace")) then
			return "client"
		end
		return nil
	end
	if rc == "Server" then
		if under("ServerScriptService") or under("Workspace") or under("ReplicatedStorage") then
			return "server"
		end
		return nil
	end
	if under("ServerScriptService") or under("Workspace") then
		return "server"
	end
	return nil
end

local function startScript(st, inst)
	if st.started or not st.source then
		return
	end
	local side = scriptSide(st, inst)
	if not side or not Services.running[side] then
		return
	end
	st.started = true
	local fn = compile(st.source)
	if not fn then
		return
	end
	Sched.spawn(Sched.contexts[side], fn, inst, function(t)
		return doRequire(inst, t)
	end, Types.typeof, Types.type)
end
Services.startScript = startScript

do
	local h = Inst.hook("LuaSourceContainer")
	h.init = function(st)
		st.source = false
		st.started = false
	end
	h.clone = function(src, dst)
		dst.source = src.source
	end
	local bs = Inst.hook("BaseScript")
	bs.defaults.Enabled = true
	bs.ancestry = function(st, inst)
		if not st.started and (Services.running.server or Services.running.client) then
			startScript(st, inst)
		end
	end
end

function Services.startScriptsUnder(root)
	Inst.eachDescendant(Inst.st(root), function(st, inst)
		if st.info.isA.BaseScript then
			startScript(st, inst)
		end
	end)
end

-- ================= Players =================
do
	local h = Inst.hook("Players")
	h.get.LocalPlayer = function()
		if Sched.ctx and Sched.ctx.client then
			return R.player
		end
		return nil
	end
	h.get.localPlayer = h.get.LocalPlayer
	h.defaults.CharacterAutoLoads = true
	h.defaults.RespawnTime = 5
	h.get.MaxPlayers = function()
		return 1
	end
	h.methods.GetPlayers = function(st)
		local out = {}
		for _, c in st.children do
			if Inst.isA(c, "Player") then
				table.insert(out, c)
			end
		end
		return out
	end
	h.methods.GetPlayerByUserId = function(st, _, userId)
		for _, c in st.children do
			if Inst.isA(c, "Player") and c.UserId == userId then
				return c
			end
		end
		return nil
	end
	h.methods.GetPlayerFromCharacter = function()
		return nil
	end
	h.methods.GetNameFromUserIdAsync = function(_, _, userId)
		return "Player" .. tostring(userId)
	end
	h.methods.GetUserIdFromNameAsync = function(_, _, name)
		return tonumber(string.match(name, "%d+")) or 1
	end
	h.methods.GetUserThumbnailAsync = function(_, _, userId)
		return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150", true
	end
	local p = Inst.hook("Player")
	p.methods.GetMouse = function(st)
		clientOnly("Player:GetMouse")
		if not st.mouse then
			st.mouse = Inst.create("PlayerMouse")
		end
		return st.mouse
	end
	p.methods.Kick = function(st, inst, message)
		R.warn("Player:Kick(" .. tostring(message or "") .. ") — " .. st.name .. " 을(를) 내보냈다", "")
		Services.removePlayer(inst)
	end
	p.methods.GetJoinData = function()
		return {}
	end
	p.methods.GetNetworkPing = function()
		return 0.05
	end
	p.methods.IsInGroupAsync = function()
		return false
	end
	p.methods.IsFriendsWithAsync = function()
		return false
	end
	p.methods.HasAppearanceLoaded = function()
		return false
	end
	p.methods.LoadCharacterAsync = function()
		R.note("character", "캐릭터(3D)는 흉내 내지 않는다 — LoadCharacter는 아무것도 하지 않고 CharacterAdded도 나지 않는다")
	end
	p.defaults.LocaleId = "ko-kr"
	local pg = Inst.hook("BasePlayerGui")
	pg.methods.GetGuiObjectsAtPosition = function(_, _, x, y)
		local out = {}
		for _, e in Layout.hitList(x, y) do
			table.insert(out, e.st.self)
		end
		return out
	end
	local pm = Inst.hook("Mouse")
	pm.get.X = function()
		return R.Input.mouseX
	end
	pm.get.Y = function()
		return R.Input.mouseY - R.opts.insetTop
	end
	pm.get.ViewSizeX = function()
		return R.opts.viewW
	end
	pm.get.ViewSizeY = function()
		return R.opts.viewH - R.opts.insetTop
	end
end

function Services.addPlayer(userId: number, name: string)
	local players = services.Players
	local player = Inst.create("Player")
	local st = Inst.st(player)
	st.name = name
	st.props.UserId = userId
	st.props.DisplayName = name
	st.props.AccountAge = 365
	local pg = Inst.create("PlayerGui")
	Inst.setParentRaw(pg, player)
	local ps = Inst.create("PlayerScripts")
	Inst.setParentRaw(ps, player)
	local bp = Inst.create("Backpack")
	Inst.setParentRaw(bp, player)
	Inst.setParentRaw(player, players)
	st.parentLocked = true
	R.player = player
	R.playerGui = pg
	Layout.bump()
	return player
end

function Services.removePlayer(player)
	if not player or Inst.st(player).removed then
		return
	end
	Inst.st(player).removed = true
	Inst.fire(services.Players, "PlayerRemoving", player, E("PlayerExitReason", "Unknown"))
	Sched.flush()
	Inst.st(player).parentLocked = false
	Inst.setParentRaw(player, nil)
end

-- ================= RunService =================
local renderBinds = {} :: { any }
do
	local h = Inst.hook("RunService")
	h.methods.IsClient = function()
		return isClient()
	end
	h.methods.IsServer = function()
		return Sched.ctx ~= nil and Sched.ctx.server and not Sched.ctx.harness
	end
	h.methods.IsStudio = function()
		return R.opts.studio == true
	end
	h.methods.IsRunning = function()
		return true
	end
	h.methods.IsRunMode = function()
		return false
	end
	h.methods.IsEdit = function()
		return false
	end
	h.get.FrameNumber = function()
		return Sched.frame
	end
	h.methods.BindToRenderStep = function(_, _, name, priority, fn)
		clientOnly("RunService:BindToRenderStep")
		table.insert(renderBinds, { name = name, priority = priority, fn = fn, ctx = Sched.ctx, seq = #renderBinds })
		table.sort(renderBinds, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.seq < b.seq
		end)
	end
	h.methods.UnbindFromRenderStep = function(_, _, name)
		local found = false
		for i = #renderBinds, 1, -1 do
			if renderBinds[i].name == name then
				table.remove(renderBinds, i)
				found = true
			end
		end
		if not found then
			R.warn('RunService:UnbindFromRenderStep("' .. tostring(name) .. '"): 그 이름으로 건 것이 없다', "")
		end
	end
	local function renderOnly(ctx)
		if ctx and not ctx.client then
			raise("RenderStepped/PreRender event can only be used from local scripts (지금: " .. ctx.name .. ")")
		end
	end
	h.sigCheck.RenderStepped = renderOnly
	h.sigCheck.PreRender = renderOnly
end

-- ================= TweenService =================
local Ease = {}
local function bounceOut(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t -= 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t -= 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	end
	t -= 2.625 / 2.75
	return 7.5625 * t * t + 0.984375
end
local IN = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Exponential = function(t)
		return if t == 0 then 0 else 2 ^ (10 * (t - 1))
	end,
	Circular = function(t)
		return 1 - math.sqrt(1 - t * t)
	end,
	Back = function(t)
		local s = 1.70158
		return t * t * ((s + 1) * t - s)
	end,
	Bounce = function(t)
		return 1 - bounceOut(1 - t)
	end,
	Elastic = function(t)
		if t == 0 or t == 1 then
			return t
		end
		local p = 0.3
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1 - p / 4) * (2 * math.pi) / p)
	end,
}
function Ease.value(alpha: number, style: string, direction: string): number
	local f = IN[style] or IN.Linear
	alpha = math.clamp(alpha, 0, 1)
	if direction == "In" then
		return f(alpha)
	elseif direction == "Out" then
		return 1 - f(1 - alpha)
	end
	if alpha < 0.5 then
		return f(alpha * 2) / 2
	end
	return 1 - f((1 - alpha) * 2) / 2
end
Services.Ease = Ease

local function lerpValue(a: any, b: any, t: number): any
	local ty = type(a)
	if ty == "number" then
		return a + (b - a) * t
	elseif ty == "boolean" then
		return if t >= 1 then b else a
	end
	local mt = getmetatable(a)
	if mt == Types.V2MT then
		return V2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
	elseif mt == Types.UD2MT then
		return Types.UD2(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t)
	elseif mt == Types.C3MT then
		return Types.C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	elseif mt == Types.UDimMT then
		return Types.UD(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	elseif mt == Types.V3MT then
		return Types.V3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
	elseif mt == Types.RectMT then
		return Types.RC(a.Min.X + (b.Min.X - a.Min.X) * t, a.Min.Y + (b.Min.Y - a.Min.Y) * t, a.Max.X + (b.Max.X - a.Max.X) * t, a.Max.Y + (b.Max.Y - a.Max.Y) * t)
	elseif mt == Types.NRMT then
		return Types.NumberRange.new(a.Min + (b.Min - a.Min) * t, a.Max + (b.Max - a.Max) * t)
	elseif mt == Types.CFMT then
		return Types.CFrame.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
	end
	return if t >= 1 then b else a
end
local TWEENABLE = { bool = true, int = true, int64 = true, float = true, double = true, Vector2 = true, Vector3 = true, UDim = true, UDim2 = true, Color3 = true, Rect = true, NumberRange = true, CFrame = true }

local activeTweens = {} :: { any }
local function setState(st, name: string)
	Inst.setRaw(st.self, "PlaybackState", E("PlaybackState", name))
end
local function stopTween(st, stateName: string)
	local i = table.find(activeTweens, st)
	if i then
		table.remove(activeTweens, i)
	end
	st.playing = false
	setState(st, stateName)
	Inst.fire(st.self, "Completed", E("PlaybackState", stateName))
	if st.onDone then
		st.onDone(stateName)
	end
end

local function newTween(target, info, goals, what: string)
	local tst = Inst.st(target)
	for k, v in goals do
		local m = if type(k) == "string" then tst.info.members[k] else nil
		if not m or m.kind ~= 1 then
			raise(what .. " no property named '" .. tostring(k) .. "' for object '" .. tst.name .. "' (" .. tst.class .. ")" .. R.hint(k, tst.info.members))
		end
		if m.readonly then
			raise(what .. " property named '" .. k .. "' 는 읽기 전용이라 트윈할 수 없다")
		end
		if not TWEENABLE[m.tcode] then
			raise(what .. " property named '" .. k .. "' cannot be tweened (형 " .. Inst.prettyType(m.tcode) .. "은 트윈할 수 없다)")
		end
		local ok = m.check.f(v)
		if not ok or (type(v) == "string") then
			raise(what .. " property named '" .. k .. "' cannot be tweened due to type mismatch (property is a '" .. Inst.prettyType(m.tcode) .. "', but given type is '" .. Types.typeof(v) .. "')")
		end
	end
	local tw = Inst.create("Tween")
	local st = Inst.st(tw)
	st.target = target
	st.tinfo = info
	st.goals = table.clone(goals)
	st.elapsed = 0
	st.playing = false
	st.paused = false
	st.ctx = Sched.ctx
	return tw
end

do
	local h = Inst.hook("TweenService")
	h.methods.Create = function(_, _, target, info, goals)
		return newTween(target, info, goals, "TweenService:Create")
	end
	h.methods.GetValue = function(_, _, alpha, style, direction)
		return Ease.value(alpha, style.Name, direction.Name)
	end
	local t = Inst.hook("Tween")
	t.get.Instance = function(st)
		return st.target
	end
	t.get.TweenInfo = function(st)
		return st.tinfo
	end
	local tb = Inst.hook("TweenBase")
	tb.methods.Play = function(st, inst)
		if st.playing then
			return
		end
		if not st.paused then
			st.elapsed = 0
			st.starts = {}
			for k in st.goals do
				st.starts[k] = Inst.getRaw(st.target, k)
				local m = Inst.st(st.target).info.members[k]
				if m.get then
					st.starts[k] = st.target[k]
				end
			end
			-- 같은 속성을 움직이던 다른 트윈은 멈춘다
			for _, other in table.clone(activeTweens) do
				if other ~= st and other.target == st.target then
					for k in st.goals do
						if other.goals[k] ~= nil then
							stopTween(other, "Cancelled")
							break
						end
					end
				end
			end
		end
		st.paused = false
		st.playing = true
		table.insert(activeTweens, st)
		setState(st, if st.tinfo.DelayTime > 0 and st.elapsed < st.tinfo.DelayTime then "Delayed" else "Playing")
	end
	tb.methods.Pause = function(st)
		if st.playing then
			local i = table.find(activeTweens, st)
			if i then
				table.remove(activeTweens, i)
			end
			st.playing = false
			st.paused = true
			setState(st, "Paused")
		end
	end
	tb.methods.Cancel = function(st)
		if st.playing or st.paused then
			st.paused = false
			stopTween(st, "Cancelled")
		end
	end
end

function Services.stepTweens(dt: number)
	if #activeTweens == 0 then
		return
	end
	for _, st in table.clone(activeTweens) do
		if st.playing then
			st.elapsed += dt
			local info = st.tinfo
			local t = st.elapsed - info.DelayTime
			if t >= 0 then
				if Inst.getRaw(st.self, "PlaybackState").Name ~= "Playing" then
					setState(st, "Playing")
				end
				local dur = math.max(info.Time, 1e-9)
				local leg = if info.Reverses then dur * 2 else dur -- 한 번 도는 시간
				local cycles = if info.RepeatCount < 0 then math.huge else info.RepeatCount + 1
				local done = t >= leg * cycles
				local alpha
				if done then
					alpha = if info.Reverses then 0 else 1
				else
					local within = t % leg
					alpha = if within <= dur then within / dur else 1 - (within - dur) / dur
				end
				local e = if done then alpha else Ease.value(alpha, info.EasingStyle.Name, info.EasingDirection.Name)
				local target = st.target
				local ok, err = pcall(function()
					for k, goal in st.goals do
						target[k] = if e >= 1 then goal elseif e <= 0 and done then st.starts[k] else lerpValue(st.starts[k], goal, e)
					end
				end)
				if not ok then
					R.onError({ message = "트윈이 속성을 넣다가 실패했다: " .. tostring(err), traceback = "", ctx = "tween" })
					done = true
				end
				if done then
					stopTween(st, "Completed")
				end
			end
		end
	end
end

-- GuiObject:TweenPosition 같은 옛 메서드
do
	local h = Inst.hook("GuiObject")
	local function legacy(st, inst, goals, direction, style, time, override, callback)
		if st.legacyTween and st.legacyTween.playing then
			if not override then
				return false
			end
			st.legacyTween.onDone = nil
			stopTween(st.legacyTween, "Cancelled")
		end
		local info = Types.TweenInfo.new(time or 1, style or E("EasingStyle", "Quad"), direction or E("EasingDirection", "Out"))
		local tw = newTween(inst, info, goals, "GuiObject:Tween")
		local ts = Inst.st(tw)
		st.legacyTween = ts
		if callback then
			local ctx = Sched.ctx
			ts.onDone = function(stateName)
				Sched.call(ctx, callback, E("TweenStatus", if stateName == "Completed" then "Completed" else "Canceled"))
			end
		end
		tw:Play()
		return true
	end
	h.methods.TweenPosition = function(st, inst, pos, direction, style, time, override, callback)
		return legacy(st, inst, { Position = pos }, direction, style, time, override, callback)
	end
	h.methods.TweenSize = function(st, inst, size, direction, style, time, override, callback)
		return legacy(st, inst, { Size = size }, direction, style, time, override, callback)
	end
	h.methods.TweenSizeAndPosition = function(st, inst, size, pos, direction, style, time, override, callback)
		return legacy(st, inst, { Size = size, Position = pos }, direction, style, time, override, callback)
	end
end

-- ================= 원격 이벤트 · 함수 =================
local netQueue = {} :: { any }
local function netSend(fn)
	table.insert(netQueue, { frame = Sched.frame, due = Sched.now + (R.opts.latency or 0), fn = fn })
end
function Services.deliverNet()
	if #netQueue == 0 then
		return
	end
	local keep = {}
	local run = {}
	for _, e in netQueue do
		if e.frame < Sched.frame and e.due <= Sched.now then
			table.insert(run, e)
		else
			table.insert(keep, e)
		end
	end
	netQueue = keep
	for _, e in run do
		e.fn()
	end
	Sched.flush()
end
function Services.netPending(): number
	return #netQueue
end

-- 건너가는 값: 표는 베끼고(메타테이블 없이), 함수 · 스레드는 nil
local function netCopy(v: any, what: string, seen: { [any]: boolean }?): any
	local t = type(v)
	if t == "function" or t == "thread" then
		R.note("net-fn:" .. what, what .. ": 함수 · 스레드는 건너가지 못한다(nil이 된다)")
		return nil
	elseif t == "table" then
		local mt = getmetatable(v)
		if mt and R.TYPEOF[mt] then
			return v -- Roblox 자료형 · 인스턴스는 그대로
		end
		seen = seen or {}
		if seen[v] then
			raise(what .. ": 돌고 도는 표(자기를 가리키는 표)는 보낼 수 없다")
		end
		seen[v] = true
		local out = {}
		local n = #v
		if n > 0 then
			for i = 1, n do
				out[i] = netCopy(v[i], what, seen)
			end
			for k in v do
				if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
					R.note("net-mixed:" .. what, what .. ": 배열과 사전이 섞인 표는 배열 부분만 건너간다")
					break
				end
			end
		else
			for k, val in v do
				if type(k) == "string" then
					out[k] = netCopy(val, what, seen)
				else
					R.note("net-key:" .. what, what .. ": 문자열이 아닌 열쇠는 문자열로 바뀌어 건너간다")
					out[tostring(k)] = netCopy(val, what, seen)
				end
			end
		end
		seen[v] = nil
		return out
	end
	return v
end
local function netPack(what: string, ...)
	local n = select("#", ...)
	local out = table.create(n)
	for i = 1, n do
		out[i] = netCopy((select(i, ...)), what)
	end
	out.n = n
	return out
end
Services.netCopy = netCopy

local function remoteDeliver(inst, eventName: string, packed)
	local st = Inst.st(inst)
	if Inst.hasListeners(inst, eventName) then
		Inst.fire(inst, eventName, table.unpack(packed, 1, packed.n))
	else
		-- 건 것이 없으면 쌓아 두었다가 처음 걸 때 준다(Roblox도 그렇게 한다)
		st.pending = st.pending or {}
		local q = st.pending[eventName]
		if not q then
			q = {}
			st.pending[eventName] = q
			local sig = Inst.signal(inst, eventName)
			sig._onCount = function(d)
				if d > 0 and #q > 0 then
					local items = table.clone(q)
					table.clear(q)
					Sched.after(0, nil, function()
						for _, p in items do
							Inst.fire(inst, eventName, table.unpack(p, 1, p.n))
						end
					end)
				end
			end
		end
		if #q < 256 then
			table.insert(q, packed)
		end
	end
end

for _, cls in { "RemoteEvent", "UnreliableRemoteEvent" } do
	local h = Inst.hook(cls)
	h.methods.FireServer = function(st, inst, ...)
		clientOnly(cls .. ":FireServer")
		local packed = netPack(st.name .. ":FireServer", ...)
		local player = R.player
		netSend(function()
			table.insert(packed, 1, player)
			packed.n += 1
			remoteDeliver(inst, "OnServerEvent", packed)
		end)
	end
	h.methods.FireClient = function(st, inst, player, ...)
		serverOnly(cls .. ":FireClient")
		if player == nil then
			raise(cls .. ":FireClient: 첫 인자는 Player여야 한다(nil이 왔다)")
		end
		local packed = netPack(st.name .. ":FireClient", ...)
		netSend(function()
			remoteDeliver(inst, "OnClientEvent", packed)
		end)
	end
	h.methods.FireAllClients = function(st, inst, ...)
		serverOnly(cls .. ":FireAllClients")
		local packed = netPack(st.name .. ":FireAllClients", ...)
		netSend(function()
			if R.player then
				remoteDeliver(inst, "OnClientEvent", packed)
			end
		end)
	end
	h.sigCheck.OnServerEvent = function(ctx)
		if ctx and not ctx.server then
			raise("OnServerEvent can only be used on the server (지금: " .. ctx.name .. ")")
		end
	end
	h.sigCheck.OnClientEvent = function(ctx)
		if ctx and not ctx.client then
			raise("OnClientEvent can only be used on the client (지금: " .. ctx.name .. ")")
		end
	end
end

do
	local h = Inst.hook("RemoteFunction")
	local function invoke(st, inst, cbName: string, side: string, what: string, prefixPlayer: any, ...)
		Sched.mustYield(what)
		local co = coroutine.running()
		local packed = netPack(what, ...)
		netSend(function()
			local function run()
				local cb = Inst.callback(inst, cbName)
				if not cb then
					-- 받는 쪽이 아직 함수를 넣지 않았다: 넣을 때까지 기다린다
					st.cbWaiters = st.cbWaiters or {}
					st.cbWaiters[cbName] = st.cbWaiters[cbName] or {}
					table.insert(st.cbWaiters[cbName], coroutine.running())
					local warned = false
					Sched.after(5, nil, function()
						if not Inst.callback(inst, cbName) and not warned then
							warned = true
							R.warn(what .. ": 받는 쪽이 " .. cbName .. " 를 넣지 않아 5초째 기다리고 있다(Roblox에서는 끝없이 기다린다)", "")
						end
					end)
					coroutine.yield()
					cb = Inst.callback(inst, cbName)
				end
				local results
				if prefixPlayer then
					results = table.pack(pcall(cb.fn, prefixPlayer, table.unpack(packed, 1, packed.n)))
				else
					results = table.pack(pcall(cb.fn, table.unpack(packed, 1, packed.n)))
				end
				if not results[1] then
					Sched.reportError(nil, results[2], cbName .. " 안에서 난 오류")
					netSend(function()
						Sched.resume(co, false, what .. " 의 받는 쪽에서 오류가 났다: " .. tostring(results[2]))
					end)
					return
				end
				local back = netPack(what .. " 의 답", table.unpack(results, 2, results.n))
				netSend(function()
					Sched.resume(co, true, table.unpack(back, 1, back.n))
				end)
			end
			Sched.spawn(Sched.contexts[side], run)
		end)
		local res = table.pack(coroutine.yield())
		if not res[1] then
			raise(res[2])
		end
		return table.unpack(res, 2, res.n)
	end
	h.methods.InvokeServer = function(st, inst, ...)
		clientOnly("RemoteFunction:InvokeServer")
		return invoke(st, inst, "OnServerInvoke", "server", st.name .. ":InvokeServer", R.player, ...)
	end
	h.methods.InvokeClient = function(st, inst, player, ...)
		serverOnly("RemoteFunction:InvokeClient")
		if player == nil then
			raise("RemoteFunction:InvokeClient: 첫 인자는 Player여야 한다(nil이 왔다)")
		end
		return invoke(st, inst, "OnClientInvoke", "client", st.name .. ":InvokeClient", nil, ...)
	end
	h.sigCheck.OnServerInvoke = function(ctx)
		if ctx and not ctx.server then
			raise("OnServerInvoke can only be set on the server (지금: " .. ctx.name .. ")")
		end
	end
	h.sigCheck.OnClientInvoke = function(ctx)
		if ctx and not ctx.client then
			raise("OnClientInvoke can only be set on the client (지금: " .. ctx.name .. ")")
		end
	end

	local be = Inst.hook("BindableEvent")
	be.methods.Fire = function(st, inst, ...)
		local packed = netPack(st.name .. ":Fire", ...)
		Inst.fire(inst, "Event", table.unpack(packed, 1, packed.n))
	end
	local bf = Inst.hook("BindableFunction")
	bf.methods.Invoke = function(st, inst, ...)
		local cb = Inst.callback(inst, "OnInvoke")
		if not cb then
			Sched.mustYield(st.name .. ":Invoke (OnInvoke가 아직 없다)")
			st.cbWaiters = st.cbWaiters or {}
			st.cbWaiters.OnInvoke = st.cbWaiters.OnInvoke or {}
			table.insert(st.cbWaiters.OnInvoke, coroutine.running())
			coroutine.yield()
			cb = Inst.callback(inst, "OnInvoke")
		end
		local packed = netPack(st.name .. ":Invoke", ...)
		local results = netPack(st.name .. ":Invoke 의 답", cb.fn(table.unpack(packed, 1, packed.n)))
		return table.unpack(results, 1, results.n)
	end
end

-- ================= DataStoreService =================
local stores = {} :: { [string]: any } -- "이름/범위" → { data = { [key] = { json, version, time } }, inst }
Services.stores = stores
Services.dsFail = { count = 0, message = "" }
Services.dsLog = {} :: { any }

local function dsValidate(v: any, path: string, seen: { [any]: boolean })
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "string" then
		if t == "string" and not utf8.len(v) then
			raise("DataStore: " .. path .. " 의 문자열이 올바른 UTF-8이 아니다(Data stores can only accept valid UTF-8 characters)")
		end
		return
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			raise("DataStore: " .. path .. " 가 NaN/무한대다 — 저장할 수 없다")
		end
		return
	elseif t == "table" then
		local mt = getmetatable(v)
		if mt and R.TYPEOF[mt] then
			raise("DataStore: " .. path .. " 가 " .. Types.typeof(v) .. " 다 — 저장할 수 없다(수 · 문자열 · 불 · 표만 된다)")
		end
		if seen[v] then
			raise("DataStore: " .. path .. " 에서 표가 돌고 돈다(cyclic table)")
		end
		seen[v] = true
		local n = #v
		local count = 0
		for k, val in v do
			count += 1
			local kt = type(k)
			if n > 0 then
				if kt ~= "number" or k % 1 ~= 0 or k < 1 or k > n then
					raise("DataStore: " .. path .. " 는 배열과 사전이 섞인 표다(열쇠 " .. tostring(k) .. ") — 저장할 수 없다")
				end
			elseif kt ~= "string" then
				raise("DataStore: " .. path .. " 의 열쇠 " .. tostring(k) .. " 가 문자열이 아니다 — 사전의 열쇠는 문자열이어야 한다(수 열쇠가 듬성듬성한 표는 저장되지 않는다)")
			end
			dsValidate(val, path .. "." .. tostring(k), seen)
		end
		seen[v] = nil
		return
	end
	raise("DataStore: " .. path .. " 가 " .. t .. " 다 — 저장할 수 없다(수 · 문자열 · 불 · 표만 된다)")
end

local function dsKey(key: any, what: string)
	if type(key) ~= "string" or #key == 0 then
		raise(what .. ": 열쇠는 빈 문자열이 아닌 문자열이어야 한다(" .. Inst.describe(key) .. ")")
	end
	if #key > 50 then
		raise(what .. ": 열쇠가 50자를 넘는다(" .. #key .. "자)")
	end
end

local function dsCall(st, what: string, key: string)
	serverOnly(what)
	Sched.mustYield(what)
	table.insert(Services.dsLog, { op = what, store = st.storeName, key = key, time = Sched.now })
	Sched.wait(R.opts.dsLatency or 0.1)
	local f = Services.dsFail
	if f.count > 0 then
		f.count -= 1
		raise(if f.message ~= "" then f.message else "502: API Services rejected request with error. HTTP 500 (Internal Server Error) — mock이 넣은 실패")
	end
end

local function dsEncode(value: any, what: string): string
	dsValidate(value, "값", {})
	local json = Json.encode(value)
	if #json > 4194304 then
		raise(what .. ": 값이 4MB를 넘는다(" .. #json .. "바이트)")
	end
	return json
end

local function getStore(name: string, scope: string, class: string)
	local id = class .. ":" .. name .. "/" .. scope
	local s = stores[id]
	if not s then
		local inst = Inst.create(class)
		local st = Inst.st(inst)
		st.name = name
		st.storeName = name
		st.data = {}
		st.ordered = class == "OrderedDataStore"
		s = { inst = inst, data = st.data, name = name, scope = scope, class = class }
		stores[id] = s
	end
	return s.inst
end
Services.getStore = getStore

do
	local h = Inst.hook("DataStoreService")
	h.methods.GetDataStore = function(_, _, name, scope)
		serverOnly("DataStoreService:GetDataStore")
		if #name == 0 or #name > 50 then
			raise("DataStoreService:GetDataStore: 이름은 1~50자여야 한다")
		end
		return getStore(name, scope or "global", "DataStore")
	end
	h.methods.GetGlobalDataStore = function()
		serverOnly("DataStoreService:GetGlobalDataStore")
		return getStore("__global", "global", "DataStore")
	end
	h.methods.GetOrderedDataStore = function(_, _, name, scope)
		serverOnly("DataStoreService:GetOrderedDataStore")
		return getStore(name, scope or "global", "OrderedDataStore")
	end
	h.methods.GetRequestBudgetForRequestType = function()
		return 100
	end
	local g = Inst.hook("GlobalDataStore")
	g.methods.GetAsync = function(st, _, key)
		dsKey(key, "GetAsync")
		dsCall(st, "GetAsync", key)
		local rec = st.data[key]
		if not rec then
			return nil
		end
		return Json.decode(rec.json)
	end
	g.methods.SetAsync = function(st, _, key, value)
		dsKey(key, "SetAsync")
		if value == nil then
			raise("SetAsync: 값이 nil이다 — 지우려면 RemoveAsync를 쓴다 (Argument 2 missing or nil)")
		end
		if st.ordered and (type(value) ~= "number" or value % 1 ~= 0) then
			raise("OrderedDataStore:SetAsync: 값은 정수여야 한다(" .. Inst.describe(value) .. ")")
		end
		local json = dsEncode(value, "SetAsync")
		dsCall(st, "SetAsync", key)
		local rec = st.data[key]
		st.data[key] = { json = json, version = (if rec then rec.version else 0) + 1, time = Sched.now }
		return tostring(st.data[key].version)
	end
	g.methods.UpdateAsync = function(st, _, key, fn)
		dsKey(key, "UpdateAsync")
		dsCall(st, "UpdateAsync", key)
		local rec = st.data[key]
		local old = if rec then Json.decode(rec.json) else nil
		local co = coroutine.running()
		local marker = Sched.frame
		local newValue = fn(old, nil)
		if coroutine.running() ~= co or Sched.frame ~= marker then
			raise("UpdateAsync: 바꾸는 함수 안에서 기다리면(yield) 안 된다")
		end
		if newValue == nil then
			return nil
		end
		if st.ordered and (type(newValue) ~= "number" or newValue % 1 ~= 0) then
			raise("OrderedDataStore:UpdateAsync: 값은 정수여야 한다(" .. Inst.describe(newValue) .. ")")
		end
		local json = dsEncode(newValue, "UpdateAsync")
		st.data[key] = { json = json, version = (if rec then rec.version else 0) + 1, time = Sched.now }
		return Json.decode(json)
	end
	g.methods.IncrementAsync = function(st, _, key, delta)
		dsKey(key, "IncrementAsync")
		dsCall(st, "IncrementAsync", key)
		local rec = st.data[key]
		local old = if rec then Json.decode(rec.json) else 0
		if type(old) ~= "number" then
			raise("IncrementAsync: 저장된 값이 수가 아니다")
		end
		local v = old + (delta or 1)
		st.data[key] = { json = Json.encode(v), version = (if rec then rec.version else 0) + 1, time = Sched.now }
		return v
	end
	g.methods.RemoveAsync = function(st, _, key)
		dsKey(key, "RemoveAsync")
		dsCall(st, "RemoveAsync", key)
		local rec = st.data[key]
		st.data[key] = nil
		return if rec then Json.decode(rec.json) else nil
	end
	local o = Inst.hook("OrderedDataStore")
	o.methods.GetSortedAsync = function(st, _, ascending, pageSize, minValue, maxValue)
		dsCall(st, "GetSortedAsync", "")
		local items = {}
		for k, rec in st.data do
			local v = Json.decode(rec.json)
			if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
				table.insert(items, { key = k, value = v })
			end
		end
		table.sort(items, function(a, b)
			if a.value ~= b.value then
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end
			return a.key < b.key
		end)
		local pages = Inst.create("DataStorePages")
		local ps = Inst.st(pages)
		ps.items, ps.at, ps.size = items, 1, pageSize
		return pages
	end
	local pg = Inst.hook("Pages")
	pg.get.IsFinished = function(st)
		return st.at + st.size > #st.items
	end
	pg.methods.GetCurrentPage = function(st)
		local out = {}
		for i = st.at, math.min(#st.items, st.at + st.size - 1) do
			table.insert(out, { key = st.items[i].key, value = st.items[i].value })
		end
		return out
	end
	pg.methods.AdvanceToNextPageAsync = function(st)
		if st.at + st.size > #st.items then
			raise("AdvanceToNextPageAsync: 마지막 쪽이다(IsFinished)")
		end
		st.at += st.size
	end
	pg.init = function(st)
		st.items, st.at, st.size = {}, 1, 10
	end
end

-- ================= HttpService =================
do
	local h = Inst.hook("HttpService")
	h.methods.JSONEncode = function(_, _, value)
		local ok, res = pcall(Json.encode, value, true)
		if not ok then
			raise("HttpService:JSONEncode: " .. tostring(res))
		end
		return res
	end
	h.methods.JSONDecode = function(_, _, text)
		local ok, res = pcall(Json.decode, text)
		if not ok then
			raise("HttpService:JSONDecode: " .. tostring(res))
		end
		return res
	end
	local guidState = 0x2545F491
	local function guidNext(): number
		-- xorshift32 (정해진 수열 — 실행마다 같다)
		local x = guidState
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		guidState = x
		return x
	end
	h.methods.GenerateGUID = function(_, _, wrap)
		local a, b, c, d = guidNext(), guidNext(), guidNext(), guidNext()
		local s = string.format("%08X-%04X-4%03X-%04X-%04X%08X", a, bit32.band(b, 0xFFFF), bit32.band(bit32.rshift(b, 16), 0xFFF), bit32.bor(0x8000, bit32.band(c, 0x3FFF)), bit32.band(bit32.rshift(c, 16), 0xFFFF), d)
		if wrap == false then
			return s
		end
		return "{" .. s .. "}"
	end
	h.methods.UrlEncode = function(_, _, text)
		return (string.gsub(text, "[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end
end

-- ================= TextService =================
do
	local h = Inst.hook("TextService")
	h.methods.GetTextSize = function(_, _, text, fontSize, _font, frameSize)
		local wrap = if frameSize.X > 0 then frameSize.X else nil
		local w, hh = Layout.measureText(text, fontSize, wrap, 1)
		return V2(math.ceil(w), math.ceil(hh))
	end
	h.methods.GetTextBoundsAsync = function(_, _, params)
		local text = params.Text
		if params.RichText then
			text = Layout.plainText(text)
		end
		local width = params.Width
		local w, hh = Layout.measureText(text, params.Size, if width > 0 then width else nil, 1)
		return V2(math.ceil(w), math.ceil(hh))
	end
	h.methods.FilterStringAsync = function(_, _, text)
		R.note("TextService.FilterStringAsync", "TextService:FilterStringAsync는 글을 거르지 않는다 — 넣은 글을 그대로 돌려주는 결과를 준다")
		local res = Inst.create("TextFilterResult")
		Inst.st(res).text = text
		return res
	end
	local r = Inst.hook("TextFilterResult")
	r.methods.GetNonChatStringForBroadcastAsync = function(st)
		return st.text
	end
	r.methods.GetNonChatStringForUserAsync = function(st)
		return st.text
	end
	r.methods.GetChatForUserAsync = function(st)
		return st.text
	end
end

-- ================= ContentProvider =================
do
	local h = Inst.hook("ContentProvider")
	h.methods.PreloadAsync = function(_, _, list, callback)
		if coroutine.isyieldable() then
			Sched.wait(0)
		end
		if callback then
			for _, item in list do
				local id = if type(item) == "string" then item else ""
				callback(id, E("AssetFetchStatus", "Success"))
			end
		end
	end
	h.methods.GetAssetFetchStatus = function()
		return E("AssetFetchStatus", "Success")
	end
	h.get.RequestQueueSize = function()
		return 0
	end
end

-- ================= AssetService =================
do
	local h = Inst.hook("AssetService")
	h.methods.CreateEditableImage = function(_, _, options)
		local w, hh = 512, 512
		if options ~= nil then
			for k, v in options do
				if k == "Size" then
					if Types.typeof(v) ~= "Vector2" then
						raise("AssetService:CreateEditableImage: Size는 Vector2여야 하는데 " .. Inst.describe(v) .. "이(가) 왔다")
					end
					w, hh = v.X, v.Y
				else
					raise("AssetService:CreateEditableImage: 모르는 옵션 '" .. tostring(k) .. "' (쓸 수 있는 것: Size)")
				end
			end
		end
		if w % 1 ~= 0 or hh % 1 ~= 0 or w < 1 or hh < 1 then
			raise("AssetService:CreateEditableImage: 크기는 1 이상의 정수여야 한다(" .. w .. "x" .. hh .. ")")
		end
		if w > 1024 or hh > 1024 then
			raise("AssetService:CreateEditableImage: 크기가 1024x1024를 넘는다(" .. w .. "x" .. hh .. ")")
		end
		return Gui.newEditableImage(w, hh)
	end
	h.methods.CreateEditableImageAsync = function(_, _, content)
		R.note("CreateEditableImageAsync", "AssetService:CreateEditableImageAsync는 올린 그림을 읽지 못한다 — 빈(투명한) 64x64 그림판을 돌려준다")
		if coroutine.isyieldable() then
			Sched.wait(0)
		end
		return Gui.newEditableImage(64, 64)
	end
end

-- ================= Sound =================
local playing = {} :: { any }
Services.soundLog = {} :: { any }
do
	local h = Inst.hook("Sound")
	h.init = function(st)
		st.length = R.opts.soundLength or 1
	end
	h.get.TimeLength = function(st)
		return st.length
	end
	h.get.IsLoaded = function()
		return true
	end
	h.get.IsPlaying = function(st)
		return Layout.P(st, "Playing")
	end
	h.get.isPlaying = h.get.IsPlaying
	h.get.IsPaused = function(st)
		return not Layout.P(st, "Playing")
	end
	local function start(st, inst, fromStart: boolean)
		if fromStart then
			st.props.TimePosition = 0
		end
		if not table.find(playing, st) then
			table.insert(playing, st)
		end
		Inst.setRaw(inst, "Playing", true)
	end
	local function stop(st, inst)
		local i = table.find(playing, st)
		if i then
			table.remove(playing, i)
		end
		Inst.setRaw(inst, "Playing", false)
	end
	h.methods.Play = function(st, inst)
		table.insert(Services.soundLog, { id = Layout.P(st, "SoundId"), name = st.name, time = Sched.now, volume = Layout.P(st, "Volume"), by = ctxName() })
		start(st, inst, true)
		Inst.fire(inst, "Played", Layout.P(st, "SoundId"))
	end
	h.methods.Stop = function(st, inst)
		stop(st, inst)
		st.props.TimePosition = 0
		Inst.fire(inst, "Stopped", Layout.P(st, "SoundId"))
	end
	h.methods.Pause = function(st, inst)
		if Layout.P(st, "Playing") then
			stop(st, inst)
			Inst.fire(inst, "Paused", Layout.P(st, "SoundId"))
		end
	end
	h.methods.Resume = function(st, inst)
		if not Layout.P(st, "Playing") then
			start(st, inst, false)
			Inst.fire(inst, "Resumed", Layout.P(st, "SoundId"))
		end
	end
	h.after.Playing = function(st, inst, value)
		if value then
			table.insert(Services.soundLog, { id = Layout.P(st, "SoundId"), name = st.name, time = Sched.now, volume = Layout.P(st, "Volume"), by = ctxName() })
			if not table.find(playing, st) then
				table.insert(playing, st)
			end
		else
			local i = table.find(playing, st)
			if i then
				table.remove(playing, i)
			end
		end
	end
	h.destroy = function(st)
		local i = table.find(playing, st)
		if i then
			table.remove(playing, i)
		end
	end
	local ss = Inst.hook("SoundService")
	ss.methods.PlayLocalSound = function(_, _, sound)
		if not Inst.isA(sound, "Sound") then
			raise("SoundService:PlayLocalSound: Sound가 와야 하는데 " .. Inst.describe(sound) .. "이(가) 왔다")
		end
		local st = Inst.st(sound)
		table.insert(Services.soundLog, { id = Layout.P(st, "SoundId"), name = st.name, time = Sched.now, volume = Layout.P(st, "Volume"), by = ctxName(), localSound = true })
	end
end

function Services.stepSounds(dt: number)
	if #playing == 0 then
		return
	end
	for _, st in table.clone(playing) do
		local speed = Layout.P(st, "PlaybackSpeed")
		local pos = Layout.P(st, "TimePosition") + dt * speed
		if pos >= st.length then
			if Layout.P(st, "Looped") then
				st.props.TimePosition = pos % math.max(st.length, 1e-6)
				st.loops = (st.loops or 0) + 1
				Inst.fire(st.self, "DidLoop", Layout.P(st, "SoundId"), st.loops)
			else
				st.props.TimePosition = 0
				local i = table.find(playing, st)
				if i then
					table.remove(playing, i)
				end
				Inst.setRaw(st.self, "Playing", false)
				Inst.fire(st.self, "Ended", Layout.P(st, "SoundId"))
			end
		else
			st.props.TimePosition = pos
		end
	end
end

-- ================= Workspace · Camera =================
do
	local h = Inst.hook("Workspace")
	h.methods.GetServerTimeNow = function()
		return R.opts.epoch + Sched.now
	end
	h.get.DistributedGameTime = function()
		return Sched.now
	end
	h.defaults.Gravity = 196.2
	local c = Inst.hook("Camera")
	c.get.ViewportSize = function()
		return V2(R.opts.viewW, R.opts.viewH)
	end
end

-- ================= StarterGui =================
local coreGui = {} :: { [string]: boolean }
local coreValues = {} :: { [string]: any }
Services.coreLog = {} :: { any }
local CORE_SET = { ChatActive = true, PointsNotificationsActive = true, BadgesNotificationsActive = true, ResetButtonCallback = true, ChatMakeSystemMessage = true, ChatWindowSize = true, ChatWindowPosition = true, ChatBarDisableFocus = true, SendNotification = true, TopbarEnabled = true, DevConsoleVisible = true, PromptSendFriendRequest = true, PromptUnfriend = true, PromptBlockPlayer = true, PromptUnblockPlayer = true, AvatarContextMenuEnabled = true, AvatarContextMenuTarget = true, AddAvatarContextMenuOption = true, RemoveAvatarContextMenuOption = true, AvatarContextMenuTheme = true, CoreGuiChatConnections = true, VRLaserPointerMode = true, VREnableControllerModels = true }
do
	local h = Inst.hook("StarterGui")
	h.methods.SetCoreGuiEnabled = function(_, _, kind, enabled)
		clientOnly("StarterGui:SetCoreGuiEnabled")
		if kind.Name == "All" then
			for _, it in Types.enumType("CoreGuiType"):GetEnumItems() do
				coreGui[it.Name] = enabled
			end
		end
		coreGui[kind.Name] = enabled
	end
	h.methods.GetCoreGuiEnabled = function(_, _, kind)
		local v = coreGui[kind.Name]
		return v == nil or v
	end
	h.methods.SetCore = function(_, _, name, value)
		clientOnly("StarterGui:SetCore")
		if not CORE_SET[name] then
			raise("SetCore: " .. tostring(name) .. " has not been registered by the CoreScripts" .. R.hint(name, CORE_SET))
		end
		coreValues[name] = value
		table.insert(Services.coreLog, { name = name, value = value, time = Sched.now })
	end
	h.methods.GetCore = function(_, _, name)
		if not CORE_SET[name] then
			raise("GetCore: " .. tostring(name) .. " has not been registered by the CoreScripts" .. R.hint(name, CORE_SET))
		end
		return coreValues[name]
	end
end

-- ================= 그 밖의 서비스 =================
do
	local d = Inst.hook("Debris")
	d.methods.AddItem = function(_, _, item, lifetime)
		Sched.after(lifetime or 10, nil, function()
			Inst.destroy(item)
		end)
	end
	local cs = Inst.hook("CollectionService")
	cs.methods.GetTagged = function(_, _, tag)
		local out = {}
		local set = Inst.tagged[tag]
		if set then
			for inst in set do
				if Inst.isDescendantOf(inst, game) then
					table.insert(out, inst)
				end
			end
			table.sort(out, function(a, b)
				return Inst.st(a).id < Inst.st(b).id
			end)
		end
		return out
	end
	cs.methods.AddTag = function(_, _, inst, tag)
		inst:AddTag(tag)
	end
	cs.methods.RemoveTag = function(_, _, inst, tag)
		inst:RemoveTag(tag)
	end
	cs.methods.HasTag = function(_, _, inst, tag)
		return inst:HasTag(tag)
	end
	cs.methods.GetTags = function(_, _, inst)
		return inst:GetTags()
	end
	local function tagSignal(key: string)
		local s = Inst.tagSignals[key]
		if not s then
			s = Signal.new("CollectionService " .. key)
			Inst.tagSignals[key] = s
		end
		return s
	end
	cs.methods.GetInstanceAddedSignal = function(_, _, tag)
		return tagSignal("+" .. tag)
	end
	cs.methods.GetInstanceRemovedSignal = function(_, _, tag)
		return tagSignal("-" .. tag)
	end
	local mp = Inst.hook("MarketplaceService")
	mp.methods.UserOwnsGamePassAsync = function()
		return false
	end
	mp.methods.PlayerOwnsAsset = function()
		return false
	end
	local ls = Inst.hook("LocalizationService")
	ls.get.RobloxLocaleId = function()
		return "ko-kr"
	end
	ls.get.SystemLocaleId = function()
		return "ko-kr"
	end
	local tm = Inst.hook("Teams")
	tm.methods.GetTeams = function()
		return {}
	end
	local gs = Inst.hook("GuiService")
	gs.methods.GetGuiInset = function()
		return V2(0, R.opts.insetTop), V2(0, 0)
	end
	gs.get.TopbarInset = function()
		return Types.RC(0, 0, R.opts.viewW, R.opts.insetTop)
	end
	gs.methods.IsTenFootInterface = function()
		return false
	end
	gs.defaults.TouchControlsEnabled = true
	gs.defaults.AutoSelectGuiEnabled = true
	gs.defaults.GuiNavigationEnabled = true
	gs.get.MenuIsOpen = function(st)
		return st.menuOpen == true
	end
	local ps = Inst.hook("PolicyService")
	ps.methods.GetPolicyInfoForPlayerAsync = function()
		return { AreAdsAllowed = false, ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {}, IsPaidItemTradingAllowed = false, IsSubjectToChinaPolicies = false }
	end
end

-- ================= 처음 짓기 =================
function Services.build()
	game = Inst.create("DataModel")
	Inst.st(game).name = R.opts.gameName or "Game"
	Inst.st(game).parentLocked = true
	Services.game = game
	R.game = game
	for _, name in EAGER do
		if Inst.classExists(name) then
			makeService(name)
		end
	end
	local sp = services.StarterPlayer
	for _, name in { "StarterPlayerScripts", "StarterCharacterScripts" } do
		local c = Inst.create(name)
		Inst.setParentRaw(c, sp)
	end
	local cam = Inst.create("Camera")
	Inst.setParentRaw(cam, services.Workspace)
	Inst.st(services.Workspace).props.CurrentCamera = cam
	local gst = Inst.st(game)
	gst.props.PlaceId = R.opts.placeId or 0
	gst.props.GameId = R.opts.gameId or 0
	gst.props.JobId = R.opts.jobId or "00000000-0000-0000-0000-000000000000"
	gst.props.PlaceVersion = 1
	gst.props.CreatorId = R.opts.creatorId or 0
	return game
end

-- 창 크기를 바꾼다
function Services.resize(w: number, h: number)
	R.opts.viewW, R.opts.viewH = w, h
	Layout.bump()
	local cam = Inst.getRaw(services.Workspace, "CurrentCamera")
	if cam then
		local cst = Inst.st(cam)
		if cst.sig or cst.psig then
			Inst.fireChanged(cst, "ViewportSize", V2(w, h))
		end
	end
end

-- 한 장(frame)
function Services.stepFrame(dt: number)
	Sched.now += dt
	Sched.frame += 1
	Services.deliverNet()
	Sched.runTimers()
	Sched.flush()
	Services.stepTweens(dt)
	local rs = services.RunService
	if rs then
		for _, b in table.clone(renderBinds) do
			Sched.call(b.ctx, b.fn, dt)
		end
		Inst.fire(rs, "PreRender", dt)
		Inst.fire(rs, "RenderStepped", dt)
		Inst.fire(rs, "PreAnimation", dt)
		Inst.fire(rs, "PreSimulation", dt)
		Inst.fire(rs, "Stepped", Sched.now, dt)
		Inst.fire(rs, "PostSimulation", dt)
		Inst.fire(rs, "Heartbeat", dt)
	end
	Services.stepSounds(dt)
	Sched.flush()
	Layout.flush()
	Sched.flush()
end

return Services
