--!strict
-- (일부러 틀린 견본) 아무도 부르지 않는 모듈 — 돌려서는 못 잡고, analyze.mjs(돌리지 않는 검사)가 잡아야 하는 것들
local Static = {}

local function area(w: number, h: number): number
	return w * h
end

function Static.unused()
	local label = Instance.new("TextLable") -- 없는 클래스
	label.Font = Enum.Font.SourceSansBolt -- 없는 열거형 값
	label.TextXAlignment = Enum.TextXAlignmet.Left -- 없는 열거형
	local tween = game:GetService("TweenServise") -- 없는 서비스
	if label:IsA("GuiObjekt") then -- 없는 클래스 이름
		print(area(1)) -- 인자가 모자란다
	end
	print(area("a", 2), undefinedName, tween) -- 형이 틀리다 · 없는 이름
	return label.AbsolutSize -- 오타(없는 이름을 읽는다)
end

return Static
