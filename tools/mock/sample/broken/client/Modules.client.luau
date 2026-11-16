-- (일부러 틀린 견본) 모듈을 잘못 부르는 것들 — 하나씩 pcall로 감싸 글을 찍는다
local function try(name: string)
	local ok, err = pcall(function()
		return require(script.Parent:FindFirstChild(name))
	end)
	print(name, ok, err)
end
try("CycleA")
try("NoReturn")
try("Missing")
-- 끝없이 기다리는 WaitForChild(5초 뒤 경고가 난다)
task.spawn(function()
	script.Parent:WaitForChild("NeverComes")
end)
