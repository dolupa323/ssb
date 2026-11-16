-- AssetIds 모듈이 있을 때: 번호가 적힌 판은 Image(에셋 번호)로, 나머지는 EditableImage(ImageContent)로 붙는지 본다
local h = harness
local RS = game:GetService("ReplicatedStorage")
local client = h.player().PlayerScripts.client
local Art = h.require(client.Art)
h.expect(RS.shared.art:FindFirstChild("AssetIds") ~= nil, "시험용 AssetIds 모듈이 있다")
h.asClient(function()
	Art.init()
end)
h.waitFor(function()
	return Art.ready
end, 30, "Art.ready")
h.eq(#Art.failed, 0, "실패한 판이 없다")
local gui = Instance.new("ScreenGui")
gui.Parent = h.playerGui()
local function label(name)
	local l = Instance.new("ImageLabel")
	l.Size = UDim2.fromOffset(64, 64)
	l.Parent = gui
	Art.set(l, name)
	return l
end
local a = label("char/player/0/0") -- chars1: 문자열 번호
h.eq(a.Image, "rbxassetid://111", "chars1 판은 올린 에셋을 쓴다")
local b = label("floor/street") -- floor_street: 숫자 번호
h.eq(b.Image, "rbxassetid://222", "floor_street 판은 숫자로 적어도 된다")
local c = label("fx/glow") -- fx1: 번호 없음 → 코드에 실린 점 자료
h.eq(c.Image, "", "번호가 없는 판은 Image가 비어 있다")
h.expect(c.ImageContent ~= nil and c.ImageContent.Object ~= nil, "번호가 없는 판은 EditableImage로 붙는다")
local d = label("prim/ring") -- 셈으로 그린 판
h.expect(d.ImageContent ~= nil and d.ImageContent.Object ~= nil, "도움 그림 판은 늘 EditableImage")
h.eq(a.ImageRectSize, Vector2.new(61, 98), "자르는 네모")
print("AssetIds 시험 끝")
