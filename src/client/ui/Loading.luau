--!strict
-- 불러오는 화면(원본에는 없다 — 그림 판을 만들고 서버에서 자료를 읽는 동안 Roblox에서만 필요하다).
local T = require(script.Parent.Theme)
local Stage = require(script.Parent.Parent.Stage) :: any

local Loading = {}
local root: Frame? = nil
local label: TextLabel? = nil

function Loading.show()
	if root then
		return
	end
	local r = T.box(Stage.top, "Loading", { size = UDim2.fromScale(1, 1), bg = T.C.body, active = true })
	local s = Instance.new("UIScale")
	s.Scale = Stage.scale
	s.Parent = r
	r.Size = UDim2.fromScale(1 / Stage.scale, 1 / Stage.scale)
	T.label(r, "Title", { text = "출근길 서바이벌", fs = 40, font = "display", color = T.C.white, ax = "Center", pos = UDim2.new(0, 0, 0.5, -44), size = UDim2.new(1, 0, 0, 48) })
	label = T.label(r, "Text", { text = "불러오는 중…", fs = 14, wt = 500, color = T.hex("#8e999c"), ax = "Center", pos = UDim2.new(0, 0, 0.5, 14), size = UDim2.new(1, 0, 0, 20) })
	root = r
end

function Loading.text(s: string)
	if label then
		label.Text = s
	end
end

function Loading.hide()
	if root then
		root:Destroy()
		root = nil
		label = nil
	end
end

function Loading.isShown(): boolean
	return root ~= nil
end

return Loading
