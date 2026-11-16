-- 차례지기(스케줄러) · 가상 시계 · 신호(RBXScriptSignal) · task 라이브러리.
--  모든 스크립트는 코루틴으로 돌고, 시간은 하네스가 한 장(frame)씩 밀 때만 흐른다(늘 같은 결과).
--  문맥(context): "server" · "client" · "harness" — 스레드마다 붙어 다니고, 신호에 건 함수는 걸 때의 문맥으로 돈다.
local R = require("./rt")
R.mark()
local Sched = {}
R.Sched = Sched
local raise = R.raise

Sched.now = 0 -- 가상 시각(초)
Sched.frame = 0
Sched.ctx = nil :: any -- 지금 도는 코드의 문맥
Sched.depth = 0 -- 겹쳐 깨운 깊이(0 = 엔진 · 하네스 자리)
Sched.deferredSignals = true -- 신호를 미뤄서 부른다(새 플레이스의 기본 — SignalBehavior.Deferred)
Sched.clockTicks = 0 -- os.clock을 부를 때마다 조금씩 흐르게(바쁜 기다림이 멈추지 않게)

local ctxOf = setmetatable({}, { __mode = "k" }) :: { [thread]: any }
local timed = {} :: { any } -- 늦은 것이 앞, 이른 것이 뒤(뒤에서 꺼낸다)
local deferred = {} :: { any }
local deferredHead = 1
local seq = 0
local flushing = false

Sched.contexts = {
	server = { name = "server", server = true, client = false, modules = {} },
	client = { name = "client", server = false, client = true, modules = {} },
	harness = { name = "harness", server = true, client = true, modules = {}, harness = true },
}

function Sched.contextOf(co: thread)
	return ctxOf[co]
end

-- 다시 던져지는 오류(require · pcall을 거치는 것)의 처음 자리를 적어 둔다
local kept = nil :: any
function Sched.keepTrace(err: any, tb: string)
	if not kept or kept.err ~= err then
		kept = { err = err, tb = tb }
	end
end

function Sched.reportError(co: thread?, err: any, extra: string?)
	local tb = if co then debug.traceback(co) else debug.traceback()
	if kept and kept.err == err then
		tb = kept.tb .. "\n" .. tb
	end
	kept = nil
	local ctx = if co then ctxOf[co] else Sched.ctx
	R.onError({ message = tostring(err), traceback = R.cleanTrace(tb), ctx = if ctx then ctx.name else "?", note = extra })
end

local flushDeferred

-- 스레드를 깨운다(오류는 모아서 알린다). 맨 바깥에서 깨운 것이 끝나면 미뤄 둔 것을 돌린다
local function resume(co: thread, ...): boolean
	local prev = Sched.ctx
	Sched.ctx = ctxOf[co] or prev
	Sched.depth += 1
	local ok, err = coroutine.resume(co, ...)
	Sched.depth -= 1
	Sched.ctx = prev
	if not ok then
		Sched.reportError(co, err)
	end
	if Sched.depth == 0 and not flushing then
		flushDeferred()
	end
	return ok
end
Sched.resume = resume

-- 새 스레드로 바로 돌린다
function Sched.spawn(ctx: any, f: any, ...): thread
	local co: thread
	if type(f) == "thread" then
		co = f
	else
		co = coroutine.create(f)
	end
	if ctx then
		ctxOf[co] = ctx
	elseif not ctxOf[co] then
		ctxOf[co] = Sched.ctx
	end
	resume(co, ...)
	return co
end

-- 신호에 건 함수를 부를 때: 빈 스레드를 돌려 쓴다(부를 때마다 코루틴을 만들지 않게)
local freeRunner: thread? = nil
local function runIn(fn, ...)
	local me = freeRunner
	freeRunner = nil
	fn(...)
	freeRunner = me
end
local function runnerLoop()
	while true do
		runIn(coroutine.yield())
	end
end
function Sched.call(ctx: any, fn: any, ...)
	local co = freeRunner
	if not co then
		co = coroutine.create(runnerLoop)
		coroutine.resume(co)
		freeRunner = co
	end
	ctxOf[co :: thread] = ctx or Sched.ctx
	resume(co :: thread, fn, ...)
end

-- 미뤄 두기
function Sched.defer(ctx: any, f: any, ...)
	local n = select("#", ...)
	table.insert(deferred, { f = f, ctx = ctx or Sched.ctx, n = n, ... })
end
function Sched.deferEntry(entry: any)
	table.insert(deferred, entry)
end

flushDeferred = function()
	if flushing then
		return
	end
	flushing = true
	local rounds = 0
	while deferredHead <= #deferred do
		local stop = #deferred
		rounds += 1
		if rounds > 80 then
			-- Roblox: Maximum re-entrancy depth (80) exceeded
			deferred = {}
			deferredHead = 1
			flushing = false
			R.onError({ message = "미뤄 부르기가 80번 넘게 서로를 다시 불렀다 (Maximum re-entrancy depth (80) exceeded)", traceback = "", ctx = "?" })
			return
		end
		while deferredHead <= stop do
			local e = deferred[deferredHead]
			deferred[deferredHead] = false
			deferredHead += 1
			if e then
				local conn = e.conn
				if conn == nil or conn.Connected or e.force then
					local f = e.f
					if type(f) == "thread" then
						if coroutine.status(f) == "suspended" then
							if e.ctx and not ctxOf[f] then
								ctxOf[f] = e.ctx
							end
							resume(f, table.unpack(e, 1, e.n))
						end
					else
						Sched.call(e.ctx, f, table.unpack(e, 1, e.n))
					end
				end
			end
		end
	end
	deferred = {}
	deferredHead = 1
	flushing = false
end
Sched.flush = flushDeferred

-- 시간 걸어 두기
local function addTimed(due: number, entry: any)
	seq += 1
	entry.due = due
	entry.seq = seq
	local i = #timed
	-- 뒤(이른 쪽)부터 제자리를 찾는다
	while i >= 1 do
		local o = timed[i]
		if o.due > due or (o.due == due and o.seq > entry.seq) then
			break
		end
		i -= 1
	end
	table.insert(timed, i + 1, entry)
	return entry
end
Sched.addTimed = addTimed

function Sched.after(seconds: number, ctx: any, f: any, ...)
	return addTimed(Sched.now + math.max(0, seconds), { f = f, ctx = ctx or Sched.ctx, n = select("#", ...), ... })
end

-- 지금 시각까지 된 것을 깨운다(깨어난 것이 새로 건 것은 다음 장에)
function Sched.runTimers()
	local now = Sched.now
	local due = {}
	while true do
		local e = timed[#timed]
		-- (1e-9: 1/60초를 여러 번 더한 값의 끝자리 오차로 한 장 늦지 않게)
		if not e or e.due > now + 1e-9 then
			break
		end
		timed[#timed] = nil
		table.insert(due, e)
	end
	for _, e in due do
		if not e.cancelled then
			local f = e.f
			if type(f) == "thread" then
				if coroutine.status(f) == "suspended" then
					if e.wait then
						resume(f, now - e.start, now)
					else
						resume(f, table.unpack(e, 1, e.n))
					end
				end
			else
				Sched.call(e.ctx, f, table.unpack(e, 1, e.n))
			end
		end
	end
end

function Sched.pendingTimers(): number
	return #timed
end

-- 지금 스레드를 멈춘다(누가 깨울 때까지)
local function mustYield(what: string)
	if not coroutine.isyieldable() then
		raise(what .. ": 여기서는 기다릴 수 없다(시나리오의 맨 바깥에서는 harness.step으로 장을 넘긴다)")
	end
end
Sched.mustYield = mustYield

function Sched.wait(seconds: number?): (number, number)
	mustYield("task.wait")
	local co = coroutine.running()
	addTimed(Sched.now + math.max(0, seconds or 0), { f = co, wait = true, start = Sched.now })
	return coroutine.yield()
end

-- ---------- task ----------
local task = {}
function task.spawn(f, ...)
	if type(f) ~= "function" and type(f) ~= "thread" then
		raise("task.spawn: 함수나 스레드가 와야 하는데 " .. R.Types.typeof(f) .. "이(가) 왔다")
	end
	return Sched.spawn(nil, f, ...)
end
function task.defer(f, ...)
	if type(f) ~= "function" and type(f) ~= "thread" then
		raise("task.defer: 함수나 스레드가 와야 하는데 " .. R.Types.typeof(f) .. "이(가) 왔다")
	end
	local co = if type(f) == "thread" then f else coroutine.create(f)
	if not ctxOf[co] then
		ctxOf[co] = Sched.ctx
	end
	table.insert(deferred, { f = co, ctx = Sched.ctx, n = select("#", ...), ... })
	if Sched.depth == 0 and not flushing then
		flushDeferred()
	end
	return co
end
function task.delay(seconds, f, ...)
	if type(f) ~= "function" and type(f) ~= "thread" then
		raise("task.delay: 둘째 인자는 함수나 스레드여야 하는데 " .. R.Types.typeof(f) .. "이(가) 왔다")
	end
	if seconds ~= nil and type(seconds) ~= "number" then
		raise("task.delay: 첫 인자는 수(초)여야 하는데 " .. R.Types.typeof(seconds) .. "이(가) 왔다")
	end
	local co = if type(f) == "thread" then f else coroutine.create(f)
	if not ctxOf[co] then
		ctxOf[co] = Sched.ctx
	end
	addTimed(Sched.now + math.max(0, seconds or 0), { f = co, ctx = Sched.ctx, n = select("#", ...), ... })
	return co
end
function task.wait(seconds)
	if seconds ~= nil and type(seconds) ~= "number" then
		raise("task.wait: 수(초)가 와야 하는데 " .. R.Types.typeof(seconds) .. "이(가) 왔다")
	end
	local elapsed = Sched.wait(seconds)
	return elapsed
end
function task.cancel(co)
	if type(co) ~= "thread" then
		raise("task.cancel: 스레드가 와야 하는데 " .. R.Types.typeof(co) .. "이(가) 왔다")
	end
	for _, e in timed do
		if e.f == co then
			e.cancelled = true
		end
	end
	for i = deferredHead, #deferred do
		local e = deferred[i]
		if e and e.f == co then
			deferred[i] = false
		end
	end
	if coroutine.status(co) ~= "running" and coroutine.status(co) ~= "normal" then
		coroutine.close(co)
	end
end
function task.synchronize() end
function task.desynchronize() end
Sched.task = table.freeze(task)

-- 옛 전역 함수: wait · delay · spawn
function Sched.legacyWait(seconds)
	local elapsed = Sched.wait(math.max(seconds or 0, 1 / 30))
	return elapsed, Sched.now
end
function Sched.legacyDelay(seconds, f)
	if type(f) ~= "function" then
		raise("delay: 둘째 인자는 함수여야 한다")
	end
	local start = Sched.now
	Sched.after(math.max(seconds or 0, 1 / 30), nil, function()
		f(Sched.now - start, Sched.now)
	end)
end
function Sched.legacySpawn(f)
	if type(f) ~= "function" then
		raise("spawn: 함수가 와야 한다")
	end
	local start = Sched.now
	Sched.after(0, nil, function()
		f(Sched.now - start, Sched.now)
	end)
end

-- ---------- 신호 ----------
local SignalMT = {}
local ConnMT = {}
R.TYPEOF[SignalMT] = "RBXScriptSignal"
R.TYPEOF[ConnMT] = "RBXScriptConnection"
local SignalM = {}
local ConnM = {}

function ConnM.Disconnect(self)
	if not rawget(self, "Connected") then
		return
	end
	rawset(self, "Connected", false)
	local sig = rawget(self, "_sig")
	local hs = sig._h
	local i = table.find(hs, self)
	if i then
		table.remove(hs, i)
	end
	if sig._onCount then
		sig._onCount(-1)
	end
end
ConnM.disconnect = ConnM.Disconnect
ConnMT.__index = function(_, k)
	local m = ConnM[k]
	if m then
		return m
	end
	raise(tostring(k) .. " is not a valid member of RBXScriptConnection (Connected · Disconnect)")
end
ConnMT.__newindex = function(_, k)
	raise(tostring(k) .. " cannot be assigned to (RBXScriptConnection)")
end
ConnMT.__tostring = function()
	return "Connection"
end

local function connect(self, fn, once: boolean)
	if type(fn) ~= "function" then
		raise("Attempt to connect failed: Passed value is not a function (" .. R.Types.typeof(fn) .. ")")
	end
	if self._check then
		self._check(Sched.ctx, self)
	end
	local c = setmetatable({ Connected = true, _fn = fn, _sig = self, _ctx = Sched.ctx, _once = once }, ConnMT)
	table.insert(self._h, c)
	if self._onCount then
		self._onCount(1)
	end
	return c
end
function SignalM.Connect(self, fn)
	return connect(self, fn, false)
end
SignalM.connect = SignalM.Connect
SignalM.ConnectParallel = SignalM.Connect
function SignalM.Once(self, fn)
	return connect(self, fn, true)
end
function SignalM.Wait(self)
	mustYield(self._name .. ":Wait()")
	if self._check then
		self._check(Sched.ctx, self)
	end
	local co = coroutine.running()
	if not self._w then
		self._w = {}
	end
	table.insert(self._w, co)
	return coroutine.yield()
end
SignalM.wait = SignalM.Wait
SignalMT.__index = function(self, k)
	local m = SignalM[k]
	if m then
		return m
	end
	raise(tostring(k) .. " is not a valid member of RBXScriptSignal (Connect · Once · Wait)" .. R.hint(k, SignalM))
end
SignalMT.__newindex = function(_, k)
	raise(tostring(k) .. " cannot be assigned to (RBXScriptSignal)")
end
SignalMT.__tostring = function(self)
	return "Signal " .. self._name
end

local Signal = {}
Sched.Signal = Signal

function Signal.new(name: string)
	return setmetatable({ _name = name, _h = {}, _w = false, _check = false, _onCount = false }, SignalMT)
end

function Signal.isSignal(v: any): boolean
	return type(v) == "table" and getmetatable(v) == SignalMT
end

function Signal.count(self): number
	return #self._h
end

-- 신호를 낸다. force = 걸린 것이 그사이 끊겨도 부른다(Destroying)
function Signal.fire(self, ...)
	local hs = self._h
	local n = #hs
	local ws = self._w
	if n == 0 and not ws then
		return
	end
	local argn = select("#", ...)
	if n > 0 then
		local list = if n == 1 then hs else table.clone(hs)
		if Sched.deferredSignals then
			for i = 1, n do
				local c = list[i]
				if c._once then
					ConnM.Disconnect(c)
					table.insert(deferred, { f = c._fn, ctx = c._ctx, n = argn, ... })
				else
					table.insert(deferred, { f = c._fn, ctx = c._ctx, conn = c, n = argn, ... })
				end
			end
		else
			local c1 = list[1]
			for i = 1, n do
				local c = if n == 1 then c1 else list[i]
				if c.Connected then
					if c._once then
						ConnM.Disconnect(c)
					end
					Sched.call(c._ctx, c._fn, ...)
				end
			end
		end
	end
	if ws then
		self._w = false
		for _, co in ws do
			if Sched.deferredSignals then
				table.insert(deferred, { f = co, n = argn, ... })
			elseif coroutine.status(co) == "suspended" then
				resume(co, ...)
			end
		end
	end
	if Sched.depth == 0 and not flushing then
		flushDeferred()
	end
end

function Signal.fireForced(self, ...)
	local hs = self._h
	local argn = select("#", ...)
	for _, c in table.clone(hs) do
		if Sched.deferredSignals then
			table.insert(deferred, { f = c._fn, ctx = c._ctx, force = true, n = argn, ... })
		else
			Sched.call(c._ctx, c._fn, ...)
		end
	end
	local ws = self._w
	if ws then
		self._w = false
		for _, co in ws do
			table.insert(deferred, { f = co, n = argn, ... })
		end
	end
	if Sched.depth == 0 and not flushing then
		flushDeferred()
	end
end

function Signal.disconnectAll(self)
	for _, c in table.clone(self._h) do
		ConnM.Disconnect(c)
	end
end

return Sched
