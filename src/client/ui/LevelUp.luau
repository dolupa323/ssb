--!strict
-- 고르는 창(원본 #levelup): 레벨 업 · 환승 보너스(보스 보상) · 오늘의 출근템(시작 무기). 선택지는 표 모양의 카드 3장.
--  원본 main.js의 showLevelUp()의 화면 부분.
local Sim = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("Sim")) :: any
local T = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Stage = require(script.Parent.Parent.Stage) :: any
local Art = require(script.Parent.Parent.Art) :: any
local Gfx = require(script.Parent.Parent.Gfx) :: any

local C = T.C
local LevelUp = {}
LevelUp.onPick = nil :: ((number) -> ())? -- 카드를 눌렀다(1부터)
LevelUp.onReroll = nil :: (() -> ())?
LevelUp.onHover = nil :: (() -> ())? -- 카드에 마우스가 올라갔다

-- 원본 LU
local LU = {
	start = { "오늘의 출근템", "시작 무기를 하나 고르세요" },
	chest = { "환승 보너스", "진상을 밀어낸 보상입니다. 하나를 더 챙기세요" },
	level = { "레벨 업", "하나를 골라 챙기세요" },
}

local ov: W.Overlay? = nil
local cur: { choices: { any }, pm: string, rerolls: number }? = nil
LevelUp.cards = {} :: { TextButton }
LevelUp.reroll = nil :: TextButton?

local function kindColor(kind: string): Color3
	if kind == "passive" then
		return T.hex("#e0a800")
	elseif kind == "evo" then
		return T.hex("#ff7a1f")
	elseif kind == "fuse" then
		return T.hex("#7a3fe0")
	elseif kind == "heal" then
		return C.danger
	end
	return C.line2
end

-- 카드 한 장을 만든다. 돌려주는 것: 단추, 타고난 높이, 높이를 맞추는 함수
local function makeCard(parent: Instance, c: any, i: number, cw: number, phone: boolean): (TextButton, number, (number) -> ())
	local col = kindColor(c.kind)
	local evo, fuse = c.kind == "evo" or c.kind == "fuse", c.kind == "fuse"
	local btn = T.button(parent, "Card" .. i, { w = cw, h = 100 })
	-- 그림자(0 6px 0) · 진화/조합 카드의 빛
	local shadow = T.box(btn, "Shadow", { pos = UDim2.fromOffset(0, 6), size = UDim2.fromScale(1, 1), bg = C.black, a = 0.4, r = 12 })
	local glow: Frame? = nil
	if evo then
		glow = T.box(btn, "Glow", { pos = UDim2.fromOffset(-4, -4), size = UDim2.new(1, 8, 1, 8), bg = if fuse then T.rgb(150, 90, 255) else T.rgb(255, 138, 60), a = if fuse then 0.45 else 0.4, r = 16 })
	end
	local body = T.box(btn, "Body", {
		size = UDim2.fromScale(1, 1),
		bg = C.paper,
		r = 12,
		clip = true,
		z = 2,
		grad = if fuse
			then { rot = 160, { 0, T.hex("#f1e6ff") }, { 0.55, T.hex("#fff3d6") }, { 1, T.hex("#e2fff0") } }
			elseif evo then { rot = 180, { 0, T.hex("#fff0d9") }, { 1, T.hex("#fff8ec") } }
			else nil,
	})
	-- 머리띠(.tag): 갈래 이름 + 글쇠 번호
	local tagH = 30
	local tag = T.box(body, "Tag", { w = cw, h = tagH, bg = col, r = 12 })
	T.box(tag, "Sq", { pos = UDim2.fromOffset(0, tagH / 2), size = UDim2.new(1, 0, 0.5, 0), bg = col })
	T.label(tag, "T", { text = c.tag or "", fs = 12, wt = 700, color = if c.kind == "passive" then T.hex("#2a2100") else C.white, x = 14, y = 0, w = cw - 60, h = tagH, z = 2 })
	local kl = T.label(tag, "KeyT", { text = tostring(i), fs = 18, font = "led", color = C.led, ax = "Center", z = 3 })
	kl.Size = UDim2.fromOffset(100, 20)
	local kw = T.bounds(kl) + 14
	T.box(tag, "Key", { x = cw - 10 - kw, y = 5, w = kw, h = 20, bg = C.ink, r = 4, z = 2 })
	kl.Position = UDim2.fromOffset(cw - 10 - kw, 5)
	kl.Size = UDim2.fromOffset(kw, 20)

	-- 가운데(.mid): 그림 + 이름 + 레벨 점 + 설명
	local padX = if phone then 12 else 14
	local padT, padB = if phone then 8 else 11, if phone then 8 else 10
	local gap = if phone then 4 else 7
	local imgS = if phone then 40 else 50
	local nameFs = if phone then 20 else 23
	local y = tagH + padT
	local imgBack = T.box(body, "IconBack", { x = padX, y = y, w = imgS, h = imgS, bg = if fuse then T.hex("#2a1f3d") elseif evo then T.hex("#ffd9a8") else T.hex("#e7e3d8"), r = 10 })
	local im = Instance.new("ImageLabel")
	im.Name = "Icon"
	im.BackgroundTransparency = 1
	im.BorderSizePixel = 0
	im.Position = UDim2.fromOffset(3, 3)
	im.Size = UDim2.new(1, -6, 1, -6)
	pcall(Art.set, im, Gfx.icon(c.key, evo))
	im.Parent = imgBack
	local tx = padX + imgS + 10
	local tw = cw - tx - padX
	local name, nameH = T.para(body, "CardName", { text = c.name or "", fs = nameFs, font = "display", color = C.ink, lh = 1.1, w = tw })
	-- 레벨 줄(.lv)
	local lvH = 18
	local lv = T.box(body, "Lv", { w = tw, h = lvH })
	local lx = 0
	local mx = if c.kind == "weapon" then Sim.WMAX else Sim.PMAX
	if c.kind == "weapon" or c.kind == "passive" then
		for j = 1, mx do
			if j == c.to then
				-- 새로 켜지는 칸: 바깥에 종이색 2px + 색 1.5px 고리(자리를 차지하지 않는다), 양옆 여백 2.5px
				lx += 2.5
				T.box(lv, "ring", { x = lx - 3.5, y = (lvH - 16) / 2, w = 16, h = 16, bg = col, r = 4 })
				T.box(lv, "gap", { x = lx - 2, y = (lvH - 13) / 2, w = 13, h = 13, bg = C.paper, r = 3.5 })
				T.box(lv, "pip", { x = lx, y = (lvH - 9) / 2, w = 9, h = 9, bg = col, r = 2, z = 2 })
				lx += 9 + 2.5
			else
				T.box(lv, "pip", { x = lx, y = (lvH - 9) / 2, w = 9, h = 9, bg = if j < c.to then col else T.hex("#d6d2c7"), r = 2 })
				lx += 9
			end
			lx += 2.5
		end
		lx += 7 - 2.5
	end
	local lvText = if fuse
		then "숨겨진 조합 발견"
		elseif c.kind == "evo" then "최종 진화"
		elseif c.kind == "heal" then "즉시 사용"
		elseif c.to == 1 then "새로 얻기"
		else "Lv " .. tostring(c.to) .. (if c.to == mx then " (최대)" else "")
	T.label(lv, "T", { text = lvText, fs = 12, wt = 700, color = C.muted, x = lx, y = 0, w = math.max(10, tw - lx), h = lvH })
	local hwH = nameH + 3 + lvH
	local headH = math.max(imgS, hwH)
	imgBack.Position = UDim2.fromOffset(padX, y + (headH - imgS) / 2)
	name.Position = UDim2.fromOffset(tx, y + (headH - hwH) / 2)
	lv.Position = UDim2.fromOffset(tx, y + (headH - hwH) / 2 + nameH + 3)
	y += headH + gap
	local _, descH = T.para(body, "Desc", { text = c.desc or "", fs = if phone then 13 else 13.5, color = C.ink, lh = 1.45, x = padX, y = y, w = cw - 2 * padX })
	y += descH + padB

	-- 아래 쪽지(.hint): 점선 + 양옆의 반달 홈
	local hPadT, hPadB = if phone then 5 else 7, if phone then 7 else 9
	local hint = T.box(body, "Hint", { x = 0, y = y, w = cw, h = 10 })
	local _, hintTextH = T.para(hint, "T", { text = c.hint or "", fs = 11.5, wt = 600, color = C.muted, lh = 1.45, x = padX, y = 2 + hPadT, w = cw - 2 * padX })
	if (c.hint or "") == "" then
		hintTextH = 0
	end
	local hintH = math.max(if phone then 0 else 32, 2 + hPadT + hintTextH + hPadB)
	hint.Size = UDim2.fromOffset(cw, hintH)
	local dx = 8
	while dx < cw - 8 do
		T.box(hint, "d", { x = dx, y = 0, w = math.min(6, cw - 8 - dx), h = 2, bg = T.hex("#c9c5ba") })
		dx += 10
	end
	T.box(hint, "NotchL", { x = -9, y = -9, w = 16, h = 16, bg = T.hex("#1b2225"), r = 1000, z = 2 })
	T.box(hint, "NotchR", { x = cw - 7, y = -9, w = 16, h = 16, bg = T.hex("#1b2225"), r = 1000, z = 2 })
	local natural = y + hintH
	local function setHeight(h: number)
		btn.Size = UDim2.fromOffset(cw, h)
		hint.Position = UDim2.fromOffset(0, h - hintH) -- 쪽지는 바닥에 붙는다(.mid가 flex:1)
	end
	local _ = shadow
	local _ = glow
	return btn, natural, setHeight
end

-- 원본 showLevelUp(ch, pm)의 화면 부분. again = 화면 크기가 바뀌어 다시 그리는 것(등장 움직임 없이)
function LevelUp.show(choices: { any }, pm: string, rerolls: number, again: boolean?)
	cur = { choices = choices, pm = pm, rerolls = rerolls }
	local o: W.Overlay = ov or W.overlay("LevelUp", 20, T.rgb(12, 16, 18), 0.74)
	ov = o
	o.root.Visible = true -- (글의 폭을 재기 전에 보이게 해 둔다)
	o.scroll:ClearAllChildren()
	o.scroll.CanvasPosition = Vector2.zero
	local sw = Stage.w
	local phone = Stage.phone
	local pw = math.min(820, sw - 32)
	local panel = T.box(o.scroll, "Panel", { w = pw, h = 100 })
	-- 제목(h2) + 작은 글
	local t = LU[pm] or LU.level
	local fs = math.clamp(0.07 * sw, 28, 42)
	local titleH = fs * 1.1
	T.label(panel, "Title", { text = t[1], fs = fs, font = "display", color = C.white, ax = "Center", x = 0, y = 0, w = pw, h = titleH, shadow = 0.35 })
	T.label(panel, "Sub", { text = t[2], fs = 13, wt = 500, color = T.hex("#c4cbcd"), ax = "Center", x = 0, y = titleH + 6, w = pw, h = 14.3 })
	local y = titleH + 6 + 14.3 + 14
	-- 카드
	local n = #choices
	local gap = if phone then 9 else 12
	local cw = if phone then pw else (pw - 2 * gap) / 3
	local cards = {}
	local maxH = if phone then 0 else 190
	local made = {}
	for i, c in ipairs(choices) do
		local btn, natural, setHeight = makeCard(panel, c, i, cw, phone)
		made[i] = { btn, natural, setHeight }
		if not phone then
			maxH = math.max(maxH, natural)
		end
		cards[i] = btn
	end
	local cy = y
	for i, m in ipairs(made) do
		local btn = m[1] :: TextButton
		local h = if phone then m[2] else maxH
		m[3](h)
		local bx, by = if phone then 0 else (i - 1) * (cw + gap), cy
		btn.Position = UDim2.fromOffset(bx, by)
		if phone then
			cy += h + gap
		end
		-- 등장(cardin .22s: 아래 14px에서 올라오며 나타난다 · 카드마다 0.05초씩 늦게) + 마우스를 올리면 4px 위로(.08s)
		local enter, hover = 1, 0
		local function put()
			btn.Position = UDim2.fromOffset(bx, by + 14 * (1 - enter) - 4 * hover)
		end
		if not again then
			local f = T.fader(btn)
			T.animate(0.22, T.EASE.ease, function(x)
				enter = x
				f(x)
				put()
			end, (i - 1) * 0.05)
		end
		local setHover = T.transition(0.08, T.EASE.ease, function(v)
			hover = v
			put()
		end)
		setHover(0, true)
		T.states(btn, function(over)
			setHover(if over then 1 else 0)
			if over and LevelUp.onHover then
				LevelUp.onHover()
			end
		end, nil)
		btn.MouseButton1Click:Connect(function()
			if LevelUp.onPick then
				LevelUp.onPick(i)
			end
		end)
	end
	y = if phone then cy - gap else y + maxH
	if n == 0 then
		y += 0
	end
	-- 다시 뽑기(.lu-foot)
	y += 14
	LevelUp.reroll = nil
	if pm ~= "start" then
		local rb = T.button(panel, "BtnReroll", { w = 100, h = 41, bg = C.white, a = 0.1, r = 8, b = 2, bc = C.white, ba = 0.6 })
		local l = T.label(rb, "T", { text = "다시 뽑기 " .. rerolls .. "회 남음", fs = 14, wt = 700, color = C.white })
		l.Size = UDim2.fromOffset(600, 37)
		local tw = T.bounds(l)
		l.Position = UDim2.fromOffset(14, 0)
		l.Size = UDim2.fromOffset(tw + 1, 37)
		local _, kw = W.kbd(rb, "R", 14 + tw + 6, (37 - 23) / 2, true)
		local bw = 16 + tw + 6 + kw + 2 + 16
		rb.Size = UDim2.fromOffset(bw - 4, 37)
		rb.Position = UDim2.fromOffset((pw - bw) / 2 + 2, y + 2)
		local disabled = rerolls <= 0
		if disabled then
			T.fader(rb)(0.35)
			rb.Active = false
		else
			T.states(rb, function(over)
				rb.BackgroundTransparency = if over then 0.8 else 0.9
			end, nil)
			rb.MouseButton1Click:Connect(function()
				if LevelUp.onReroll then
					LevelUp.onReroll()
				end
			end)
		end
		rb:SetAttribute("Disabled", disabled)
		LevelUp.reroll = rb
		y += 41
	end
	panel.Size = UDim2.fromOffset(pw, y)
	o.place(panel, pw, y)
	LevelUp.cards = cards
	o.root.Visible = true
end

function LevelUp.hide()
	if ov then
		ov.root.Visible = false
	end
end

function LevelUp.isShown(): boolean
	return ov ~= nil and ov.root.Visible
end

-- 화면 크기가 바뀌었다
function LevelUp.build()
	local was = LevelUp.isShown()
	if ov then
		ov.root:Destroy()
		ov = nil
	end
	local c = cur
	if was and c then
		LevelUp.show(c.choices, c.pm, c.rerolls, true)
	end
end

return LevelUp
