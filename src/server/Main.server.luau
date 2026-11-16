--!strict
-- 출근길 서바이벌 — 서버 시작. 2D 게임이라 3D 캐릭터를 만들지 않는다. 서버가 하는 일은 자료 저장뿐이다(Data.luau).
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local Data = require(script.Parent.Data)
Data.start()
