--!strict
-- 플레이어 자료(설정 · 본 안내 · 고른 난이도 · 난이도별 최고 기록)를 DataStore에 읽고 쓴다.
--  게임 규칙은 클라이언트에서 돈다(1인용) — 서버는 받은 값을 검사하고 저장만 한다.
--  DataStore를 못 쓰는 곳(API 접근을 끈 Studio · 게시하지 않은 플레이스)에서도 멈추지 않는다: 기본값으로 시작해 이 접속 동안은 기억에만 둔다.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Net"))

local Data = {}
Data.STORE = "SsbPlayer_v1"
Data.VERSION = 1
Data.LOAD_TRIES = 3 -- 읽기 시도 횟수 (사이에 0.5초, 1초)
Data.SAVE_TRIES = 2
Data.SAVE_DELAY = 5 -- 바뀐 뒤 이만큼 모았다가 쓴다(초)
Data.LOAD_WAIT = 9 -- Load 요청이 읽기를 기다리는 한도(초)
Data.BUCKET = 20 -- 한꺼번에 받을 수 있는 Save 수
Data.REFILL = 4 -- 초당 다시 차는 수
Data.RUN_SLACK = 10 -- 판의 시간 ≤ (지난 실제 시간 × 1.05 + 이 값)

type Dirty = { set: boolean, diff: boolean, seen: boolean, seenReset: boolean, best: { [string]: boolean } }
type Session = {
	data: Net.Data,
	loaded: boolean, -- 읽기 시도가 끝났다(성공이든 실패든)
	ok: boolean, -- DataStore에서 읽는 데 성공했다
	dirty: Dirty,
	saveAt: number?, -- 이 시각이 지나면 쓴다
	saving: boolean,
	runMark: number, -- 들어온 때 또는 마지막으로 판 결과를 보낸 때
	tokens: number,
	tokenAt: number,
	rejected: number, -- 버린 요청 수(시험 · 살펴보기용)
}

local store: any = nil
local storeTried = false
local sessions = {} :: { [Player]: Session }
Data.sessions = sessions

local function newDirty(): Dirty
	return { set = false, diff = false, seen = false, seenReset = false, best = {} }
end

local function isDirty(d: Dirty): boolean
	return d.set or d.diff or d.seen or d.seenReset or next(d.best) ~= nil
end

local function getStore(): any
	if not storeTried then
		storeTried = true
		local ok, res = pcall(function()
			return DataStoreService:GetDataStore(Data.STORE)
		end)
		if ok then
			store = res
		else
			warn("[ssb] DataStore를 쓸 수 없다 — 이번 서버에서는 기억에만 둔다: " .. tostring(res))
		end
	end
	return store
end

local function keyOf(player: Player): string
	return "u" .. player.UserId
end

-- 저장돼 있던 값(아무 모양일 수 있다) → 깨끗한 자료
function Data.parse(value: any): Net.Data
	local out = Net.defaults()
	if type(value) ~= "table" then
		return out
	end
	out.set = Net.mergeSettings(value.set)
	if type(value.seen) == "table" then
		for _, k in Net.HINT_KEYS do
			if value.seen[k] then
				out.seen[k] = 1
			end
		end
	end
	if Net.isDiff(value.diff) then
		out.diff = value.diff
	end
	if type(value.best) == "table" then
		for d = 0, Net.DIFF_COUNT - 1 do
			local rec = Net.cleanRecord(value.best[tostring(d)])
			if rec then
				out.best[tostring(d)] = rec
			end
		end
	end
	return out
end

-- 저장된 값 old에 이번 접속에서 바뀐 것(dirty)만 얹는다. 기록은 「더 나은 것」만 남긴다(다른 서버에서 먼저 쓴 값을 지우지 않게)
function Data.merge(old: any, data: Net.Data, dirty: Dirty): any
	local base = Data.parse(old)
	if dirty.set then
		base.set = table.clone(data.set)
	end
	if dirty.diff then
		base.diff = data.diff
	end
	if dirty.seenReset then
		base.seen = table.clone(data.seen)
	elseif dirty.seen then
		for k in data.seen do
			base.seen[k] = 1
		end
	end
	for d in dirty.best do
		local rec = data.best[d]
		if rec and Net.better(rec, base.best[d]) then
			base.best[d] = table.clone(rec)
		end
	end
	return { v = Data.VERSION, set = base.set, seen = base.seen, diff = base.diff, best = base.best, at = os.time() }
end

local function load(player: Player, s: Session)
	local st = getStore()
	if st then
		for try = 1, Data.LOAD_TRIES do
			local ok, value = pcall(function()
				return st:GetAsync(keyOf(player))
			end)
			if sessions[player] ~= s then
				return -- 그사이 나갔다
			end
			if ok then
				local got = Data.parse(value)
				-- 읽는 동안 이미 바뀐 칸은 그대로 두고 나머지를 채운다
				if not s.dirty.set then
					s.data.set = got.set
				end
				if not s.dirty.diff then
					s.data.diff = got.diff
				end
				if not s.dirty.seenReset then
					for k in got.seen do
						s.data.seen[k] = 1
					end
				end
				for d, rec in got.best do
					if Net.better(rec, s.data.best[d]) then
						s.data.best[d] = rec
					end
				end
				s.ok = true
				break
			end
			if try == Data.LOAD_TRIES then
				warn(("[ssb] %s의 자료를 읽지 못했다(기본값으로 시작): %s"):format(player.Name, tostring(value)))
			else
				task.wait(0.5 * try)
			end
		end
	end
	s.loaded = true
end

-- 바뀐 것을 쓴다. 돌려주는 것: 썼는가(쓸 것이 없어도 true)
local function save(player: Player, s: Session): boolean
	-- 쓰는 중이면 그것이 끝나기를 기다린다(서버가 닫힐 때 쓰던 것을 두고 가지 않게)
	while s.saving do
		task.wait()
	end
	if not isDirty(s.dirty) then
		return true
	end
	local st = getStore()
	if not st then
		return false
	end
	s.saving = true
	local taking = s.dirty
	s.dirty = newDirty()
	s.saveAt = nil
	local snapshot: Net.Data = { set = table.clone(s.data.set), seen = table.clone(s.data.seen), diff = s.data.diff, best = table.clone(s.data.best) }
	local done = false
	for try = 1, Data.SAVE_TRIES do
		local ok, err = pcall(function()
			st:UpdateAsync(keyOf(player), function(old)
				return Data.merge(old, snapshot, taking)
			end)
		end)
		if ok then
			done = true
			break
		end
		if try == Data.SAVE_TRIES then
			warn(("[ssb] %s의 자료를 저장하지 못했다: %s"):format(player.Name, tostring(err)))
		else
			task.wait(0.5)
		end
	end
	if not done then
		-- 못 쓴 것을 되돌려 놓는다(다음에 다시 쓴다)
		local d = s.dirty
		d.set = d.set or taking.set
		d.diff = d.diff or taking.diff
		d.seen = d.seen or taking.seen
		d.seenReset = d.seenReset or taking.seenReset
		for k in taking.best do
			d.best[k] = true
		end
	end
	s.saving = false
	return done
end
Data.save = save

local function touch(s: Session)
	if not s.saveAt then
		s.saveAt = os.clock() + Data.SAVE_DELAY
	end
end

-- 요청 수 제한(토큰 통)
local function allow(s: Session): boolean
	local now = os.clock()
	s.tokens = math.min(Data.BUCKET, s.tokens + (now - s.tokenAt) * Data.REFILL)
	s.tokenAt = now
	if s.tokens < 1 then
		return false
	end
	s.tokens -= 1
	return true
end

local function onSave(player: Player, kind: any, value: any)
	local s = sessions[player]
	if not s then
		return
	end
	if not allow(s) or type(kind) ~= "string" then
		s.rejected += 1
		return
	end
	if kind == "set" then
		local set = Net.cleanSettings(value)
		if not set then
			s.rejected += 1
			return
		end
		s.data.set = set
		s.dirty.set = true
	elseif kind == "seen" then
		if not Net.isHint(value) then
			s.rejected += 1
			return
		end
		if s.data.seen[value] then
			return
		end
		s.data.seen[value] = 1
		s.dirty.seen = true
	elseif kind == "seenReset" then
		s.data.seen = {}
		s.dirty.seenReset = true
		s.dirty.seen = false
	elseif kind == "diff" then
		if not Net.isDiff(value) then
			s.rejected += 1
			return
		end
		if s.data.diff == value then
			return
		end
		s.data.diff = value
		s.dirty.diff = true
	elseif kind == "run" then
		local now = os.clock()
		local elapsed = now - s.runMark
		s.runMark = now
		local d = if type(value) == "table" then value.diff else nil
		local rec = if Net.isDiff(d) then Net.cleanRecord(value) else nil
		-- 판의 시간은 실제로 흐른 시간보다 길 수 없다(규칙은 실제 시간보다 빨리 돌지 않는다)
		if not rec or rec.t > elapsed * 1.05 + Data.RUN_SLACK then
			s.rejected += 1
			return
		end
		local key = tostring(d)
		if not Net.better(rec, s.data.best[key]) then
			return
		end
		s.data.best[key] = rec
		s.dirty.best[key] = true
	else
		s.rejected += 1
		return
	end
	touch(s)
end

local function onLoad(player: Player): any
	local s = sessions[player]
	local t0 = os.clock()
	while (not s or not s.loaded) and os.clock() - t0 < Data.LOAD_WAIT do
		task.wait(0.1)
		s = sessions[player]
	end
	if not s then
		local d = Net.defaults()
		return { set = d.set, seen = d.seen, diff = d.diff, best = d.best, ok = false }
	end
	return { set = s.data.set, seen = s.data.seen, diff = s.data.diff, best = s.data.best, ok = s.ok }
end

local function added(player: Player)
	if sessions[player] then
		return
	end
	local now = os.clock()
	local s: Session = {
		data = Net.defaults(),
		loaded = false,
		ok = false,
		dirty = newDirty(),
		saveAt = nil,
		saving = false,
		runMark = now,
		tokens = Data.BUCKET,
		tokenAt = now,
		rejected = 0,
	}
	sessions[player] = s
	load(player, s)
end

local function removing(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	save(player, s)
	if sessions[player] == s then
		sessions[player] = nil
	end
end

function Data.start()
	local remotes = Net.serve()
	remotes.load.OnServerInvoke = onLoad
	remotes.save.OnServerEvent:Connect(onSave)
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(removing)
	for _, p in Players:GetPlayers() do
		task.spawn(added, p)
	end
	-- 모아 둔 것을 때가 되면 쓴다
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, s in sessions do
				if s.saveAt and now >= s.saveAt and not s.saving then
					task.spawn(save, player, s)
				end
			end
		end
	end)
	game:BindToClose(function()
		local left = 0
		for player, s in sessions do
			left += 1
			task.spawn(function()
				save(player, s)
				left -= 1
			end)
		end
		local t0 = os.clock()
		while left > 0 and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
	end)
end

return Data
