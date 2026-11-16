--!nonstrict
-- Studio에서만 켜지는 시험용 창구 — 원본의 `window.__dbg`(index.html#dbg) 자리.
--  원본 웹게임과 같은 상태(장소 · 보스 · 무기)를 만들어 나란히 찍어 견주는 데 쓴다(tools/studio/compare.mjs).
--  게시된 게임에서는 아무것도 하지 않는다(IsStudio가 아니면 바로 끝난다).
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fn = Instance.new("BindableFunction")
fn.Name = "SsbDebug"

local App, Sim
local function sim()
	if not App then
		App = require(script.Parent.ui.App) -- 처음 불릴 때(게임이 뜬 뒤) 읽는다
		Sim = require(ReplicatedStorage.shared.Sim)
	end
	return App.sim
end

fn.OnInvoke = function(cmd: string, a: any, b: any, c: any)
	local s = sim()
	if not s then
		return "sim 없음"
	end
	local S = s.S
	local p = S.p
	if cmd == "info" then
		return ("paused=%s mode=%s state=%s zone=%d t=%.1f zt=%.1f lv=%d hp=%.0f/%.0f enemies=%d phase=%s boss=%s x=%.0f y=%.0f dashes=%d"):format(
			tostring(App.paused), tostring(App.mode), tostring(S.state), S.zone, S.t, S.zt, p.level, p.hp, p.maxhp, #S.enemies, tostring(S.phase), tostring(S.gate and S.gate.type), p.x, p.y, S.dashes
		)
	elseif cmd == "god" then -- 찍는 동안 죽지 않고 · 선택 창이 뜨지 않게
		S.admNoPick = a ~= false
		p.inv = if a ~= false then 1e9 else 0
		p.hp = p.maxhp
	elseif cmd == "zone" then
		s.dbg.enterZone(a)
		p.hp = p.maxhp
	elseif cmd == "boss" then
		s.dbg.boss(a)
	elseif cmd == "set" then
		S[a] = b
	elseif cmd == "pset" then
		p[a] = b
	elseif cmd == "build" then -- a = {{이름, 레벨}…} 무기 · b = {{이름, 레벨}…} 장비 · c = {조합 이름…}
		S.weapons, S.passives, S.fus, S.fsrc, S.wt = {}, {}, {}, {}, {}
		S.wOrder, S.pOrder, S.fOrder = {}, {}, {}
		S.mace, S.gent, S.umbQ = nil, nil, nil
		table.clear(S.beams)
		for _, w in a or {} do
			S.weapons[w[1]] = w[2]
			table.insert(S.wOrder, w[1])
		end
		for _, q in b or {} do
			S.passives[q[1]] = q[2]
			table.insert(S.pOrder, q[1])
		end
		for _, k in c or {} do
			S.fus[k] = 1
			table.insert(S.fOrder, k)
			local f = Sim.FUSIONS[k]
			S.fsrc[f.a], S.fsrc[f.b] = 1, 1
		end
		s.dbg.recalc()
		p.hp = p.maxhp
	elseif cmd == "killgate" then
		if S.gate then
			s.dbg.kill(S.gate, "card")
		end
	elseif cmd == "die" then -- 지금 죽게 한다
		S.admNoPick = false
		p.inv = 0
		p.hp = 0.01
		for i = 1, 12 do
			s.dbg.spawn("pass", p.x + i, p.y)
		end
	elseif cmd == "find" then -- 글에 a가 들어간 보이는 단추의 한가운데(화면 좌표)
		local gui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		for _, d in gui:GetDescendants() do
			if d:IsA("GuiButton") then
				local text = if d:IsA("TextButton") then d.Text else ""
				for _, t in d:GetDescendants() do
					if t:IsA("TextLabel") then
						text ..= " " .. t.Text
					end
				end
				if text:find(a, 1, true) and d.AbsoluteSize.X > 0 then
					local vis, q = true, d :: Instance
					while q and q:IsA("GuiObject") do
						if not (q :: GuiObject).Visible then
							vis = false
							break
						end
						q = q.Parent :: Instance
					end
					if vis then
						-- AbsolutePosition은 Roblox 위쪽 띠 아래가 원점이다 → 화면 좌표로 바꾸려고 띠의 높이를 더한다
						local at = d.AbsolutePosition + d.AbsoluteSize / 2 + game:GetService("GuiService"):GetGuiInset()
						return ("%d,%d"):format(at.X, at.Y)
					end
				end
			end
		end
		return "없음"
	else
		return "모르는 명령 " .. tostring(cmd)
	end
	return "ok"
end
fn.Parent = ReplicatedStorage
