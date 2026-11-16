--!strict
-- 출근길 서바이벌 — 클라이언트 시작. 이 폴더(client) 전체가 LocalScript 하나가 된다.
--  차례: 화면 틀 → 불러오는 화면 → (서버 자료 읽기 ∥ 그림 판 만들기) → 세계 그리기 준비 → 메뉴(뒤에서 시연이 돈다).
--  게임의 진행은 ui/App.luau(원본 js/main.js)에 있다.
local Stage = require(script.Stage)
Stage.init()

-- 구운 글자 판(작은 판 셋)을 먼저 만든다 — 불러오는 화면의 제목부터 그 글자로 그린다
local Bitmap = require(script.ui.Bitmap)
local okFont, errFont = (pcall :: any)(Bitmap.init)
if not okFont then
	warn("[ssb] 글자 판을 만들지 못했다(보통 글꼴로 그린다): " .. tostring(errFont))
	Bitmap.ready = true
end

local Loading = require(script.ui.Loading)
Loading.show()

local Store = require(script.ui.Store)
local Art = require(script.Art) :: any

local storeDone, artDone = false, false
task.spawn(function()
	local ok, err = (pcall :: any)(Store.load)
	if not ok then
		warn("[ssb] 저장된 자료를 읽지 못했다(기본값으로 시작): " .. tostring(err))
	end
	storeDone = true
end)
task.spawn(function()
	local Theme = require(script.ui.Theme)
	;(pcall :: any)(Theme.preload) -- 본문 글꼴을 미리 읽는다
	;(pcall :: any)(Theme.calibrate, Stage.ui) -- 글의 폭을 재는 자를 맞춘다(견본 꼬리표)
	local ok, err = (pcall :: any)(Art.init)
	if not ok then
		warn("[ssb] 그림 판을 만들지 못했다: " .. tostring(err))
	end
	artDone = true
end)
while not (storeDone and artDone) do
	task.wait()
end

local Gfx = require(script.Gfx) :: any
Gfx.init(Stage.world, Stage.overlay)

local App = require(script.ui.App)
App.boot()
Loading.hide()
