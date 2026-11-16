-- (mock 확인용) 베껴 온 stage · canvas · sprite가 mock에서 낸 결과를 본다.
--  node tools/mock/run.mjs --project tools/mock/work/lune-check/default.project.json --script tools/mock/work/lune-check/check.luau --shot-dir tools/mock/work/lune-check
local h = harness
h.step(3)
local gui = h.get("PlayerGui.LuneStage")
local view = h.get("PlayerGui.LuneStage.Holder.View")
local ui = h.get("PlayerGui.LuneStage.Holder.Ui")
-- 1280x720: 384x216이 3배로 들어간다 → 화면 틀의 배율은 1(격자 1152x648)
h.eq(view.UIScale.Scale, 3, "게임 세계의 배율")
h.eq(ui.UIScale.Scale, 1, "화면 틀의 배율")
h.eq({ h.rect(h.get("PlayerGui.LuneStage.Holder")) }, { 64, 36, 1152, 648 }, "틀의 자리")
h.eq(ui.Size, UDim2.fromOffset(1152, 648), "화면 틀의 격자")
-- 그림판
local fxBack = view.World.FxBack
local img = fxBack.ImageContent.Object
h.eq(img.Size, Vector2.new(384, 216), "그림판의 크기")
local function pixel(x, y)
	local b = img:ReadPixelsBuffer(Vector2.new(x, y), Vector2.new(1, 1))
	return { buffer.readu8(b, 0), buffer.readu8(b, 1), buffer.readu8(b, 2), buffer.readu8(b, 3) }
end
h.eq(pixel(12, 12), { 255, 48, 48, 255 }, "빨간 네모")
h.eq(pixel(90, 60), { 48, 255, 48, 128 }, "반쯤 비치는 초록 네모")
h.eq(pixel(50, 35), { 151, 152, 48, 255 }, "겹친 자리(섞인 색)")
-- stage.luau가 pcall로 감싸 부르는 것들이 mock에서 오류 없이 되는가(pcall이 오류를 삼키므로 따로 본다)
h.eq(h.pcallAs("client", function()
	local StarterGui = game:GetService("StarterGui")
	for _, kind in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
		StarterGui:SetCoreGuiEnabled(kind, false)
	end
	game:GetService("GuiService").TouchControlsEnabled = false
	game.Players.LocalPlayer:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	return game:GetService("UserInputService").PreferredInput == Enum.PreferredInput.KeyboardAndMouse
end), true, "stage.luau가 pcall 안에서 부르는 것들")
h.eq(game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList), false, "참가자 목록을 껐다")
h.eq(pixel(300, 200), { 0, 0, 0, 0 }, "빈 자리")
-- 캐릭터 그림
local hero = view.World:FindFirstChild("hero")
h.eq(hero.Image, "rbxassetid://1001", "캐릭터 판")
h.eq({ hero.ImageRectOffset, hero.ImageRectSize }, { Vector2.new(32, 0), Vector2.new(32, 32) }, "둘째 장")
h.eq(hero.Position, UDim2.fromOffset(104, 128), "발밑 가운데(120, 160)에 맞춘 자리")
h.eq(hero.robeL.ImageColor3, Color3.fromRGB(0x30, 0x60, 0xff), "염색 겹(로브)의 색")
h.eq(hero.pointL.Image, "rbxassetid://1004", "염색 겹(무기)의 판")
-- 화면 구석에 붙인 판
local corner = ui.Corner
h.eq({ h.rect(corner) }, { 64 + 1152 - 100, 36 + 648 - 60, 90, 50 }, "오른쪽 아래에서의 거리가 같게 놓인다")
-- Roblox 단추 띠: 틀의 위(36)가 띠(58)보다 위라 22만큼 가려진다
h.eq(ui.Hud.Position, UDim2.new(0, 10, 0, 10 + 22), "왼쪽 위의 판은 Roblox 단추 띠만큼 내려간다")
h.shot("lune-1280x720.png")
-- 폰 화면으로
h.resize(844, 390)
h.step(2)
h.near(view.UIScale.Scale, 390 / 216, 1e-9, "폰: 화면에 꽉 차게")
h.near(ui.UIScale.Scale, (390 / 216) * 384 / 768, 1e-9, "폰: 화면 틀은 가장 작은 격자")
h.shot("lune-844x390.png")
-- 손가락 화면
gui:SetAttribute("Touch", true)
h.step(1)
h.eq(h.pcallAs("client", function()
	return require(game.Players.LocalPlayer.PlayerScripts.client.lune.stage).touchLike()
end), true, "Touch 속성(Attribute)")
print("끝: lune-check")
