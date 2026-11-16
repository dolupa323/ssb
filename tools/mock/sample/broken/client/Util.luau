-- (일부러 틀린 견본) 모듈 안의 오타
local Util = {}

function Util.style(label: TextLabel)
	label.TextSize = 14
	(label :: any).TextColour3 = Color3.new(1, 1, 1) -- 오타: TextColor3
end

return Util
