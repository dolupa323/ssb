-- (일부러 틀린 견본) 서버에서 흔한 실수
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

Players.PlayerAdded:Connect(function(player)
	local store = DataStoreService:GetDataStore("Bad")
	store:SetAsync("u" .. player.UserId, { name = player.Name, onDone = function() end }) -- 함수는 저장할 수 없다
end)

-- 서버에는 LocalPlayer가 없다
print(Players.LocalPlayer.Name)
