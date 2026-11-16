-- mock 런타임의 들머리. 묶음 파일(bundle.mjs가 만든 것)이 부른다:
--   local RT = require("../runtime/main")
--   local G = RT.setup(options)          → 스크립트가 볼 전역(game · Instance · task …) — 묶음 파일이 제 전역에 넣는다
--   RT.run({ tree = …, sources = …, scenario = … })
local R = require("./rt")
R.mark()
local Json = require("./json")
local Types = require("./types")
local Sched = require("./sched")
local Inst = require("./inst")
local Layout = require("./layout")
local _Gui = require("./gui")
local Services = require("./services")
local Input = require("./input")
local Dump = require("./dump")
local Harness = require("./harness")

local RT = {}
local nativePrint = print
local nativeOs = os
local nativeDebug = debug

local function ctxName(): string
	return if Sched.ctx then Sched.ctx.name else "engine"
end

R.onError = function(e)
	R.counts.errors += 1
	table.insert(R.errorList, e)
	R.emit("err", { ctx = e.ctx, text = e.message, trace = e.traceback, note = e.note, time = Sched.now, frame = Sched.frame })
end
R.warn = function(text: string, trace: string?)
	R.counts.warns += 1
	local w = { text = text, trace = trace or "", ctx = ctxName() }
	table.insert(R.warnList, w)
	R.emit("warn", { ctx = w.ctx, text = text, trace = w.trace, time = Sched.now, frame = Sched.frame })
end

local function joinArgs(...): string
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

function RT.setup(options)
	local o = R.opts
	R.RUNTIME[nativeDebug.info(2, "s")] = true -- 묶음 파일도 런타임으로 친다(역추적에서 뺀다)
	for k, v in options do
		o[k] = v
	end
	o.viewW = o.viewW or 1280
	o.viewH = o.viewH or 720
	o.insetTop = o.insetTop or 58
	o.dt = o.dt or 1 / 60
	o.epoch = o.epoch or 1794787200
	o.userId = o.userId or 1001
	o.userName = o.userName or "Player1"
	if o.strictEnums == nil then
		o.strictEnums = true
	end
	Sched.deferredSignals = o.signals ~= "immediate"
	math.randomseed(o.seed or 20261116) -- 돌릴 때마다 같은 결과가 나오게(바꾸려면 --seed)
	Services.build()
	Harness.init()
	if o.device == "touch" then
		Input.setDevice({ touch = true, keyboard = false, mouse = false, preferred = "Touch" })
	end

	local G = {}
	G.game = Services.game
	G.Game = Services.game
	G.workspace = Services.get("Workspace")
	G.Workspace = G.workspace
	G.Instance = table.freeze({ new = Inst.new, fromExisting = function(inst)
		return inst:Clone()
	end })
	G.Enum = Types.Enum
	G.Vector2 = table.freeze(Types.Vector2)
	G.Vector3 = table.freeze(Types.Vector3)
	G.UDim = table.freeze(Types.UDim)
	G.UDim2 = table.freeze(Types.UDim2)
	G.Color3 = table.freeze(Types.Color3)
	G.Rect = table.freeze(Types.Rect)
	G.NumberRange = table.freeze(Types.NumberRange)
	G.NumberSequence = table.freeze(Types.NumberSequence)
	G.NumberSequenceKeypoint = table.freeze(Types.NumberSequenceKeypoint)
	G.ColorSequence = table.freeze(Types.ColorSequence)
	G.ColorSequenceKeypoint = table.freeze(Types.ColorSequenceKeypoint)
	G.TweenInfo = table.freeze(Types.TweenInfo)
	G.Font = table.freeze(Types.Font)
	G.Content = table.freeze(Types.Content)
	G.CFrame = table.freeze(Types.CFrame)
	G.BrickColor = table.freeze(Types.BrickColor)
	G.Random = table.freeze(Types.Random)
	G.DateTime = table.freeze(Types.DateTime)
	G.task = Sched.task
	G.wait = Sched.legacyWait
	G.delay = Sched.legacyDelay
	G.spawn = Sched.legacySpawn
	G.tick = function()
		return o.epoch + Sched.now
	end
	G.time = function()
		return Sched.now
	end
	G.elapsedTime = G.time
	G.print = function(...)
		R.emit("out", { ctx = ctxName(), text = joinArgs(...) })
	end
	G.warn = function(...)
		R.warn(joinArgs(...), R.cleanTrace(nativeDebug.traceback("", 2)))
	end
	-- os: 가상 시계. os.clock은 부를 때마다 100만분의 1초씩 흐른다(바쁜 기다림이 끝나게)
	local osT = {}
	osT.clock = function()
		Sched.clockTicks += 1
		return Sched.now + Sched.clockTicks * 1e-6
	end
	osT.time = function(t)
		if t ~= nil then
			return nativeOs.time(t)
		end
		return math.floor(o.epoch + Sched.now)
	end
	osT.date = function(format, t)
		return nativeOs.date(format or "%c", t or math.floor(o.epoch + Sched.now))
	end
	osT.difftime = nativeOs.difftime
	G.os = table.freeze(osT)
	local dbg = table.clone(nativeDebug)
	dbg.profilebegin = function() end
	dbg.profileend = function() end
	dbg.setmemorycategory = function() end
	dbg.resetmemorycategory = function() end
	G.debug = table.freeze(dbg)
	G.shared = {}
	G.settings = function()
		R.note("settings()", "settings()는 흉내 내지 않는다")
		return nil
	end
	G.UserSettings = function()
		return Services.game
	end
	G.version = function()
		return "0.0.0.mock"
	end
	G.printidentity = function()
		R.emit("out", { ctx = ctxName(), text = "Current identity is 2" })
	end
	G.loadstring = function()
		error("loadstring() is not available", 2)
	end
	G.gcinfo = function()
		return collectgarbage("count")
	end
	RT.G = G
	return G
end

-- Rojo의 $properties 값을 그 속성의 형으로 바꾼다
local function convertProp(inst, key: string, v: any): any
	local st = Inst.st(inst)
	local m = st.info.members[key]
	if not m or m.kind ~= 1 then
		error("project.json의 $properties: " .. st.class .. " 에 " .. key .. " 속성이 없다" .. R.hint(key, st.info.members), 0)
	end
	local t = m.tcode
	if type(v) == "table" and next(v) ~= nil and #v == 0 then
		-- { "Color3": [..] } 꼴: 안쪽 값을 꺼낸다
		local k, inner = next(v)
		if k == "Enum" then
			return Types.enumType(string.sub(t, 3)):FromValue(inner)
		end
		v = inner
	end
	if string.sub(t, 1, 2) == "E:" then
		local et = Types.enumType(string.sub(t, 3))
		local item = if type(v) == "string" then et:FromName(v) else et:FromValue(v)
		if not item then
			error("project.json의 $properties: " .. key .. ' = "' .. tostring(v) .. '" 는 Enum.' .. string.sub(t, 3) .. " 에 없다", 0)
		end
		return item
	elseif type(v) == "table" then
		if t == "Color3" then
			return Types.C3(v[1], v[2], v[3])
		elseif t == "Vector2" then
			return Types.V2(v[1], v[2])
		elseif t == "Vector3" then
			return Types.V3(v[1], v[2], v[3])
		elseif t == "UDim" then
			return Types.UD(v[1], v[2])
		elseif t == "UDim2" then
			return Types.UD2(v[1][1], v[1][2], v[2][1], v[2][2])
		end
		error("project.json의 $properties: " .. key .. " (" .. t .. ") 형의 값은 mock이 읽지 못한다", 0)
	end
	return v
end

local function buildTree(node, parent)
	local inst
	local existing = Inst.findChild(parent, node.n, false)
	if existing and Inst.st(existing).class == node.c then
		inst = existing
	else
		local info = Inst.getInfo(node.c)
		if not info then
			error("project.json: 없는 클래스 " .. tostring(node.c) .. " (" .. node.n .. ")", 0)
		end
		if info.tags.Service and parent == Services.game then
			inst = Services.get(node.c)
		else
			inst = Inst.create(node.c)
			Inst.st(inst).name = node.n
			Inst.setParentRaw(inst, parent)
		end
	end
	local st = Inst.st(inst)
	if node.s then
		st.source = node.s
	end
	if node.p then
		for k, v in node.p do
			inst[k] = convertProp(inst, k, v)
		end
	end
	if node.a then
		for k, v in node.a do
			inst:SetAttribute(k, v)
		end
	end
	if node.k then
		for _, child in node.k do
			buildTree(child, inst)
		end
	end
end

function RT.run(bundle)
	local o = R.opts
	for i, s in bundle.sources do
		Services.sources[i] = { file = s.file, src = s.src }
	end
	-- 전역이 빠짐없이 들어갔는지(묶음 파일이 아는 이름과 런타임이 주는 이름이 같아야 한다)
	local assigned = {}
	for _, name in bundle.globals do
		assigned[name] = true
	end
	for name in RT.G do
		if not assigned[name] then
			error("mock 안쪽 오류: 전역 " .. name .. " 이 묶음 파일의 목록(bundle.mjs의 GLOBALS)에 없다")
		end
	end
	local ok, err = pcall(function()
		for _, child in bundle.tree.k or {} do
			buildTree(child, Services.game)
		end
	end)
	if not ok then
		R.onError({ message = tostring(err), traceback = "", ctx = "build" })
		R.emit("done", { errors = R.counts.errors, warns = R.counts.warns, fails = R.counts.fails, checks = 0, frames = 0, time = 0 })
		return
	end
	local t0 = nativeOs.clock()
	Sched.ctx = Sched.contexts.harness
	if bundle.scenario then
		local sc = bundle.scenario
		local fn, cerr = loadstring("local harness,require,typeof,type=...;" .. sc.src, "=" .. sc.file)
		if not fn then
			R.onError({ message = tostring(cerr), traceback = "", ctx = "scenario", note = "시나리오의 문법 오류" })
		else
			if not o.noStart then
				Harness.start()
			end
			local sok, serr = xpcall(function()
				fn(Harness, function(target)
					return Services.require(Services.game, target)
				end, Types.typeof, Types.type)
			end, function(e)
				return { message = tostring(e), traceback = R.cleanTrace(nativeDebug.traceback("", 2)) }
			end)
			if not sok then
				R.onError({ message = serr.message, traceback = serr.traceback, ctx = "scenario", note = "시나리오가 오류로 멈췄다" })
			end
		end
	else
		Harness.start()
		Harness.step(o.frames or 60, o.dt)
	end
	Sched.flush()
	if o.finalShot then
		for _, file in o.finalShot do
			Dump.shot(file)
		end
	end
	if o.printTree then
		R.emit("out", { ctx = "harness", text = if R.playerGui then Dump.tree(R.playerGui) else "(PlayerGui 없음)" })
	end
	R.emit("done", {
		errors = R.counts.errors,
		warns = R.counts.warns,
		fails = R.counts.fails,
		checks = R.counts.checks or 0,
		frames = Sched.frame,
		time = Sched.now,
		wall = nativeOs.clock() - t0,
		timers = Sched.pendingTimers(),
	})
end

RT.Json = Json
RT.Input = Input
RT.Layout = Layout
return RT
