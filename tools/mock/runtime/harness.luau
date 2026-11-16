-- 하네스: 시나리오(Luau 파일)가 받는 `harness` — 장 넘기기 · 입력 흉내 · 찾기 · 확인 · 화면 찍기.
local R = require("./rt")
R.mark()
local Types = require("./types")
local Sched = require("./sched")
local Inst = require("./inst")
local Layout = require("./layout")
local Services = require("./services")
local Input = require("./input")
local Dump = require("./dump")
local Json = require("./json")
local P = Layout.P

local H = {}
R.Harness = H

local started = false

local function fail(msg: string, level: number?)
	R.counts.fails += 1
	local tb = R.cleanTrace(debug.traceback("", (level or 1) + 1))
	R.emit("fail", { text = msg, trace = tb })
	if R.opts.stopOnFail then
		error("harness: 확인 실패 — " .. msg, 0)
	end
end

-- ---------- 시작 · 장 ----------
function H.start()
	if started then
		return
	end
	started = true
	local prev = Sched.ctx
	Sched.ctx = nil
	local game = Services.game
	-- 1) 서버 스크립트
	Services.running.server = true
	for _, name in { "ServerScriptService", "Workspace" } do
		Services.startScriptsUnder(Services.get(name))
	end
	Sched.flush()
	-- 2) 플레이어: StarterPlayerScripts · StarterGui를 베껴 넣는다
	local o = R.opts
	local player = Services.addPlayer(o.userId, o.userName)
	local pg, ps = R.playerGui, Inst.findChild(player, "PlayerScripts")
	local starterGui = Services.get("StarterGui")
	Inst.st(pg).props.ScreenOrientation = P(Inst.st(starterGui), "ScreenOrientation")
	local sps = Inst.findChild(Services.get("StarterPlayer"), "StarterPlayerScripts")
	if sps then
		for _, c in Inst.st(sps).children do
			local copy = c:Clone()
			if copy then
				copy.Parent = ps
			end
		end
	end
	for _, c in Inst.st(starterGui).children do
		local copy = c:Clone()
		if copy then
			copy.Parent = pg
		end
	end
	Inst.fire(Services.get("Players"), "PlayerAdded", player)
	Sched.flush()
	-- 3) 클라이언트 스크립트
	Services.running.client = true
	Services.startScriptsUnder(Services.get("ReplicatedFirst"))
	Services.startScriptsUnder(ps)
	Services.startScriptsUnder(pg)
	Sched.flush()
	Layout.flush()
	Sched.ctx = prev
	local _ = game
end

function H.step(n: number?, dt: number?)
	if Sched.depth > 0 then
		error("harness.step: asClient · asServer에 준 함수 안에서는 장을 넘길 수 없다(시나리오의 맨 바깥에서 부른다)", 2)
	end
	local prev = Sched.ctx
	Sched.ctx = nil
	for _ = 1, n or 1 do
		Services.stepFrame(dt or R.opts.dt)
	end
	Sched.ctx = prev
end

-- 가상 시간으로 seconds만큼(장 단위로) 넘긴다
function H.advance(seconds: number, dt: number?)
	local d = dt or R.opts.dt
	local n = math.max(1, math.floor(seconds / d + 0.5))
	H.step(n, d)
end

function H.time(): number
	return Sched.now
end
-- 진짜 시계(초) — 얼마나 걸리는지 잴 때(스크립트가 보는 os.clock은 가상 시계다)
local realClock = os.clock
function H.wallClock(): number
	return realClock()
end
function H.frame(): number
	return Sched.frame
end

-- 조건이 참이 될 때까지 장을 넘긴다(가상 시간 timeout초까지). 돌려주는 것: 그 값
function H.waitFor(cond: () -> any, timeout: number?, what: string?)
	local limit = Sched.now + (timeout or 5)
	while true do
		local v = cond()
		if v then
			return v
		end
		if Sched.now >= limit then
			fail("기다리던 것이 " .. tostring(timeout or 5) .. "초 안에 되지 않았다" .. (if what then ": " .. what else ""), 2)
			return nil
		end
		H.step(1)
	end
end

-- ---------- 화면 크기 · 기기 ----------
function H.viewport(): (number, number)
	return R.opts.viewW, R.opts.viewH
end
function H.resize(w: number, h: number)
	Services.resize(w, h)
	Layout.flush()
end
function H.setDevice(opts)
	Input.setDevice(opts)
end
function H.windowFocus(focused: boolean)
	Input.windowFocus(focused)
end
function H.menu(open: boolean)
	Input.menu(open)
end

-- ---------- 찾기 ----------
H.game = nil :: any
local function rootFor(path: string): (any, string)
	if string.sub(path, 1, 5) == "game." then
		return Services.game, string.sub(path, 6)
	elseif string.sub(path, 1, 10) == "PlayerGui." then
		return R.playerGui, string.sub(path, 11)
	elseif path == "PlayerGui" then
		return R.playerGui, ""
	elseif path == "game" then
		return Services.game, ""
	end
	return R.playerGui, path
end

-- 길로 찾는다: "PlayerGui.Hud.Frame" · "game.ReplicatedStorage.X" · (앞머리가 없으면 PlayerGui 아래). 없으면 nil
function H.find(path: string): any
	local root, rest = rootFor(path)
	if not root then
		return nil
	end
	if rest == "" then
		return root
	end
	return Inst.byPath(root, rest)
end

function H.get(path: string): any
	local v = H.find(path)
	if not v then
		-- 어디까지 있었는지 알려 준다
		local root, rest = rootFor(path)
		local cur = root
		local okPath = {}
		for part in string.gmatch(rest, "[^%.]+") do
			local nextOne = cur and Inst.findChild(cur, part, false)
			if not nextOne then
				local names = {}
				if cur then
					for _, c in Inst.st(cur).children do
						table.insert(names, Inst.st(c).name)
					end
				end
				error('harness.get("' .. path .. '"): "' .. part .. '" 가 없다 (' .. (if #okPath > 0 then table.concat(okPath, ".") else "뿌리") .. " 아래에 있는 것: " .. table.concat(names, ", ") .. ")", 2)
			end
			table.insert(okPath, part)
			cur = nextOne
		end
		error('harness.get("' .. path .. '"): 없다', 2)
	end
	return v
end

local function descend(root: any, fn: (any, any) -> ())
	Inst.eachDescendant(Inst.st(root), fn)
end

function H.findAllByName(name: string, root: any?): { any }
	local out = {}
	descend(root or R.playerGui, function(st, inst)
		if st.name == name then
			table.insert(out, inst)
		end
	end)
	return out
end
function H.findByName(name: string, root: any?): any
	return H.findAllByName(name, root)[1]
end

-- 글로 찾는다(TextLabel · TextButton · TextBox). exact가 아니면 그 글이 들어 있는 것. 보이는 것만(includeHidden이 아니면)
function H.findAllByText(text: string, exact: boolean?, includeHidden: boolean?): { any }
	local out = {}
	if not R.playerGui then
		return out
	end
	descend(R.playerGui, function(st, inst)
		if st.info.members.TextBounds then
			local t = P(st, "Text")
			if P(st, "RichText") then
				t = Layout.plainText(t)
			end
			local hit = if exact then t == text else string.find(t, text, 1, true) ~= nil
			if hit and (includeHidden or Layout.isShown(st)) then
				table.insert(out, inst)
			end
		end
	end)
	return out
end
function H.findByText(text: string, exact: boolean?, includeHidden: boolean?): any
	return H.findAllByText(text, exact, includeHidden)[1]
end

function H.findAllByClass(className: string, root: any?): { any }
	local out = {}
	descend(root or R.playerGui, function(st, inst)
		if st.info.isA[className] then
			table.insert(out, inst)
		end
	end)
	return out
end

-- 화면에 보이는가 / 화면에서의 네모(화면 좌표) / 그 가운데
function H.isVisible(inst: any): boolean
	return Layout.isShown(Inst.st(inst))
end
function H.rect(inst: any): (number, number, number, number)
	local st = Inst.st(inst)
	Layout.ensure(st)
	Layout.drain()
	return st.ax, st.ay + R.opts.insetTop, st.aw, st.ah
end
function H.center(inst: any): (number, number)
	local x, y, w, h = H.rect(inst)
	return x + w / 2, y + h / 2
end
-- 그 점(화면 좌표)에서 맨 위에 있는 것 · 누르면 받는 것
function H.at(x: number, y: number): (any, any)
	local over, target = Input.pick(x, y)
	return over[1], target
end
function H.prop(inst: any, name: string): any
	return inst[name]
end

-- ---------- 입력 ----------
function H.keyDown(key)
	Input.keyDown(key)
end
function H.keyUp(key)
	Input.keyUp(key)
end
-- 글쇠를 눌렀다 뗀다(사이에 frames장 — 기본 1)
function H.keyTap(key, frames: number?)
	Input.keyDown(key)
	H.step(frames or 1)
	Input.keyUp(key)
end
function H.mouseMove(x: number, y: number)
	Input.mouseMove(x, y)
end
function H.mouseDown(x: number?, y: number?, button: number?)
	return Input.mouseDown(x, y, button)
end
function H.mouseUp(x: number?, y: number?, button: number?)
	return Input.mouseUp(x, y, button)
end
-- 그 점을 마우스로 누른다. 돌려주는 것: 입력을 받은 것(없으면 nil)
function H.click(x: number, y: number, button: number?)
	Input.mouseDown(x, y, button)
	return Input.mouseUp(x, y, button)
end
local function pointOf(inst: any, what: string): (number, number)
	if not Inst.is(inst) then
		error(what .. ": 인스턴스가 와야 하는데 " .. Inst.describe(inst) .. "이(가) 왔다", 3)
	end
	local x, y = H.center(inst)
	return x, y
end
-- 그 인스턴스의 가운데를 누른다. 다른 것이 가로채면 확인 실패로 적는다
function H.clickOn(inst: any)
	local x, y = pointOf(inst, "harness.clickOn")
	if not Layout.isShown(Inst.st(inst)) then
		fail("clickOn: " .. Inst.fullName(Inst.st(inst)) .. " 는 화면에 보이지 않는다", 2)
	end
	local got = H.click(x, y)
	if got ~= inst then
		fail("clickOn: " .. Inst.fullName(Inst.st(inst)) .. " 를 눌렀는데 입력을 받은 것은 " .. (if got then Inst.fullName(Inst.st(got)) else "없다(아무도 받지 않았다)"), 2)
	end
	return got
end
function H.wheel(x: number, y: number, delta: number)
	Input.wheel(x, y, delta)
end
function H.touchBegin(id, x: number, y: number)
	return Input.touchBegin(id, x, y)
end
function H.touchMove(id, x: number, y: number)
	return Input.touchMove(id, x, y)
end
function H.touchEnd(id, x: number?, y: number?)
	return Input.touchEnd(id, x, y)
end
local tapId = 0
function H.tap(x: number, y: number)
	tapId += 1
	local id = "tap" .. tapId
	Input.touchBegin(id, x, y)
	return Input.touchEnd(id)
end
function H.tapOn(inst: any)
	local x, y = pointOf(inst, "harness.tapOn")
	if not Layout.isShown(Inst.st(inst)) then
		fail("tapOn: " .. Inst.fullName(Inst.st(inst)) .. " 는 화면에 보이지 않는다", 2)
	end
	local got = H.tap(x, y)
	if got ~= inst then
		fail("tapOn: " .. Inst.fullName(Inst.st(inst)) .. " 를 눌렀는데 입력을 받은 것은 " .. (if got then Inst.fullName(Inst.st(got)) else "없다(아무도 받지 않았다)"), 2)
	end
	return got
end
function H.typeText(text: string)
	Input.typeText(text)
end
function H.focus(box: any)
	Input.captureFocus(box)
end
function H.unfocus(enter: boolean?)
	if Input.focused then
		Input.releaseFocus(Input.focused, enter == true, nil)
	end
end

-- ---------- 확인 ----------
function H.expect(cond: any, msg: string?)
	if not cond then
		fail(msg or "expect: 참이 아니다", 2)
		return false
	end
	R.counts.checks = (R.counts.checks or 0) + 1
	return true
end
local function show(v: any, depth: number?): string
	local t = Types.typeof(v)
	if t == "string" then
		return '"' .. v .. '"'
	elseif t == "table" then
		local d = depth or 0
		if d > 4 then
			return "{…}"
		end
		local parts = {}
		local n = #v
		for i = 1, n do
			parts[i] = show(v[i], d + 1)
		end
		local keys = {}
		for k in v do
			if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
				table.insert(keys, k)
			end
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in keys do
			table.insert(parts, tostring(k) .. " = " .. show(v[k], d + 1))
		end
		return "[" .. table.concat(parts, ",") .. "]"
	elseif t == "Instance" then
		return v.ClassName .. "(" .. v:GetFullName() .. ")"
	end
	return tostring(v)
end
local function same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) == "table" and type(b) == "table" and not getmetatable(a) and not getmetatable(b) then
		for k, v in a do
			if not same(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	return false
end
function H.eq(actual: any, expected: any, msg: string?)
	if not same(actual, expected) then
		fail((msg or "eq") .. ": " .. show(expected) .. " 이어야 하는데 " .. show(actual) .. " 이다", 2)
		return false
	end
	R.counts.checks = (R.counts.checks or 0) + 1
	return true
end
function H.near(actual: number, expected: number, eps: number?, msg: string?)
	if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
		fail((msg or "near") .. ": " .. show(expected) .. " (±" .. tostring(eps or 1e-6) .. ") 이어야 하는데 " .. show(actual) .. " 이다", 2)
		return false
	end
	R.counts.checks = (R.counts.checks or 0) + 1
	return true
end
function H.fail(msg: string)
	fail(msg, 2)
end
-- fn이 오류를 내야 한다(그 글에 pattern이 들어 있어야 한다). 돌려주는 것: 오류 글
function H.expectError(fn: () -> (), pattern: string?, msg: string?)
	local ok, err = pcall(fn)
	if ok then
		fail((msg or "expectError") .. ": 오류가 나야 하는데 나지 않았다", 2)
		return nil
	end
	local text = tostring(err)
	if pattern and not string.find(text, pattern, 1, true) then
		fail((msg or "expectError") .. ': 오류 글에 "' .. pattern .. '" 가 있어야 하는데: ' .. text, 2)
		return text
	end
	R.counts.checks = (R.counts.checks or 0) + 1
	return text
end
-- 지금까지 난 오류 · 경고 (스크립트에서 난 것)
function H.errors(): { any }
	return table.clone(R.errorList)
end
function H.warnings(): { any }
	return table.clone(R.warnList)
end
-- 알고 낸 오류는 세지 않게: 지금까지의 오류를 지우고 돌려준다
function H.takeErrors(): { any }
	local list = R.errorList
	R.errorList = {}
	R.counts.errors -= #list
	R.emit("forgive", { count = #list })
	return list
end

-- ---------- 문맥 ----------
local function runAs(side: string, fn: (...any) -> ...any, ...)
	local results = nil
	local co = Sched.spawn(Sched.contexts[side], function(...)
		results = table.pack(fn(...))
	end, ...)
	if results then
		return table.unpack(results, 1, results.n)
	end
	if coroutine.status(co) == "suspended" then
		return nil -- 기다리는 중(다음 장들에서 이어 돈다)
	end
	return nil
end
function H.asServer(fn, ...)
	return runAs("server", fn, ...)
end
function H.asClient(fn, ...)
	return runAs("client", fn, ...)
end
-- 그 쪽에서 fn을 pcall로 돌린다: ok, 값… (또는 false, 오류 글). 오류로 세지 않는다. fn이 기다리면 nil
function H.pcallAs(side: string, fn, ...)
	if not Sched.contexts[side] then
		error('harness.pcallAs: side는 "client" · "server" 가운데 하나', 2)
	end
	local res = nil
	Sched.spawn(Sched.contexts[side], function(...)
		res = table.pack(pcall(fn, ...))
	end, ...)
	if res then
		return table.unpack(res, 1, res.n)
	end
	return nil
end
-- 그 쪽(client · server)이 읽어 둔 모듈의 값을 얻는다(아직 읽지 않았으면 읽는다)
function H.require(module: any, side: string?)
	local ctx = Sched.contexts[side or "client"]
	if not ctx then
		error('harness.require: side는 "client" · "server" 가운데 하나', 2)
	end
	local entry = ctx.modules[module]
	if entry and entry.done and not entry.failed then
		return entry.value
	end
	return runAs(side or "client", function()
		return Services.require(module, module)
	end)
end

-- ---------- 그 밖 ----------
function H.shot(file: string)
	if type(file) ~= "string" or not string.find(file, "%.png$") then
		error("harness.shot: .png로 끝나는 파일 이름이 와야 한다", 2)
	end
	Dump.shot(file)
end
function H.capture()
	return Dump.capture()
end
function H.tree(root: any?, depth: number?): string
	return Dump.tree(root or R.playerGui, depth)
end
function H.print(...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	R.emit("out", { ctx = "harness", text = table.concat(parts, " ") })
end
H.log = H.print
function H.fire(inst: any, eventName: string, ...)
	Inst.signal(inst, eventName) -- 없는 이벤트면 오류
	Inst.fire(inst, eventName, ...)
	Sched.flush()
end
function H.sounds(): { any }
	return table.clone(Services.soundLog)
end
function H.coreCalls(): { any }
	return table.clone(Services.coreLog)
end
function H.notes(): { [string]: string }
	return table.clone(R.unmodelled)
end

-- DataStore 들여다보기 · 실패 넣기
H.datastore = {}
function H.datastore.get(name: string, key: string, scope: string?)
	local s = Services.stores["DataStore:" .. name .. "/" .. (scope or "global")] or Services.stores["OrderedDataStore:" .. name .. "/" .. (scope or "global")]
	local rec = s and s.data[key]
	return if rec then Json.decode(rec.json) else nil
end
function H.datastore.set(name: string, key: string, value: any, scope: string?)
	local inst = Services.getStore(name, scope or "global", "DataStore")
	Inst.st(inst).data[key] = { json = Json.encode(value), version = 1, time = Sched.now }
end
function H.datastore.failNext(count: number?, message: string?)
	Services.dsFail.count = count or 1
	Services.dsFail.message = message or ""
end
function H.datastore.calls(): { any }
	return table.clone(Services.dsLog)
end
function H.datastore.dump(): { [string]: any }
	local out = {}
	for id, s in Services.stores do
		local d = {}
		for k, rec in s.data do
			d[k] = Json.decode(rec.json)
		end
		out[id] = d
	end
	return out
end

-- 플레이어가 나간다 → PlayerRemoving → BindToClose
function H.shutdown(maxSeconds: number?)
	local player = R.player
	if player then
		Services.removePlayer(player)
	end
	local pending = 0
	for _, b in Services.closeBinds do
		pending += 1
		Sched.spawn(b.ctx, function()
			b.fn(Types.enumItem("CloseReason", "Unknown"))
			pending -= 1
		end)
	end
	local limit = Sched.now + (maxSeconds or 30)
	while pending > 0 and Sched.now < limit do
		H.step(1)
	end
	if pending > 0 then
		fail("shutdown: BindToClose에 건 함수 " .. pending .. "개가 " .. tostring(maxSeconds or 30) .. "초 안에 끝나지 않았다", 2)
	end
end

function H.init()
	H.game = Services.game
	H.services = setmetatable({}, {
		__index = function(_, name)
			return Services.get(name)
		end,
	})
	H.Enum = Types.Enum
end
function H.player()
	return R.player
end
function H.playerGui()
	return R.playerGui
end
function H.started(): boolean
	return started
end

return H
