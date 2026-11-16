--!strict
-- 일시정지 · 설정(원본 #pause): 제목 + 설정 칸(.sets) + 단추 둘. 메뉴에서 「설정」으로 열면 제목 · 단추가 달라진다.
local T = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Stage = require(script.Parent.Parent.Stage) :: any

local C = T.C
local Pause = {}
-- App이 채운다
Pause.onSet = nil :: ((key: string, value: number) -> ())? -- 설정 값을 바꿨다
Pause.onSfxRelease = nil :: (() -> ())? -- 효과음 막대에서 손을 뗐다(원본: 'select' 소리)
Pause.onTutorial = nil :: (() -> ())? -- 안내 처음부터 다시 보기
Pause.onResume = nil :: (() -> ())?
Pause.onQuit = nil :: (() -> ())?

local ov: W.Overlay? = nil
local state = { title = "일시정지", sub = "열차가 잠시 정차 중입니다", resume = "계속 출근하기", quit = true, tutDone = false }
local values = { music = 80, sfx = 80, fx = 2, shake = 1, hand = 0, bloom = 1 } :: { [string]: number }
local segs = {} :: { [string]: W.Seg }
local sliders = {} :: { [string]: W.Slider }
Pause.E = {} :: { [string]: any }

local function render()
	local o: W.Overlay = ov or W.overlay("Pause", 30, T.rgb(12, 16, 18), 0.74)
	ov = o
	local keepY = o.scroll.CanvasPosition
	o.scroll:ClearAllChildren()
	table.clear(segs)
	table.clear(sliders)
	table.clear(Pause.E)
	local sw = Stage.w
	local pw = math.min(820, sw - 32)
	local panel = T.box(o.scroll, "Panel", { w = pw, h = 100 })
	local fs = math.clamp(0.07 * sw, 28, 42)
	local titleH = fs * 1.1
	Pause.E.title = T.label(panel, "Title", { text = state.title, fs = fs, font = "display", color = C.white, ax = "Center", x = 0, y = 0, w = pw, h = titleH, shadow = 0.35 })
	Pause.E.sub = T.label(panel, "Sub", { text = state.sub, fs = 13, wt = 500, color = T.hex("#c4cbcd"), ax = "Center", x = 0, y = titleH + 6, w = pw, h = 14.3 })
	local y = titleH + 6 + 14.3 + 14

	-- 설정 칸(.sets): 왼쪽 이름 · 오른쪽 조절
	local setsW = math.min(460, pw)
	local sets = T.box(panel, "Sets", { x = (pw - setsW) / 2, y = y, w = setsW, h = 100, bg = C.paper, r = 12 })
	local function pick(text: string, value: number): { any }
		return { text, value }
	end
	local rows: { { any } } = {
		{ "음악", "slider", "music" },
		{ "효과음", "slider", "sfx" },
		{ "이펙트", "seg", "fx", { pick("적게", 0), pick("보통", 1), pick("많이", 2) } },
		{ "빛 번짐", "seg", "bloom", { pick("켜기", 1), pick("끄기", 0) } },
		{ "화면 흔들림", "seg", "shake", { pick("켜기", 1), pick("끄기", 0) } },
		{ "대시 버튼", "seg", "hand", { pick("오른쪽", 0), pick("왼쪽", 1) } },
		{ "안내 (여유 전용)", "tut" },
	}
	local labels = {}
	local labelW = 0
	for i, row in ipairs(rows) do
		local l = T.label(sets, "Label" .. i, { text = row[1], fs = 14, wt = 700, color = C.ink })
		l.Size = UDim2.fromOffset(400, 20)
		labelW = math.max(labelW, (T.bounds(l)))
		labels[i] = l
	end
	local cx = 18 + labelW + 16
	local cwid = setsW - 18 - cx
	local sy = 14
	for i, row in ipairs(rows) do
		local kind = row[2]
		local h = if kind == "slider" then 28 else 37
		labels[i].Position = UDim2.fromOffset(18, sy)
		labels[i].Size = UDim2.fromOffset(labelW + 2, h)
		if kind == "slider" then
			local key = row[3]
			sliders[key] = W.slider(sets, "Set_" .. key, cx, sy, cwid, values[key], function(v)
				values[key] = v
				if Pause.onSet then
					Pause.onSet(key, v)
				end
			end, if key == "sfx" then function()
				if Pause.onSfxRelease then
					Pause.onSfxRelease()
				end
			end else nil)
		elseif kind == "seg" then
			local key = row[3]
			local sg = W.seg(sets, "Set_" .. key, cx, sy, cwid, row[4], function(v)
				if Pause.onSet then
					Pause.onSet(key, v)
				end
			end)
			sg.press(values[key])
			segs[key] = sg
		else
			local sg = W.seg(sets, "BtnTut", cx, sy, cwid, { { if state.tutDone then "다음 판부터 다시 나옵니다" else "처음부터 다시 보기", 1 } }, function()
				state.tutDone = true
				local b = Pause.E.tut :: TextButton
				local tl = b:FindFirstChild("T")
				if tl and tl:IsA("TextLabel") then
					tl.Text = "다음 판부터 다시 나옵니다"
				end
				if Pause.onTutorial then
					Pause.onTutorial()
				end
			end)
			sg.press(nil)
			Pause.E.tut = sg.buttons[1]
		end
		sy += h + 12
	end
	local _, noteH = T.para(sets, "Note", {
		text = "화면이 끊기면 빛 번짐을 끄고 이펙트를 줄여 보세요. 계속 끊기면 빛 번짐은 저절로 꺼집니다. 설정은 이 기기에 저장됩니다.",
		fs = 12,
		wt = 500,
		color = C.muted,
		lh = 1.5,
		x = 18,
		y = sy,
		w = setsW - 36,
	})
	sy += noteH + 14
	sets.Size = UDim2.fromOffset(setsW, sy)
	y += sy + 14

	-- 단추(.btnrow): 가운데로, 좁으면 아래로 넘긴다
	local bh = 61
	local function goW(text: string, fsz: number, padX: number): number
		local l = T.label(panel, "m", { text = text, fs = fsz, font = "display" })
		l.Size = UDim2.fromOffset(900, 30)
		local tw = T.bounds(l)
		l:Destroy()
		return math.max(200, tw + 2 * padX + 4)
	end
	local w1 = goW(state.resume, 24, 20)
	if state.quit then
		local w2 = goW("처음 화면으로", 18, 16)
		if w1 + 10 + w2 <= pw then
			local x0 = (pw - (w1 + 10 + w2)) / 2
			Pause.E.resume = W.go(panel, "BtnResume", { text = state.resume, x = x0, y = y, w = w1, h = bh })
			Pause.E.quit = W.go(panel, "BtnQuit", { text = "처음 화면으로", x = x0 + w1 + 10, y = y, w = w2, h = bh, sub = true })
			y += bh
		else
			Pause.E.resume = W.go(panel, "BtnResume", { text = state.resume, x = (pw - w1) / 2, y = y, w = w1, h = bh })
			Pause.E.quit = W.go(panel, "BtnQuit", { text = "처음 화면으로", x = (pw - w2) / 2, y = y + bh + 10, w = w2, h = 45, sub = true })
			y += bh + 10 + 45
		end
		Pause.E.quit.MouseButton1Click:Connect(function()
			if Pause.onQuit then
				Pause.onQuit()
			end
		end)
	else
		Pause.E.resume = W.go(panel, "BtnResume", { text = state.resume, x = (pw - w1) / 2, y = y, w = w1, h = bh })
		y += bh
	end
	Pause.E.resume.MouseButton1Click:Connect(function()
		if Pause.onResume then
			Pause.onResume()
		end
	end)
	panel.Size = UDim2.fromOffset(pw, y)
	o.place(panel, pw, y, nil, (pw - setsW) / 2)
	o.scroll.CanvasPosition = keepY
end

-- 원본 applySet의 화면 부분: 값에 맞춰 막대 · 눌린 단추를 맞춘다
function Pause.apply(set: { [string]: number })
	for k, v in set do
		values[k] = v
	end
	for k, sg in segs do
		sg.press(values[k])
	end
	for k, sl in sliders do
		sl.set(values[k])
	end
end

-- 창을 연다. quit = 「처음 화면으로」 단추를 보일까. 닫혀 있다가 열릴 때는 「안내」 단추의 글이 처음으로 돌아가지 않는다(원본과 같다)
function Pause.open(title: string, sub: string, resume: string, quit: boolean)
	state.title, state.sub, state.resume, state.quit = title, sub, resume, quit
	if ov then
		ov.root.Visible = true -- (글의 폭을 재기 전에 보이게 해 둔다)
	end
	render()
	if ov then
		ov.scroll.CanvasPosition = Vector2.zero
		ov.root.Visible = true
	end
end

function Pause.close()
	if ov then
		ov.root.Visible = false
	end
end

function Pause.isShown(): boolean
	return ov ~= nil and ov.root.Visible
end

function Pause.build()
	local was = Pause.isShown()
	if ov then
		ov.root:Destroy()
		ov = nil
	end
	if was then
		render()
		if ov then
			(ov :: W.Overlay).root.Visible = true
		end
	end
end

return Pause
