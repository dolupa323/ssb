--!strict
-- 견본 서버: 기록만 저장한다(게임은 클라이언트에서 돈다).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.shared.Config)
local Remotes = require(ReplicatedStorage.shared.Remotes)

local store = DataStoreService:GetDataStore(Config.STORE)
local best: { [number]: number } = {}

local function load(player: Player)
	local ok, value = pcall(function()
		return store:GetAsync("u" .. player.UserId)
	end)
	if ok then
		best[player.UserId] = if typeof(value) == "table" and typeof(value.best) == "number" then value.best else 0
	else
		warn("기록을 읽지 못했다:", value)
		best[player.UserId] = 0
	end
	print("서버: 읽은 최고 기록", player.Name, best[player.UserId])
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

Remotes.best.OnServerInvoke = function(player: Player)
	while best[player.UserId] == nil do
		task.wait()
	end
	return best[player.UserId]
end

Remotes.submit.OnServerEvent:Connect(function(player: Player, score: any)
	if typeof(score) ~= "number" or score ~= score then
		return
	end
	local newBest = 0
	local ok, err = pcall(function()
		store:UpdateAsync("u" .. player.UserId, function(old)
			local was = if typeof(old) == "table" and typeof(old.best) == "number" then old.best else 0
			newBest = math.max(was, score)
			return { best = newBest, at = os.time() }
		end)
	end)
	if ok then
		best[player.UserId] = newBest
		Remotes.saved:FireClient(player, newBest)
	else
		warn("기록을 저장하지 못했다:", err)
	end
end)

game:BindToClose(function()
	task.wait(0.1)
	print("서버: 닫는다")
end)
