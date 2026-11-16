--!strict
-- 견본: 폴더가 곧 모듈(init.luau) · 문자열로 부르는 require
local Child = require("@self/Child") -- 제 아이
local Stage = require("./Stage") -- 제 형제(script.Parent.Stage)
local Config = require("@game/ReplicatedStorage/shared/Config")

return {
	child = Child,
	stageSame = Stage == require(script.Parent.Stage),
	title = Config.TITLE,
	name = script.Name,
	className = script.ClassName,
}
