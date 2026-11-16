--!strict
-- 서버와 클라이언트가 주고받는 길. 서버가 만들고, 클라이언트는 기다렸다가 받는다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local function get(className: string, name: string): any
	if RunService:IsServer() then
		local found = ReplicatedStorage:FindFirstChild(name)
		if found then
			return found
		end
		local r = Instance.new(className)
		r.Name = name
		r.Parent = ReplicatedStorage
		return r
	end
	return ReplicatedStorage:WaitForChild(name)
end

Remotes.submit = get("RemoteEvent", "Submit") :: RemoteEvent -- 클라 → 서버: 점수를 낸다
Remotes.best = get("RemoteFunction", "GetBest") :: RemoteFunction -- 클라 → 서버: 내 최고 기록을 묻는다
Remotes.saved = get("RemoteEvent", "Saved") :: RemoteEvent -- 서버 → 클라: 저장했다(최고 기록)

return Remotes
