-- 빠르기 재기: 움직이는 ImageLabel 수백 개로 600장을 넘기는 데 걸리는 시간.
--  node tools/mock/run.mjs --project tools/mock/sample/default.project.json --script tools/mock/sample/scenarios/perf.luau
local h = harness
local RunService = game:GetService("RunService")
local N = 300

local world = h.get("PlayerGui.Sample.Holder.View.World")
local content = world.PersonRight.ImageContent
local sprites = {}

h.asClient(function()
	for i = 1, N do
		local label = Instance.new("ImageLabel")
		label.Name = "Mob" .. i
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		label.Size = UDim2.fromOffset(16, 16)
		label.ImageContent = content
		label.ImageRectSize = Vector2.new(16, 16)
		label.Parent = world
		sprites[i] = { label = label, x = (i * 37) % 368, y = (i * 53) % 200, vx = ((i % 5) - 2) * 20, vy = ((i % 3) - 1) * 15, frame = 0 }
	end
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for i, sp in sprites do
			sp.x += sp.vx * dt
			sp.y += sp.vy * dt
			if sp.x < 0 or sp.x > 368 then
				sp.vx = -sp.vx
			end
			if sp.y < 0 or sp.y > 200 then
				sp.vy = -sp.vy
			end
			local label = sp.label
			label.Position = UDim2.fromOffset(math.floor(sp.x + 0.5), math.floor(sp.y + 0.5))
			-- 여덟 장에 한 번 그림 장을 바꾼다 · 가는 쪽으로 뒤집는다
			local frame = math.floor(t * 8 + i) % 4
			if frame ~= sp.frame then
				sp.frame = frame
				if sp.vx < 0 then
					label.ImageRectOffset = Vector2.new(frame * 16 + 16, 0)
					label.ImageRectSize = Vector2.new(-16, 16)
				else
					label.ImageRectOffset = Vector2.new(frame * 16, 0)
					label.ImageRectSize = Vector2.new(16, 16)
				end
			end
			label.ZIndex = 1 + math.floor(sp.y) -- 아래에 있는 것이 앞에
		end
	end)
end)

local t0 = h.wallClock()
h.step(600)
local t1 = h.wallClock()
local shot0 = h.wallClock()
local data = h.capture()
local shot1 = h.wallClock()
print(string.format("움직이는 ImageLabel %d개 · 600장: %.3f초 (한 장 %.3f ms) · 화면 적기 한 번(마디 %d개): %.1f ms", N, t1 - t0, (t1 - t0) / 600 * 1000, #data.items, (shot1 - shot0) * 1000))
h.eq(#h.findAllByClass("ImageLabel", world) >= N, true, "만든 것이 다 있다")
h.shot("perf.png")
