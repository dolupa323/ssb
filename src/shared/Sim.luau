--!native
--!optimize 2
--[[
	출근길 서바이벌 — 게임 규칙 (화면 없음)
	원본 commute-survival/js/sim.js 를 줄마다 옮긴 것. Roblox API 도 require 도 쓰지 않는다
	(Roblox 안에서도, tools/luau/luau.exe 로도 돈다). 같은 난수열을 넣으면 원본과 같은 게임이 나온다
	(tools/parity 가 원본 JS 와 견준다. 쓰는 법은 tools/parity/SIM_API.md).

	옮길 때 지킨 약속
	- 0부터 세는 "숫자 상태"는 숫자 그대로: S.zone(0..6 → ZONES[S.zone+1]), S.diff, S.stopIdx, 김 팀장의 e.day,
	  e.st, 광선의 b.j, 'zone' 이벤트의 i …
	- 배열(S.enemies, S.shots, S.ev, choices, pts, lv …)은 1부터 세는 보통의 Lua 배열. sim.choose(i) 도 1부터.
	- JS 객체의 키 순서: 상수는 WEAPON_ORDER / PASSIVE_ORDER / FUSION_ORDER / ENEMY_ORDER / ZW_ORDER.
	  바뀌는 맵 S.weapons · S.passives · S.fus 의 "넣은 순서"는 S.wOrder · S.pOrder · S.fOrder, S.dmg 는 S.dmgOrder.
	  (규칙 계산은 순서에 기대지 않는다 — 순서 목록은 UI 와 저장용. recalc 때마다 맵에 맞춰 다시 맞춘다.)
	- host.end → host.finish (end 는 Lua 예약어).
	- JS 에서 undefined 인 채 `>0` 으로만 견주는 칸(e.intro, e.shT, e.rzT, e.board)은 0 으로 채워 둔다.
	  boss() 가 채우는 보스 전용 칸(e.t3, e.sayT, e.cc, e.pend, 김 팀장의 e.day·z·fan·row·stp·sq)은 그 전까지 NaN
	  (JS 에서도 undefined 로 셈하면 NaN — dbg.spawn 으로 보스를 바로 만들 때만 드러난다).
	- JS 의 참·거짓: 0 · '' · undefined 는 거짓 → 여기서는 `~= 0`, `~= ''`, truthy() 로 따로 견준다.
	- Math.hypot 은 V8 과 같은 식, `%`(실수) 는 math.fmod, Math.round / Math.sign 은 JS 규칙(-0 포함).
	- 난수를 여러 번 부르는 식은 JS 의 계산 순서대로 한 줄씩 풀어 썼다.
	- opts.rng: [0,1) 난수 함수 (기본 math.random).
	- 짜임새만 바꾼 곳 (결과는 같다): 정의 순서(spawn 을 boss 앞으로), update 안의 적 루프 · 겹침 풀기 · 하차 인파 탄막을
	  함수로 뺌(stepEnemies · separate · volley), 격자는 지난번에 채운 칸만 비움, exp(-7dt) 는 적마다가 아니라 한 번만 계산.
	- `--@unreachable-begin/end`: 원본에서도 닿지 않는 가지 (검사 도구가 "밟지 않아도 되는 줄"로 센다).
	  `--@@MATH-BEGIN/END`: 검사 도구가 견줌용 수학 함수로 바꿔 끼우는 한 줄. 둘 다 지우지 말 것.
]]

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local fmod = math.fmod
local PI = math.pi
local HUGE = math.huge
local NAN = 0 / 0
--@@MATH-BEGIN (tools/parity 는 이 한 줄만 바꿔 끼운 사본으로 "같은 수학 함수" 견줌을 한다)
local sin, cos, atan2, exp, pow = math.sin, math.cos, math.atan2, math.exp, math.pow
--@@MATH-END

-- Math.hypot(x, y): V8 과 같은 식 (큰 쪽으로 나눈 뒤 제곱합의 제곱근 × 큰 쪽)
local function hypot(x: number, y: number): number
	x = abs(x)
	y = abs(y)
	local m = if x > y then x else y
	if m == 0 then
		return 0
	end
	if m == HUGE then
		return HUGE
	end
	x /= m
	y /= m
	return sqrt(x * x + y * y) * m
end

-- Math.round: 반올림(.5 는 위로). -0.5 ~ -0 은 -0
local function round(x: number): number
	local f = floor(x)
	if x - f >= 0.5 then
		f += 1
	end
	if f == 0 and x < 0 then
		return -0
	end
	return f
end

-- Math.sign: 0 과 -0 은 그대로 돌려준다
local function sign(x: number): number
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return x
end

-- JS 의 참·거짓
local function truthy(v: any): boolean
	return v ~= nil and v ~= false and v ~= 0 and v ~= "" and v == v
end

-- JS 의 `v|0` (소수점 아래 버림, undefined → 0)
local function toInt(v: any): number
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return if v >= 0 then floor(v) else ceil(v)
end

-- 각도 차를 -π..π 로: ((x % TAU) + TAU + π) % TAU - π
local TAU = PI * 2
local function angd(x: number): number
	return fmod(fmod(x, TAU) + TAU + PI, TAU) - PI
end

local GAME_LEN, RAMP, LANE_GAP, LANE_H, TRAIN_LEN, TRAIN_SPD, WMAX, EVO, PMAX, MAX_W, MAX_P = 540, 600, 1000, 56, 1080, 1500, 6, 7, 5, 5, 5
local GATE_GAP, GATE_PER, GATE_HALF, GATE_TH, AISLE, DOOR_PER, DOOR_OPEN, ESC_W, ESC_PUSH = 420, 130, 28, 16, 80, 320, 9, 220, 58

-- 출근길, 장소 순서대로: 역삼역 앞 → 개찰구 → 승강장 → 열차 안 → 구로디지털단지역 승강장 → 에스컬레이터 → 회사 앞
local ZONES = {
	{ key = "street", kind = "street", name = "역삼역 앞", short = "역삼역 앞", at = 0, y0 = 500, song = 0, hazard = "bus", dens = .8, floor = { 198, 192, 182 }, amb = .13, tint = "40,28,8", line = "버스가 지나는 차도를 조심하세요" },
	{ key = "gates", kind = "gates", name = "개찰구", short = "개찰구", at = 40, y0 = 210, song = 1, dens = .72, floor = { 214, 212, 204 }, amb = .26, tint = "12,18,26", line = "개찰구 사이 틈으로만 지나갈 수 있습니다" },
	{ key = "platA", kind = "plat", name = "역삼역 승강장", short = "역삼 승강장", station = "역삼", at = 75, y0 = 500, song = 1, hazard = "train", dens = .96, floor = { 207, 203, 192 }, amb = .32, tint = "12,18,28", line = "선로에 경고가 뜨면 물러나세요" },
	{ key = "train", kind = "train", name = "열차 안", short = "열차 안", at = 110, y0 = 0, song = 2, dens = .5, floor = { 203, 206, 207 }, amb = .22, tint = "6,10,18", line = "좁은 통로입니다. 역마다 문이 열리고 인파가 탑니다" },
	{ key = "platB", kind = "plat", name = "구로디지털단지역 승강장", short = "구디 승강장", station = "구로디지털단지", at = 200, y0 = 500, song = 3, hazard = "train", floor = { 186, 198, 210 }, amb = .36, tint = "8,12,36", line = "내리는 인파를 뚫고 나가세요" },
	{ key = "esc", kind = "esc", name = "에스컬레이터", short = "에스컬레이터", at = 230, y0 = 0, song = 4, floor = { 176, 180, 184 }, amb = .4, tint = "10,10,24", line = "계단이 위아래로 밀어냅니다", dens = .8 },
	{ key = "office", kind = "office", name = "회사 앞", short = "회사 앞", at = 270, y0 = 0, song = 4, dens = .93, floor = { 214, 208, 198 }, amb = .13, tint = "44,24,6", line = "9시가 코앞입니다" },
}
local STOPS = { { name = "강남" }, { name = "교대" }, { name = "사당" }, { name = "신림" } }
local LAST_STOP = "구로디지털단지"
-- 장소 종류마다 나오는 적의 비중. ZW_ORDER 가 JS 객체의 키 순서
local ZW = {
	street = { pass = 10, flyer = .8, runner = 2, intern = 2, zomb = 2.5 },
	gates = { pass = 10, stud = 4, intern = 3, carrier = 2, uncle = 1.5 },
	plat = { pass = 10, zomb = 2.5, intern = 2.5, stud = 3, runner = 3, flyer = .7, uncle = 2, carrier = 1.5 },
	train = { pass = 10, uncle = 4, stud = 3, intern = 2.5, zomb = 2 },
	esc = { pass = 10, runner = 5, stud = 3, carrier = 3, intern = 2 },
	office = { pass = 10, intern = 4, runner = 3, flyer = 3, uncle = 3, carrier = 3, stud = 2 },
}
local ZW_ORDER = {
	street = { "pass", "flyer", "runner", "intern", "zomb" },
	gates = { "pass", "stud", "intern", "carrier", "uncle" },
	plat = { "pass", "zomb", "intern", "stud", "runner", "flyer", "uncle", "carrier" },
	train = { "pass", "uncle", "stud", "intern", "zomb" },
	esc = { "pass", "runner", "stud", "carrier", "intern" },
	office = { "pass", "intern", "runner", "flyer", "uncle", "carrier", "stud" },
}
-- 장소를 깨는 법: 인파를 버티면 진상이 나오고, 진상을 잡으면 통과. 열차는 정해진 시간만큼 탄다
local GATE = {
	street = { crowd = 36, boss = "flyboss" },
	gates = { crowd = 38, boss = "bagman" },
	platA = { crowd = 36, boss = "doorman" },
	train = { ride = 90, opt = "speaker" },
	platB = { crowd = 34, boss = "crowd" },
	esc = { crowd = 38, boss = "carrierboss" },
	office = { crowd = 30, boss = "lead" },
}
local ENRAGE_STEP = 20
-- 난이도 (승강장 전광판의 혼잡도 이름). JS 의 DIFFS[i] → DIFFS[i+1]
local DIFFS = {
	{ key = "easy", name = "여유", blurb = "일곱 장소를 끝까지 둘러보기 좋습니다", xp = .88, crowd = .52, foe = .58, boss = .55, enrage = 70, hp = 170, heal = 40, rerolls = 5, elite = 1.6, hazard = 1.4 },
	{ key = "normal", name = "보통", blurb = "도착은 할 만하지만 정시 출근은 빠듯합니다", xp = .75, crowd = .8, foe = .76, boss = .7, enrage = 50, hp = 120, heal = 28, rerolls = 4, elite = 1.25, hazard = 1 },
	{ key = "hard", name = "혼잡", blurb = "조합을 잘 맞춰야 도착합니다", xp = .7, crowd = 1, foe = .97, boss = .82, enrage = 45, hp = 100, heal = 20, rerolls = 3, elite = 1, hazard = 1 },
	{ key = "hell", name = "지옥철", blurb = "폭주가 빨리 오고 회복이 적습니다", xp = .66, crowd = 1.2, foe = 1.15, boss = 1.2, enrage = 32, hp = 100, heal = 10, rerolls = 2, elite = .75, hazard = .7 },
}
local function B(v: boolean): number
	return if v then 1 else 0
end
-- 무기. lv[n] = n레벨 설명(1부터), stat(l) = l레벨 수치. 키 순서는 WEAPON_ORDER
local WEAPONS = {
	card = {
		name = "교통카드", evoName = "법인카드", pair = "shoes",
		lv = { "가장 가까운 사람에게 카드를 던집니다. 두 명까지 꿰뚫습니다", "카드 +1장", "피해량 +5, 관통 +1", "카드 +1장", "카드 +1장, 던지는 속도 증가" },
		evoDesc = "한도 없는 카드 5장이 인파를 꿰뚫습니다",
		stat = function(l)
			if l >= 6 then
				return { n = 5, dmg = 21, cd = .62, pierce = 4 }
			end
			return { n = 1 + B(l >= 2) + B(l >= 4) + B(l >= 5), dmg = 11 + 5 * B(l >= 3), cd = if l >= 5 then .76 else .86, pierce = 2 + B(l >= 3) }
		end,
	},
	umbrella = {
		name = "장우산", evoName = "골프 우산", pair = "armor",
		lv = { "가까운 쪽을 우산으로 찌릅니다", "피해량 +8", "사거리 +25%, 등 뒤도 함께 찌릅니다", "피해량 +10", "공격 속도 +30%" },
		evoDesc = "검정과 금빛의 골프 우산으로 앞뒤 좌우 네 방향을 한꺼번에 세 번 찌릅니다. 세 번째는 길게 뻗어 일직선의 모두를 꿰뚫습니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 28, range = 150, half = .5, both = true, cd = 1.15, kb = 150, combo = true, fin = 58, finLen = 300, finW = 24 }
			end
			return { dmg = 22 + 8 * B(l >= 2) + 10 * B(l >= 4), range = 108 * (if l >= 3 then 1.25 else 1), half = .8, both = l >= 3, cd = if l >= 5 then .8 else 1.05, kb = 130 }
		end,
	},
	backpack = {
		name = "백팩 회전", evoName = "등산 배낭", pair = "snack",
		lv = { "백팩 2개가 몸 주위를 돌며 부딪힙니다", "백팩 +1개", "피해량 +6, 회전 반경과 속도 증가", "백팩 +1개", "백팩 +1개, 피해량 +6" },
		evoDesc = "묵직한 등산 배낭 6개가 넓게 돕니다",
		stat = function(l)
			if l >= 6 then
				return { n = 6, dmg = 38, radius = 108, spin = 4.8, size = 19 }
			end
			return { n = 2 + B(l >= 2) + B(l >= 4) + B(l >= 5), dmg = 22 + 6 * B(l >= 3) + 6 * B(l >= 5), radius = 76 * (if l >= 3 then 1.25 else 1), spin = 3.2 * (if l >= 3 then 1.3 else 1), size = 13 }
		end,
	},
	coffee = {
		name = "뜨거운 아메리카노", evoName = "사약 에스프레소", pair = "pods",
		lv = { "커피를 던져 뜨거운 웅덩이를 만듭니다", "웅덩이 크기 +25%", "웅덩이 +1개", "피해량 +4, 지속 시간 +1.5초", "웅덩이 +1개" },
		evoDesc = "쓰디쓴 웅덩이 4개가 넓게 퍼지고 발을 묶습니다",
		stat = function(l)
			if l >= 6 then
				return { n = 4, r = 88, tick = 14, dur = 5, cd = 2.8, slow = .5 }
			end
			return { n = 1 + B(l >= 3) + B(l >= 5), r = 54 * (if l >= 2 then 1.25 else 1), tick = 5.5 + 3 * B(l >= 4), dur = 3 + 1.5 * B(l >= 4), cd = 2.4, slow = .3 }
		end,
	},
	anc = {
		name = "노이즈캔슬링", evoName = "풀볼륨 스피커", pair = "payday",
		lv = { "주변 사람을 밀어내는 파동을 냅니다", "피해량 +6", "범위 +30%", "발동 속도 +25%", "피해량 +8, 범위 +25%" },
		evoDesc = "쩌렁쩌렁한 음파가 훨씬 넓게, 자주 터집니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 46, r = 225, cd = 1.3, kb = 260 }
			end
			return { dmg = 19 + 6 * B(l >= 2) + 8 * B(l >= 5), r = 120 * (1 + .3 * B(l >= 3) + .25 * B(l >= 5)), cd = 1.8 * (if l >= 4 then .75 else 1), kb = 170 }
		end,
	},
	shout = {
		name = '"내릴게요!"', evoName = '"저 내려요!!!"', pair = "tumbler",
		lv = { "화면의 모두를 밀쳐내고 잠시 멈춰 세웁니다", "재사용 대기 2초 감소", "피해량 +9", "재사용 대기 2초 감소", "피해량 +9, 멈춰 세우는 시간 +0.5초" },
		evoDesc = "6.5초마다 터지는 절규. 피해량이 크게 오릅니다",
		stat = function(l)
			if l >= 6 then
				return { cd = 6.5, dmg = 55, stun = 1.6 }
			end
			return { cd = 13 - 2 * B(l >= 2) - 2 * B(l >= 4), dmg = 16 + 9 * B(l >= 3) + 9 * B(l >= 5), stun = 1 + .5 * B(l >= 5) }
		end,
	},
	battery = {
		name = "보조배터리", evoName = "고속 충전기", pair = "focus",
		lv = { "전기가 튀어 가까운 4명에게 번집니다", "피해량 +6", "번지는 수 +2", "발동 속도 +20%", "피해량 +8, 번지는 수 +3" },
		evoDesc = "12명에게 번지는 고압 전류. 맞으면 잠깐 굳습니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 42, chain = 12, cd = .75, stun = .25 }
			end
			return { dmg = 16 + 6 * B(l >= 2) + 8 * B(l >= 5), chain = 4 + 2 * B(l >= 3) + 3 * B(l >= 5), cd = 1.5 * (if l >= 4 then .8 else 1), stun = 0 }
		end,
	},
	hotpack = {
		name = "핫팩", evoName = "찜질방", pair = "vitamin",
		lv = { "몸 주변을 뜨겁게 달궈 닿는 사람을 지집니다", "범위 +20%", "피해량 +3", "범위 +20%", "피해량 +4, 더 자주 지집니다" },
		evoDesc = "넓은 열기가 주변을 태우고 발걸음을 늦춥니다",
		stat = function(l)
			if l >= 6 then
				return { r = 160, dmg = 20, tick = .3, slow = .25 }
			end
			return { r = 86 * (1 + .2 * B(l >= 2) + .2 * B(l >= 4)), dmg = 13 + 3 * B(l >= 3) + 4 * B(l >= 5), tick = if l >= 5 then .33 else .45, slow = 0 }
		end,
	},
	scooter = {
		name = "킥보드 호출", evoName = "전동 킥보드 폭주", pair = "mask",
		lv = { "킥보드가 가까운 적 쪽으로 일직선으로 질주하며 길 위의 모두를 칩니다", "피해량 +10", "차체 폭 +40%", "킥보드 +1대 (반대 방향)", "피해량 +12, 호출 속도 +20%" },
		evoDesc = "킥보드 3대가 부채꼴로 더 멀리 폭주합니다",
		stat = function(l)
			if l >= 6 then
				return { n = 3, dmg = 58, w = 30, cd = 2.3, max = 720 }
			end
			return { n = 1 + B(l >= 4), dmg = 32 + 10 * B(l >= 2) + 12 * B(l >= 5), w = 24 * (if l >= 3 then 1.4 else 1), cd = 2.6 * (if l >= 5 then .8 else 1), max = 560 }
		end,
	},
	selfie = {
		name = "셀카봉", evoName = "라이브 방송", pair = "badge",
		lv = { "셀카봉이 시곗바늘처럼 돌며 닿는 사람을 칩니다", "피해량 +5", "길이 +30%", "셀카봉 +1개", "피해량 +6, 회전 속도 +30%" },
		evoDesc = "셀카봉 3개가 길게 돌고, 플래시에 맞으면 잠깐 굳습니다",
		stat = function(l)
			if l >= 6 then
				return { n = 3, dmg = 28, len = 195, spin = 4.8, stun = .15 }
			end
			return { n = 1 + B(l >= 4), dmg = 14 + 5 * B(l >= 2) + 6 * B(l >= 5), len = 122 * (if l >= 3 then 1.3 else 1), spin = 3.2 * (if l >= 5 then 1.3 else 1), stun = 0 }
		end,
	},
	handle = {
		name = "손잡이", evoName = "순환선", pair = "energy",
		lv = { "손잡이가 날아갔다 돌아오며 지나는 길의 모두를 칩니다", "피해량 +6", "손잡이 +1개", "피해량 +7, 사거리 +30%", "손잡이 +1개" },
		evoDesc = "손잡이 4개가 더 멀리, 더 세게 돌아옵니다",
		stat = function(l)
			if l >= 6 then
				return { n = 4, dmg = 36, range = 1.5, size = 16, cd = 1.3 }
			end
			return { n = 1 + B(l >= 3) + B(l >= 5), dmg = 22 + 6 * B(l >= 2) + 7 * B(l >= 4), range = 1 + .3 * B(l >= 4), size = 12, cd = 1.5 }
		end,
	},
	alarm = {
		name = "알람 시계", evoName = "스누즈 지옥", pair = "overtime",
		lv = { "알람 시계를 던집니다. 잠시 뒤 울리며 주변을 터뜨리고 멈춰 세웁니다", "피해량 +10", "폭발 범위 +30%", "시계 +1개", "피해량 +12" },
		evoDesc = "시계 3개가 각각 세 번씩 울립니다",
		stat = function(l)
			if l >= 6 then
				return { n = 3, dmg = 52, r = 108, cd = 2.4, stun = .6, rings = 3 }
			end
			return { n = 1 + B(l >= 4), dmg = 31 + 10 * B(l >= 2) + 12 * B(l >= 5), r = 72 * (if l >= 3 then 1.3 else 1), cd = 2.6, stun = .4, rings = 1 }
		end,
	},
	tie = {
		name = "넥타이 채찍", evoName = "불금 넥타이", pair = "report",
		lv = { "가장 가까운 사람 쪽으로 넥타이를 채찍처럼 내리칩니다. 끝자락에 맞으면 40% 더 아픕니다", "피해량 +7", "등 뒤쪽도 함께 후려칩니다", "길이 +30%", "피해량 +9, 공격 속도 +20%" },
		evoDesc = "앞뒤로 두 번 후려친 다음, 세 번째에는 머리 위로 크게 한 바퀴 돌려 주변을 쓸어 버립니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 46, len = 178, w = 38, both = true, cd = .62, kb = 200 }
			end
			return { dmg = 28 + 7 * B(l >= 2) + 9 * B(l >= 5), len = 130 * (if l >= 4 then 1.3 else 1), w = 28, both = l >= 3, cd = .9 * (if l >= 5 then .8 else 1), kb = 110 }
		end,
	},
	laptop = {
		name = "노트북", evoName = "듀얼 모니터", pair = "will",
		lv = { "떠 있는 노트북이 블루라이트 광선을 쏘며 부채꼴로 훑습니다. 닿는 동안 계속 피해를 줍니다", "피해량 +9", "광선 굵기 +50%", "발사 속도 +20%", "피해량 +11, 반대쪽으로도 쏩니다" },
		evoDesc = "모니터 네 대가 십자 광선을 쏘며 천천히 돌아갑니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 58, w = 30, n = 4, cd = 1.8, len = 640 }
			end
			return { dmg = 31 + 9 * B(l >= 2) + 11 * B(l >= 5), w = 18 * (if l >= 3 then 1.5 else 1), n = 1 + B(l >= 5), cd = 2 * (if l >= 4 then .8 else 1), len = 520 }
		end,
	},
	gum = {
		name = "씹던 껌", evoName = "풍선껌 지뢰밭", pair = "lotto",
		lv = { "지나간 자리에 껌을 뱉습니다. 밟은 사람은 끈적하게 느려지고 피해를 받습니다", "피해량 +3", "껌 크기 +30%", "더 자주 뱉습니다", "피해량 +4, 지속 시간 +2초" },
		evoDesc = "큼직한 풍선껌이 발을 거의 묶어 버리고 훨씬 아프게 터집니다",
		stat = function(l)
			if l >= 6 then
				return { r = 76, tick = 14, dur = 6, cd = 1, slow = .7 }
			end
			return { r = 40 * (if l >= 3 then 1.3 else 1), tick = 7 + 3 * B(l >= 2) + 3 * B(l >= 5), dur = 4 + 2 * B(l >= 5), cd = 1.6 * (if l >= 4 then .7 else 1), slow = .45 }
		end,
	},
	shoulder = {
		name = "어깨빵", evoName = "출근 돌파", pair = "gym",
		lv = { "몸에 부딪힌 사람을 어깨로 받아칩니다. 대시가 끝나는 자리에서는 주변을 훨씬 세게 들이받습니다", "피해량 +9", "대시 충격 범위 +30%", "대시하며 스친 사람도 칩니다. 받아치는 간격이 짧아집니다", "피해량 +11" },
		evoDesc = "부딪히는 족족 튕겨 내고, 대시가 지나간 길과 도착 지점이 통째로 터집니다. 맞은 사람은 잠깐 굳습니다",
		stat = function(l)
			if l >= 6 then
				return { dmg = 64, mul = 2.8, r = 160, cdE = .35, trail = true, stun = .5, kb = 320 }
			end
			return { dmg = 28 + 9 * B(l >= 2) + 11 * B(l >= 5), mul = 2.6, r = 104 * (if l >= 3 then 1.3 else 1), cdE = if l >= 4 then .45 else .65, trail = l >= 4, stun = 0, kb = 250 }
		end,
	},
}
local WEAPON_ORDER = { "card", "umbrella", "backpack", "coffee", "anc", "shout", "battery", "hotpack", "scooter", "selfie", "handle", "alarm", "tie", "laptop", "gum", "shoulder" }
local PASSIVES = {
	shoes = { name = "운동화", desc = "이동 속도 +10%" },
	will = { name = "기계식 키보드", desc = "모든 피해량 +15%" },
	pods = { name = "샷 추가", desc = "공격 대기 시간 9% 감소" },
	tumbler = { name = "목캔디", desc = "공격 범위 +12%" },
	gym = { name = "헬스 회원권", desc = "최대 멘탈 +25, 초당 회복 +0.3" },
	badge = { name = "삼각대", desc = "떨어진 것을 줍는 범위 +40%" },
	armor = { name = "우비", desc = "받는 피해 9% 감소" },
	payday = { name = "플레이리스트", desc = "얻는 경험치 +10%" },
	energy = { name = "환승 요령", desc = "대시 대기 시간 15% 감소" },
	focus = { name = "고속 충전 케이블", desc = "치명타 확률 +6%" },
	lotto = { name = "껌 뽑기 기계", desc = "아이템이 떨어질 확률 +50%" },
	mask = { name = "헬멧", desc = "맞은 뒤 무적 시간 +0.12초" },
	report = { name = "보고서", desc = "진상과 진상 승객에게 주는 피해 +12%" },
	overtime = { name = "모닝콜", desc = "멘탈이 절반 이하일 때 피해량 +18%" },
	vitamin = { name = "목도리", desc = "초당 회복 +0.5" },
	snack = { name = "간식 보따리", desc = "레벨이 오를 때마다 멘탈 4 회복" },
}
local PASSIVE_ORDER = { "shoes", "will", "pods", "tumbler", "gym", "badge", "armor", "payday", "energy", "focus", "lotto", "mask", "report", "overtime", "vitamin", "snack" }
local DOOR_RATE = { 8, 11 }
local MACE = { strap = 85, dmg = 218, slam = 411, spin = 5 }
local BOMB = { n = 4, cd = 1.5, fuse = 1.3, dmg = 135 }
local GUARD = { push = 340, r = 59, half = 1.05, bash = 48, dmg = 79, counter = 108, len = 215, cd = .35, auto = .7 }
local W_SCALE, XP_SCALE, SPIN_R = .9, .9, 115
local PHASES = { "아침 인사", "업무 지시", "잔소리", "긴급 회의", "불호령" }
local DAY_LINE = { "회사 앞에서 하필 팀장님을 만났습니다", "서류와 지시가 쏟아집니다", "잔소리가 발밑에 깔립니다", "팀원들을 불러 모읍니다", "9시가 코앞입니다. 전부 빨라집니다" }
local TALK = {
	flyboss = { "전단지 받아 가세요~", "헬스장 오픈했어요!", "한 장만요, 한 장만!", "필라테스 첫 달 무료!" },
	bagman = { "(음악 듣는 중)", "뒤에 뭐 있어요?", "아, 좁네..." },
	doorman = { "저 다음 역에서 내려요", "안쪽은 답답해서요", "여기가 내 자리야" },
	speaker = { "이 노래 좋지 않아요?", "볼륨 좀 더 올릴까", "쿵짝 쿵짝~" },
	crowd = { "내립니다, 내려요!", "밀지 마세요!", "먼저 내리고 타요!" },
	carrierboss = { "공항철도가 어디예요?", "캐리어 좀 지나갈게요~", "어머, 죄송~" },
	-- lead[day+1] = 그 단계의 대사들
	lead = { { "좋은 아침~", "주말 잘 쉬었나?" }, { "이것 좀 오늘까지 부탁해", "메일 확인했나?" }, { "내가 자네 연차 때는 말이야", "요즘 친구들은 말이야..." }, { "9시 회의 있는 거 알지?", "전원 회의실로!" }, { "지금 몇 시인 줄 아나!", "자네, 지각이야!" } },
}
local RAGE_TALK = { flyboss = "안 받으면 못 지나가요!", bagman = "아, 왜 밀어요!", doorman = "안 비킨다니까!", speaker = "시끄럽다니, 뭐가!", crowd = "비켜요, 비켜!", carrierboss = "비행기 놓친단 말이에요!", lead = "자네 지금 나 무시하나!" }
-- 6레벨 = 5레벨 수치에 피해량 +18%, 7레벨(EVO) = 진화 수치
for _, k in ipairs(WEAPON_ORDER) do
	local w = WEAPONS[k]
	local f = w.stat
	table.insert(w.lv, "피해량 +18%")
	w.stat = function(l)
		if l >= EVO then
			return f(6)
		end
		if l == 6 then
			local o = f(5)
			if o.dmg and o.dmg ~= 0 then
				o.dmg *= 1.18
			end
			if o.tick and o.tick ~= 0 and o.tick > 1 then
				o.tick *= 1.18
			end
			return o
		end
		return f(l)
	end
end
-- 히든 조합: 서로 짝이 맞는 진화 무기 둘이 한 칸으로 합쳐진다
local FUSIONS = {
	remote = { name = "재택근무", a = "laptop", b = "battery", desc = "모니터 네 대가 쉬지 않고 돌아가며 노란 광선을 쏩니다. 광선에 닿은 사람에게서 번개가 터져 옆 사람들로 줄줄이 번집니다. 두 무기의 피해량이 30% 오릅니다" },
	bulldozer = { name = "배낭 철퇴", a = "backpack", b = "shoulder", desc = "끈에 매단 거대한 배낭 하나를 해머던지기처럼 크게 휘두릅니다. 느리지만 한 방이 세고 맞은 사람은 잠깐 굳습니다. 대시가 끝나면 배낭을 앞에 내려찍어 넓게 날려 버립니다" },
	gentleman = { name = "풀정장 신사", a = "umbrella", b = "tie", desc = "펼친 우산이 걷는 방향 앞을 막아서서 날아오는 것을 튕겨 내고, 닿는 사람을 앞으로 밀어냅니다. 막을 때마다 넥타이가 크게 한 바퀴 돌아 반격합니다" },
	routine = { name = "커피 시한폭탄", a = "coffee", b = "alarm", desc = "사람들 사이에 커피잔을 내려놓습니다. 컵 위의 시곗바늘이 한 바퀴 돌면 알람과 함께 두 번 연달아 터져 주변을 굳히고 진한 커피를 바닥에 쏟습니다" },
	freepass = { name = "프리패스", a = "card", b = "handle", desc = "카드와 손잡이가 하나의 순환선이 됩니다. 카드는 사람에서 사람으로 다섯 번까지 갈아타고, 카드가 꽂힌 커다란 손잡이 고리가 돌아올 때마다 카드 여섯 장이 더 나갑니다. 두 무기의 피해량이 50% 오릅니다" },
}
local FUSION_ORDER = { "remote", "bulldozer", "gentleman", "routine", "freepass" }
local PAIR_OF = {}
for _, k in ipairs(WEAPON_ORDER) do
	PAIR_OF[WEAPONS[k].pair] = k
end
local ENEMIES = {
	pass = { name = "승객", hp = 10, spd = 54, dmg = 8, r = 11, xp = 1 },
	zomb = { name = "스마트폰 좀비", hp = 14, spd = 90, dmg = 9, r = 11, xp = 1 },
	intern = { name = "아아 든 인턴", hp = 20, spd = 76, dmg = 8, r = 11, xp = 2 },
	stud = { name = "백팩 학생", hp = 36, spd = 62, dmg = 10, r = 12, xp = 3, kbRes = .5 },
	runner = { name = "뛰는 승객", hp = 28, spd = 58, dmg = 14, r = 11, xp = 3 },
	flyer = { name = "전단지 알바", hp = 38, spd = 72, dmg = 8, r = 11, xp = 4 },
	uncle = { name = "쩍벌 아저씨", hp = 95, spd = 38, dmg = 15, r = 18, xp = 6, kbRes = .7 },
	carrier = { name = "캐리어 여행객", hp = 160, spd = 44, dmg = 18, r = 16, xp = 9, kbRes = .85 },
	flyboss = { name = "진상 전단지 알바", boss = true, hp = 165, spd = 56, dmg = 9, r = 17, xp = 40, spr = "flyer", sc = 1.7 },
	doorman = { name = "문지기", boss = true, hp = 2600, spd = 26, dmg = 20, r = 30, xp = 70, spr = "uncle", sc = 1.9 },
	carrierboss = { name = "진상 캐리어 여행객", boss = true, hp = 4500, spd = 54, dmg = 22, r = 27, xp = 120, spr = "carrier", sc = 1.8 },
	bagman = { name = "백팩 빌런", boss = true, hp = 780, spd = 66, dmg = 16, r = 26, xp = 60 },
	crowd = { name = "하차 인파", boss = true, hp = 3600, spd = 46, dmg = 22, r = 40, xp = 110 },
	speaker = { name = "스피커 빌런", boss = true, hp = 2600, spd = 64, dmg = 20, r = 27, xp = 170 },
	lead = { name = "김 팀장", boss = true, hp = 3500, spd = 54, dmg = 26, r = 30, xp = 260, spr = "uncle", sc = 2 },
}
local ENEMY_ORDER = { "pass", "zomb", "intern", "stud", "runner", "flyer", "uncle", "carrier", "flyboss", "doorman", "carrierboss", "bagman", "crowd", "speaker", "lead" }

local function xpNeed(l: number): number
	local k = l - 1
	return floor((if k <= 20 then 4 + 2.3 * k + .085 * k * k else 84 * pow(1.16, k - 20)) * 1.22) + 1
end
local function clockText(t: number): string
	local m = floor(t / (GAME_LEN / 60))
	local h = 8 + floor(m / 60)
	local mm = fmod(m, 60) + 0
	return (if h < 10 then "0" else "") .. h .. ":" .. (if mm < 10 then "0" else "") .. mm
end

local BOSS_LINE = { flyboss = "전단지를 한 뭉치씩 뿌립니다", doorman = "출입문 앞에서 절대 안 비킵니다", carrierboss = "캐리어로 길을 통째로 막습니다", bagman = "가방을 뒤로 멘 채 돌아섭니다", crowd = "내리는 사람들이 한 덩어리로 밀려옵니다", speaker = "이어폰 없이 최대 볼륨", lead = DAY_LINE[1] }
local ZK = { 0, .13, .26, .39, .52, .64, .76 }
local FLY_FAN3, FLY_FAN2 = { -.2, 0, .2 }, { -.14, .14 }
local CELL, MAXR = 48, 60

-- 맵 얕은 복사 (Object.assign({}, src))
local function copyMap(src: any): any
	local o = {}
	if type(src) == "table" then
		for k, v in src do
			o[k] = v
		end
	end
	return o
end
-- 맵의 키 수 (Object.keys(o).length)
local function owned(o: any): number
	local n = 0
	for _ in o do
		n += 1
	end
	return n
end
-- 순서 목록 list 를 맵 map 에 맞춘다: 아직 있는 키는 제 순서대로, 새 키는 canon 순서로 뒤에 붙인다
local function syncList(list: { any }, map: any, canon: { any }?)
	local seen = {}
	local n = 0
	for i = 1, #list do
		local k = list[i]
		if map[k] ~= nil and not seen[k] then
			seen[k] = true
			n += 1
			list[n] = k
		end
	end
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
	if canon then
		for _, k in ipairs(canon) do
			if map[k] ~= nil and not seen[k] then
				seen[k] = true
				n += 1
				list[n] = k
			end
		end
	end
	local extra = nil
	for k in map do
		if not seen[k] then
			extra = extra or {}
			table.insert(extra, k)
		end
	end
	if extra then
		table.sort(extra, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in ipairs(extra) do
			n += 1
			list[n] = k
		end
	end
end

local Sim = {}

-- createSim(host, opts)
-- host = { sfx(name, x, arg), banner(a, b, kind), shake(a), levelUp(choices, pickMode), finish(won) }
-- opts = { diff, restore, build, demo, autoPick(choices, S), xpMul, botRange, rng }
function Sim.create(host: any, opts: any)
	opts = opts or {}
	local R: () -> number = opts.rng or math.random
	local rs = opts.restore
	local di
	if rs and rs.diff ~= nil then
		di = toInt(rs.diff)
	elseif opts.diff == nil then
		di = 2
	else
		di = toInt(opts.diff)
	end
	di = max(0, min(3, di))
	local D = DIFFS[di + 1]
	local S = {
		diff = di, t = 0, state = "run", kills = 0, delay = 0, zone = 0, zk = "street", song = 0, zt = 0, phase = "crowd",
		rage = 0, rageT = 0, clearT = 0, gate = nil :: any, started = false, late = false, optDone = false, stopIdx = 0,
		doorT = 0, doorAcc = 0, pvx = 0, side = 1, spawnX = 540, seen = {}, pending = 0, pickMode = "level", buildVer = 1,
		fus = {}, fsrc = {}, rerolls = D.rerolls,
		p = { x = 0, y = LANE_GAP / 2, r = 11, hp = 100, maxhp = 100, inv = 0, fx = 1, fy = 0, level = 1, xp = 0, moving = false, anim = 0, dashT = 0, dashCd = 0, ddx = 1, ddy = 0, slow = 0 },
		weapons = {}, passives = {}, wt = {}, M = nil :: any,
		enemies = {}, shots = {}, puddles = {}, lobs = {}, bullets = {}, beans = {}, items = {}, zones = {}, slicks = {}, waves = {},
		riders = {}, rangs = {}, mines = {}, beams = {}, selfA = 0, ev = {},
		spawnAcc = 0, nextRow = 25, nextElite = 35, evIdx = 0, bosses = {}, boss = nil :: any, orbA = 0, nextId = 1, dmg = {}, taken = 0,
		takenBy = {}, dashes = 0, input = { x = 0, y = 0 }, choices = nil :: any, spawnR = 600,
		train = nil :: any, trainT = 40, trainSeen = false, eliteSeen = false, rush = 1, auraT = 0,
		-- Lua 쪽에만 있는 것: 넣은 순서 목록 (JS 객체의 키 순서)
		wOrder = {}, pOrder = {}, fOrder = {}, dmgOrder = {},
	} :: any
	local p = S.p
	local function ev(o)
		local E = S.ev
		if #E < 400 then
			E[#E + 1] = o
		end
	end
	if rs and truthy(rs.weapons) then
		local r = rs
		S.t = if truthy(r.t) then r.t else 0
		S.zone = max(0, min(#ZONES - 1, toInt(r.zone)))
		S.kills = if truthy(r.kills) then r.kills else 0
		S.weapons = copyMap(r.weapons)
		S.passives = copyMap(r.passives)
		p.level = if truthy(r.level) then r.level else 1
		p.xp = if truthy(r.xp) then r.xp else 0
		S.dmg = copyMap(r.dmg)
		S.rerolls = toInt(r.rerolls)
		S.fus = copyMap(r.fus)
		S.fsrc = copyMap(r.fsrc)
		-- 순서 목록(serialize 가 같이 내보낸다). 없으면 상수 순서
		S.wOrder = if type(r.wOrder) == "table" then table.clone(r.wOrder) else {}
		S.pOrder = if type(r.pOrder) == "table" then table.clone(r.pOrder) else {}
		S.fOrder = if type(r.fOrder) == "table" then table.clone(r.fOrder) else {}
		S.dmgOrder = if type(r.dmgOrder) == "table" then table.clone(r.dmgOrder) else {}
	elseif opts.build then
		local b = opts.build
		S.weapons = copyMap(b.weapons)
		S.passives = copyMap(b.passives)
		S.wOrder = if type(b.wOrder) == "table" then table.clone(b.wOrder) else {}
		S.pOrder = if type(b.pOrder) == "table" then table.clone(b.pOrder) else {}
	else
		S.weapons.card = 1
		S.passives.shoes = 1
	end
	local function syncOrder()
		syncList(S.wOrder, S.weapons, WEAPON_ORDER)
		syncList(S.pOrder, S.passives, PASSIVE_ORDER)
		syncList(S.fOrder, S.fus, FUSION_ORDER)
		syncList(S.dmgOrder, S.dmg, nil)
	end
	local function recalc()
		local P = S.passives
		S.M = {
			might = 1 + .15 * (P.will or 0),
			cd = 1 - .09 * (P.pods or 0),
			area = 1 + .12 * (P.tumbler or 0),
			speed = 1 + .1 * (P.shoes or 0),
			pick = 1 + .4 * (P.badge or 0),
			regen = .3 * (P.gym or 0) + .5 * (P.vitamin or 0),
			bossDmg = 1 + .12 * (P.report or 0),
			low = 1 + .18 * (P.overtime or 0),
			lvHeal = 4 * (P.snack or 0),
			armor = 1 - .09 * (P.armor or 0),
			xp = 1 + .1 * (P.payday or 0),
			dashCd = 2.4 * (1 - .15 * (P.energy or 0)),
			crit = .08 + .06 * (P.focus or 0),
			luck = 1 + .5 * (P.lotto or 0),
			invT = .45 + .12 * (P.mask or 0),
		}
		p.maxhp = D.hp + 25 * (P.gym or 0)
		S.buildVer += 1
		syncOrder()
	end
	recalc()
	p.hp = if rs and type(rs.hp) == "number" and rs.hp > 0 then min(rs.hp, p.maxhp) else p.maxhp

	-- 피해량 기록 (S.dmg[src] = (S.dmg[src]||0) + d)
	local function addDmg(src: string, d: number)
		local dm = S.dmg
		local cur = dm[src]
		if cur == nil then
			table.insert(S.dmgOrder, src)
			cur = 0
		end
		dm[src] = cur + d
	end

	---------------- 장소 ----------------
	local function q(): number
		return min(1.3, ZK[S.zone + 1] + min(.11, S.zt / 700))
	end
	local function say(e, txt)
		if e and not e.dead and txt and txt ~= "" then
			ev({ k = "say", id = e.id, txt = txt })
		end
	end
	local function hpMul(): number
		local k = q()
		return 1 + k * 2.4 + k * k * 6
	end
	local function pickType(t: number): string
		local zk = S.zk
		local w, keys = ZW[zk], ZW_ORDER[zk]
		local f = min(1.3, .35 + t / 300)
		local tot = 0
		for i = 1, #keys do
			local k = keys[i]
			tot += if k == "pass" then w[k] else w[k] * f
		end
		local r = R() * tot
		for i = 1, #keys do
			local k = keys[i]
			r -= if k == "pass" then w[k] else w[k] * f
			if r <= 0 then
				return k
			end
		end
		--@unreachable-begin 반올림 오차로 r 이 끝까지 양수로 남을 때만 온다
		return "pass"
		--@unreachable-end
	end
	-- (원본에서는 boss · ring 뒤에 있다. 먼저 정의해야 해서 앞으로 옮겼다)
	local function spawn(ty: string, x: number, y: number)
		local d = ENEMIES[ty]
		local k = q()
		local isBoss = d.boss == true
		local m = if isBoss then D.boss else hpMul() * D.foe
		local id = S.nextId
		S.nextId = id + 1
		-- 난수 순서: spd → anim → tm → ang → seed
		local spd = d.spd * (if isBoss then 1 else (.9 + R() * .2) * (1 + k * .38))
		local dmg = d.dmg * (if isBoss then (D.foe + 1) / 2 else (1 + k * 1.2) * D.foe)
		local anim = R() * 10
		local tm = if isBoss then 2.5 else 1 + R() * 2
		local ang = R() * TAU
		local seed = floor(R() * 1000)
		local e = {
			id = id, type = ty, def = d, x = x, y = y, hp = d.hp * m, maxhp = d.hp * m, r = d.r, sc = 1,
			spd = spd, dmg = dmg, xp = d.xp,
			kx = 0, ky = 0, stun = 0, slow = 0, slowAmt = 0, flash = 0, bpT = 0, sfT = 0, anim = anim, vx = 0, vy = 0, st = 0,
			tm = tm, t2 = if isBoss then 6 else 0, acc = 0, ang = ang,
			dx = 1, dy = 0, seed = seed, dead = false, boss = isBoss, elite = false, mv = true,
			-- JS 에서는 undefined 로 시작하는 칸
			intro = 0, shT = 0, rzT = 0, board = 0,
		}
		if isBoss then
			e.t3 = NAN
			e.sayT = NAN
			e.cc = NAN
			e.pend = NAN
			if ty == "lead" then
				e.day = NAN
				e.z = NAN
				e.fan = NAN
				e.row = NAN
				e.stp = NAN
				e.sq = NAN
			end
		end
		if ty == "zomb" then
			local a
			if S.zk == "train" then
				a = if x < p.x then 0 else PI
			else
				a = atan2(p.y - y, p.x - x) + (R() - .5) * .3
			end
			e.vx = cos(a) * e.spd
			e.vy = sin(a) * e.spd
		end
		table.insert(S.enemies, e)
		return e
	end
	-- 돌려주는 값: x, y (원본은 [x, y])
	local function spawnPos(k: number?): (number, number)
		local kk = if k and k ~= 0 then k else 1
		if S.zk == "train" then
			local sd = if R() < .78 then S.side else -S.side
			local x = p.x + sd * (S.spawnX * kk + R() * 70)
			local y = (R() * 2 - 1) * (AISLE - 14)
			return x, y
		end
		local a = R() * TAU
		return p.x + cos(a) * S.spawnR * kk, p.y + sin(a) * S.spawnR * kk
	end
	local function enterZone(i: number)
		local Z = ZONES[i + 1]
		local G = GATE[Z.key]
		S.zone = i
		S.zk = Z.kind
		S.song = Z.song
		local left = ""
		table.clear(S.beams)
		S.zt = 0
		S.phase = if G.ride then "ride" else "crowd"
		S.rage = 0
		S.gate = nil
		S.stopIdx = 0
		S.optDone = false
		if i > 0 and S.started then
			for _, e in ipairs(S.bosses) do
				if not e.dead then
					left = e.def.name
				end
			end
			table.clear(S.bosses)
			S.boss = nil
			local sx, sy = -p.x, Z.y0 - p.y
			for _, b in ipairs(S.beans) do
				b.x += sx
				b.y += sy
				b.att = true
			end
			for _, it in ipairs(S.items) do
				local a = R() * TAU
				local d = 30 + R() * 40
				it.x = cos(a) * d
				it.y = Z.y0 + sin(a) * (if Z.kind == "train" then d * .6 else d)
			end
			table.clear(S.enemies)
			table.clear(S.shots)
			table.clear(S.puddles)
			table.clear(S.lobs)
			table.clear(S.bullets)
			table.clear(S.zones)
			table.clear(S.slicks)
			table.clear(S.waves)
			table.clear(S.riders)
			table.clear(S.rangs)
			table.clear(S.mines)
			S.train = nil
			S.delay = 0
			S.doorT = 0
			S.pvx = 0
			p.x = 0
			p.y = Z.y0
			p.dashT = 0
			p.inv = max(p.inv, 1.3)
			if p.hp < p.maxhp then
				p.hp = min(p.maxhp, p.hp + D.heal)
				ev({ k = "heal", v = D.heal })
			end
			ev({ k = "zone", i = i })
			host.sfx("zone")
		end
		S.started = true
		S.trainT = if Z.hazard then (if i == 0 then 13 else 6) else 1e9
		S.nextRow = S.t + 10
		S.nextElite = S.t + (if i == 0 then 30 else 14)
		host.banner(Z.name, if left ~= "" then left .. "을 따돌렸습니다. " .. Z.line else Z.line, "station")
	end
	local function boss(ty: string)
		local ba = R() * TAU
		local inTrain = S.zk == "train"
		local bd = if inTrain then 300 else 260
		local bx
		if inTrain then
			bx = p.x + (if R() < .5 then -1 else 1) * bd
		else
			bx = p.x + cos(ba) * bd
		end
		local by = if inTrain then 0 else p.y + sin(ba) * bd * .8
		local e = spawn(ty, bx, by)
		e.intro = 1.3
		ev({ k = "bossin", x = bx, y = by })
		if ty == "speaker" then
			e.tm = 2.6
			e.t2 = 0
			e.acc = .6
		end
		if ty == "lead" then
			e.day = 0
			e.label = "김 팀장 · " .. PHASES[1]
			e.z = 2
			e.fan = 1.5
			e.row = 2
			e.t2 = 3
			e.stp = 4
			e.sq = 0
		end
		e.t3 = 5
		e.sayT = 2.2
		e.cc = 0
		e.pend = 0
		if ty == GATE[ZONES[S.zone + 1].key].boss then
			S.gate = e
		end
		table.insert(S.bosses, e)
		S.boss = e
		host.banner(e.def.name, BOSS_LINE[ty], "boss")
		host.sfx("boss")
	end
	local function ring(n: number, quiet: boolean?)
		local rr, t = S.spawnR * .9, S.t
		for i = 0, n - 1 do
			local ty = if t > 400 and i % 4 == 0 then "uncle" elseif t > 260 and i % 3 == 0 then "stud" else "pass"
			if S.zk == "train" then
				local sd = if i % 2 == 1 then 1 else -1
				spawn(ty, p.x + sd * (S.spawnX + (i // 2) * 16), (((i * 37) % 100) / 50 - 1) * (AISLE - 14))
			else
				local a = i / n * TAU
				spawn(ty, p.x + cos(a) * rr, p.y + sin(a) * rr)
			end
		end
		--@unreachable-begin 원본에서도 ring() 은 늘 quiet=true 로만 불린다
		if not quiet then
			host.banner("인파에 둘러싸였습니다", if S.zk == "train" then "앞뒤에서 밀려옵니다" else "틈을 뚫고 나가세요", "warn")
			host.sfx("warn")
		end
		--@unreachable-end
	end
	local function spawnElite()
		local ty = pickType(S.t)
		if ty == "zomb" then
			ty = "pass"
		end
		local qx, qy = spawnPos()
		local e = spawn(ty, qx, qy)
		e.elite = true
		e.maxhp = max(140, min(e.maxhp, 30 * hpMul() * D.foe) * 11)
		e.hp = e.maxhp
		e.r *= 1.45
		e.sc = 1.45
		e.dmg *= 1.5
		e.spd *= 1.1
		e.xp = e.def.xp * 10
		if not S.eliteSeen then
			S.eliteSeen = true
			host.banner("진상 승객 등장", "훨씬 끈질기고 아픕니다. 잡으면 원두를 듬뿍 떨어뜨립니다", "warn")
		end
		host.sfx("elite")
	end
	local function zombieRow()
		local n = min(24, 9 + floor(S.t / 40))
		if S.zk == "gates" then
			return
		end
		if S.zk == "train" then
			local sd = if R() < .5 then -1 else 1
			local m = min(n, 14)
			for i = 0, m - 1 do
				local e = spawn("zomb", p.x + sd * (S.spawnX + floor(i / 5) * 30), ((i % 5) - 2) * 30)
				e.vx = -sd * e.spd
				e.vy = 0
			end
			return
		end
		local a
		if S.zk == "esc" then
			a = (if R() < .5 then 1 else -1) * PI / 2
		else
			a = R() * TAU
		end
		local dx, dy = -cos(a), -sin(a)
		local ox, oy = p.x + cos(a) * S.spawnR, p.y + sin(a) * S.spawnR
		for i = 0, n - 1 do
			local o = (i - (n - 1) / 2) * 34
			local e = spawn("zomb", ox - dy * o, oy + dx * o)
			e.vx = dx * e.spd
			e.vy = dy * e.spd
		end
	end
	-- 개찰구 줄: 단단한 기계와 그 사이의 틈. 작은 것은 틈으로만 지나간다
	local function gateSolve(o, r: number)
		local ry = round(o.y / GATE_GAP) * GATE_GAP
		local dy = o.y - ry
		if abs(dy) >= GATE_TH + r then
			return
		end
		local gx = round(o.x / GATE_PER) * GATE_PER
		local lx = o.x - gx
		local lim = GATE_HALF - r
		if abs(lx) <= GATE_HALF and lim > 0 then
			if abs(dy) < GATE_TH then
				if lx > lim then
					o.x = gx + lim
				elseif lx < -lim then
					o.x = gx - lim
				end
			end
			return
		end
		o.y = ry + (if dy >= 0 then 1 else -1) * (GATE_TH + r)
	end

	---------------- 공간 격자 ----------------
	-- 칸 열쇠 = (cx+32768)*65536 + (cy+32768)
	local grid: { [number]: { any } } = {}
	local gridAge = 0
	local gridUsed: { { any } } = {} -- 지난번에 채운 칸들 (원본은 모든 칸을 비운다 — 채운 칸만 비워도 결과는 같다)
	local function buildGrid()
		gridAge += 1
		if gridAge > 600 then
			grid = {}
			gridAge = 0
		else
			for i = 1, #gridUsed do
				table.clear(gridUsed[i])
			end
		end
		table.clear(gridUsed)
		local E = S.enemies
		local g, used, nu = grid, gridUsed, 0
		for i = 1, #E do
			local e = E[i]
			if not e.dead then
				local key = (floor(e.x / CELL) + 32768) * 65536 + (floor(e.y / CELL) + 32768)
				local a = g[key]
				if not a then
					a = {}
					g[key] = a
				end
				local n = #a
				if n == 0 then
					nu += 1
					used[nu] = a
				end
				a[n + 1] = e
			end
		end
	end
	local function query(x: number, y: number, r: number, fn: (any) -> ())
		local x0, x1 = floor((x - r - MAXR) / CELL), floor((x + r + MAXR) / CELL)
		local y0, y1 = floor((y - r - MAXR) / CELL), floor((y + r + MAXR) / CELL)
		local g = grid
		for cx = x0, x1 do
			local kx = (cx + 32768) * 65536 + 32768
			for cy = y0, y1 do
				local a = g[kx + cy]
				if a then
					for i = 1, #a do
						local e = a[i]
						if not e.dead then
							fn(e)
						end
					end
				end
			end
		end
	end

	---------------- 전투 ----------------
	local function dropBean(x: number, y: number, v: number)
		local Bn = S.beans
		if #Bn >= 380 then
			local b = Bn[floor(R() * #Bn) + 1]
			b.v += v
			return
		end
		Bn[#Bn + 1] = { x = x, y = y, v = v, att = false, sp = 0, ph = R() * TAU }
	end
	local function kill(e, src: string?)
		if e.dead then
			return
		end
		e.dead = true
		S.kills += 1
		host.sfx(if e.boss then "bossdie" elseif e.elite then "elitedie" elseif src == "train" then "trainkill" else "kill", e.x)
		ev({ k = "kill", x = e.x, y = e.y, type = e.type, seed = e.seed, sc = e.sc, vx = e.kx, vy = e.ky, boss = e.boss, elite = e.elite, src = src })
		if e.type == "intern" and not e.elite then
			table.insert(S.slicks, { x = e.x, y = e.y, r = 38, life = 3.2, dur = 3.2 })
		end
		if e.boss then
			for _ = 1, 16 do
				local a = R() * TAU
				local d = R() * 70
				dropBean(e.x + cos(a) * d, e.y + sin(a) * d, ceil(e.xp / 16))
			end
			local nb = {}
			for _, b in ipairs(S.bosses) do
				if b ~= e then
					table.insert(nb, b)
				end
			end
			S.bosses = nb
			S.boss = if #nb > 0 then nb[#nb] else nil
			host.shake(12)
			if e == S.gate then
				S.gate = nil
				S.phase = "clear"
				S.clearT = 1.5
				S.pending += 1
				S.pickMode = "chest"
				p.hp = min(p.maxhp, p.hp + D.heal)
				ev({ k = "heal", v = D.heal })
				host.banner(e.def.name .. " 통과", if S.zone == #ZONES - 1 then "회사 정문이 열렸습니다" else "상여금을 챙기고 다음 장소로 갑니다", "good")
			else
				table.insert(S.items, { kind = "chest", x = e.x, y = e.y, t = 0 })
				host.banner(e.def.name .. " 통과", "상여금 봉투가 떨어졌습니다", "good")
			end
		elseif e.elite then
			for _ = 1, 6 do
				local a = R() * TAU
				local d = R() * 30
				dropBean(e.x + cos(a) * d, e.y + sin(a) * d, ceil(e.xp / 6))
			end
			if R() < .4 * S.M.luck then
				table.insert(S.items, { kind = "kimbap", x = e.x, y = e.y, t = 0 })
			end
		else
			dropBean(e.x, e.y, e.xp)
			local r = R()
			if r < .007 * S.M.luck then
				table.insert(S.items, { kind = "kimbap", x = e.x, y = e.y, t = 0 })
			elseif r < .0105 * S.M.luck then
				table.insert(S.items, { kind = "pass", x = e.x, y = e.y, t = 0 })
			end
		end
	end
	local function hit(e, d: number, kx: number, ky: number, src: string)
		--@unreachable-begin 부르는 쪽이 모두 죽은 적을 먼저 거른다 (원본의 안전 장치)
		if e.dead then
			return
		end
		--@unreachable-end
		if e.intro > 0 then
			return
		end
		local M = S.M
		local fm = 1
		if truthy(S.fsrc[src]) then
			fm = if truthy(S.fus.freepass) and (src == "card" or src == "handle") then 1.5 else 1.3
		end
		d *= M.might * W_SCALE * fm * (if e.boss or e.elite then M.bossDmg else 1) * (if p.hp < p.maxhp * .5 then M.low else 1)
		local crit = R() < M.crit
		if crit then
			d *= 2
		end
		e.hp -= d
		e.flash = .12
		local res = if e.boss then 1 elseif e.elite then .8 else (e.def.kbRes or 0)
		e.kx += kx * (1 - res)
		e.ky += ky * (1 - res)
		ev({ k = "num", x = e.x, y = e.y - e.r - 8, v = d, crit = crit })
		addDmg(src, d)
		if crit then
			host.sfx("crit", e.x)
		end
		if e.hp <= 0 then
			kill(e, src)
		else
			host.sfx("hit", e.x, src)
			ev({ k = "hit", x = e.x, y = e.y, src = src })
		end
	end
	local function hurt(d: number, force: boolean?, src: string?)
		if truthy(opts.demo) or S.state ~= "run" then
			return
		end
		if not force and p.inv > 0 then
			return
		end
		d *= S.M.armor
		p.hp -= d
		S.taken += d
		local by = src or "contact"
		S.takenBy[by] = (S.takenBy[by] or 0) + d
		p.inv = S.M.invT
		host.sfx("hurt")
		host.shake(8)
		ev({ k = "hurt", v = d })
		if p.hp <= 0 then
			p.hp = 0
			S.state = "over"
			host.finish(false)
		end
	end
	-- 가까운 순서로 n 명까지 (maxD 안). 원본은 [{e,d}] — 여기서는 적만 든 배열을 돌려준다
	local nnD: { number } = {}
	local function nearestN(n: number, maxD: number): { any }
		local out, ds, cnt = {}, nnD, 0
		local E, m2 = S.enemies, maxD * maxD
		local px, py = p.x, p.y
		for i = 1, #E do
			local e = E[i]
			if not e.dead then
				local dx, dy = e.x - px, e.y - py
				local d = dx * dx + dy * dy
				if not (d > m2) then
					-- 원본: push 뒤 안정 정렬 = 같거나 가까운 것들 뒤에 끼워 넣기
					if cnt < n then
						local j = cnt
						while j >= 1 and ds[j] > d do
							out[j + 1] = out[j]
							ds[j + 1] = ds[j]
							j -= 1
						end
						out[j + 1] = e
						ds[j + 1] = d
						cnt += 1
					elseif d < ds[n] then
						local j = n - 1
						while j >= 1 and ds[j] > d do
							out[j + 1] = out[j]
							ds[j + 1] = ds[j]
							j -= 1
						end
						out[j + 1] = e
						ds[j + 1] = d
					end
				end
			end
		end
		return out
	end
	-- (life · r 에 0 을 넘기는 곳은 없다: `life||4`, `r||7`)
	local function shoot(x: number, y: number, a: number, spd: number, dmg: number, kind: number, life: number?, r: number?)
		local Bl = S.bullets
		if #Bl >= 260 then
			table.remove(Bl, 1)
		end
		local vx, vy = cos(a) * spd, sin(a) * spd
		Bl[#Bl + 1] = { x = x, y = y, vx = vx, vy = vy, life = if life and life ~= 0 then life else 4, dmg = dmg, r = if r and r ~= 0 then r else 7, kind = kind, a = R() * TAU }
	end

	---------------- 무기 ----------------
	local function ready(k: string, cd: number, dt: number, first: number?): boolean
		local wt = S.wt
		local v = wt[k]
		if v == nil then
			v = cd * (if first == nil then .3 else first)
		end
		v -= dt
		if v <= 0 then
			v += cd * S.M.cd
			if v < 0 then
				v = cd * S.M.cd
			end
			wt[k] = v
			return true
		end
		wt[k] = v
		return false
	end
	-- 돌려주는 값: x, y (원본은 [x, y])
	local function pickSpot(): (number, number)
		local E = S.enemies
		local tr = 0
		while tr < 12 and #E > 0 do
			local e = E[floor(R() * #E) + 1]
			if not e.dead then
				if hypot(e.x - p.x, e.y - p.y) < 300 then
					return e.x, e.y
				end
			end
			tr += 1
		end
		local a = R() * TAU
		local d = 70 + R() * 90
		return p.x + cos(a) * d, p.y + sin(a) * d
	end
	local WpScratch = {}
	local function weapons(dt: number)
		local Wp = S.weapons
		local M = S.M
		local l
		local FZ = S.fus
		if next(FZ) ~= nil then
			-- 조합이 있으면 사본을 만들어 재료 무기를 진화 단계로 본다
			Wp = WpScratch
			table.clear(Wp)
			for k, v in S.weapons do
				Wp[k] = v
			end
			for fk in FZ do
				local f = FUSIONS[fk]
				Wp[f.a] = EVO
				Wp[f.b] = EVO
			end
		end
		-- 세 조합은 재료 무기 둘을 새 공격 하나로 바꾼다
		if truthy(FZ.bulldozer) then
			Wp.backpack = 0
			Wp.shoulder = 0
			-- 배낭 철퇴: 끈에 매단 큰 배낭 하나를 해머던지기처럼 돌린다. 대시가 끝나면 내려찍는다
			local F = S.mace
			if not F then
				F = { a = 0, sl = 0, rad = 60, x = p.x, y = p.y }
				S.mace = F
			end
			local R0, sz = 150 * M.area, 48
			if F.sl > 0 then
				F.sl -= dt
				if F.sl <= 0 then
					local r = 175 * M.area
					query(F.x, F.y, r, function(e)
						local dx, dy = e.x - F.x, e.y - F.y
						local d = hypot(dx, dy)
						if d == 0 then
							d = 1
						end
						if d < r + e.r then
							if not e.boss then
								e.stun = max(e.stun, .8)
							end
							hit(e, MACE.slam, dx / d * 380, dy / d * 380, "bulldozer")
						end
					end)
					ev({ k = "maceslam", x = F.x, y = F.y, r = r })
					host.shake(9)
					host.sfx("bump", nil, true)
					F.rad = hypot(F.x - p.x, F.y - p.y)
					F.a = atan2(F.y - p.y, F.x - p.x)
				end
			else
				F.a += MACE.spin * dt
				F.rad += (R0 - F.rad) * min(1, dt * 4)
				local ox, oy = p.x + cos(F.a) * F.rad, p.y + sin(F.a) * F.rad
				F.x = ox
				F.y = oy
				query(ox, oy, sz, function(e)
					if e.bpT > 0 then
						return
					end
					local dx, dy, rr = e.x - ox, e.y - oy, e.r + sz
					if dx * dx + dy * dy < rr * rr then
						e.bpT = .5
						if not e.boss then
							e.stun = max(e.stun, .25)
						end
						hit(e, MACE.dmg, -sin(F.a) * 300, cos(F.a) * 300, "bulldozer")
						ev({ k = "macehit", x = e.x, y = e.y })
					end
				end)
				-- 팽팽한 끈은 나와 배낭 사이에 선 사람을 친다
				do
					local cx, cy = cos(F.a), sin(F.a)
					query(p.x + cx * F.rad * .5, p.y + cy * F.rad * .5, F.rad * .5, function(e)
						if e.bpT > 0 then
							return
						end
						local dx, dy = e.x - p.x, e.y - p.y
						local al = dx * cx + dy * cy
						if al > 10 and al < F.rad - sz and abs(dx * cy - dy * cx) < 10 + e.r then
							e.bpT = .5
							hit(e, MACE.strap, -cy * 160, cx * 160, "bulldozer")
						end
					end)
				end
				if p.dashT > 0 then
					S.wasDash = true
				elseif S.wasDash then
					S.wasDash = false
					F.sd = .24
					F.sl = .24
					F.x0 = ox
					F.y0 = oy
					ev({ k = "macedash", a = atan2(p.fy, p.fx) })
					F.x = p.x + p.fx * 80
					F.y = p.y + p.fy * 80
				end
			end
		end
		if truthy(FZ.routine) then
			Wp.coffee = 0
			Wp.alarm = 0
			-- 커피 시한폭탄: 사람들 사이에 내려놓은 컵이 잠깐 째깍거리다 터지고 바닥을 적신다
			if ready("routine", BOMB.cd * M.cd, dt) then
				local live = 0
				for _, m in ipairs(S.mines) do
					if m.tb then
						live += 1
					end
				end
				local n = 0
				local k = 0
				while k < BOMB.n and live + k < 8 do
					local qx, qy = pickSpot()
					local mx = qx + (R() - .5) * 56
					local my = qy + (R() - .5) * 44
					table.insert(S.mines, { tb = true, x = mx, y = my, fuse = BOMB.fuse, dur = BOMB.fuse, r = WEAPONS.alarm.stat(EVO).r * M.area, dmg = BOMB.dmg, stun = .7, rings = 2, evo = true })
					n += 1
					k += 1
				end
				if n ~= 0 then
					host.sfx("throw")
				end
			end
		end
		if truthy(FZ.gentleman) then
			Wp.umbrella = 0
			Wp.tie = 0
			-- 우산 방패: 펼친 우산을 걷는 쪽으로 내밀어 닿는 것을 막고, 막을 때마다 넥타이로 받아친다
			local G = S.gent
			if not G then
				G = { a = atan2(p.fy, p.fx), cd = 0, auto = 1, fl = 0 }
				S.gent = G
			end
			local ta = atan2(p.fy, p.fx)
			local dd = atan2(sin(ta - G.a), cos(ta - G.a))
			G.a += dd * min(1, dt * 12)
			G.cd -= dt
			G.auto -= dt
			if G.fl > 0 then
				G.fl -= dt
			end
			local blocked = false
			local function inArc(x: number, y: number, rad: number): boolean
				local dx, dy = x - p.x, y - p.y
				local d = hypot(dx, dy)
				if d > GUARD.r + rad or d < GUARD.r - 30 - rad then
					return false
				end
				local an = atan2(dy, dx) - G.a
				return abs(atan2(sin(an), cos(an))) < GUARD.half
			end
			local Bl = S.bullets
			for i = #Bl, 1, -1 do
				local b = Bl[i]
				if inArc(b.x, b.y, b.r) then
					ev({ k = "parry", x = b.x, y = b.y })
					table.remove(Bl, i)
					blocked = true
				end
			end
			query(p.x, p.y, GUARD.r + 40, function(e)
				if e.shT > 0 or e.intro > 0 then
					return
				end
				if inArc(e.x, e.y, e.r) then
					e.shT = .3
					local gx, gy = cos(G.a), sin(G.a)
					hit(e, GUARD.bash, gx * GUARD.push, gy * GUARD.push, "gentleman")
					blocked = true
				end
			end)
			if blocked then
				if G.fl <= 0 then
					host.sfx("hit", nil, "umbrella")
				end
				G.fl = .18
			end
			if (blocked and G.cd <= 0) or G.auto <= 0 then
				local r = GUARD.len * M.area
				local dm = if blocked then GUARD.counter else GUARD.dmg
				G.cd = GUARD.cd
				G.auto = GUARD.auto * M.cd
				query(p.x, p.y, r, function(e)
					local dx, dy = e.x - p.x, e.y - p.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					if d < r + e.r then
						hit(e, dm, dx / d * 280, dy / d * 280, "gentleman")
					end
				end)
				ev({ k = "lashspin", r = r, w = 38 * sqrt(M.area), gent = true })
				host.sfx("lash", nil, true)
				if blocked then
					host.shake(3)
				end
			end
		end
		l = Wp.card
		if l and l ~= 0 then
			local s = WEAPONS.card.stat(l)
			local wt = S.wt
			if wt.card == nil then
				wt.card = .4
			end
			wt.card -= dt
			if wt.card <= 0 then
				local cn = s.n + (if truthy(S.fus.freepass) then 2 else 0)
				local T = nearestN(cn, 540)
				local tn = #T
				if tn > 0 then
					wt.card = s.cd * M.cd
					for i = 0, cn - 1 do
						local e, rep = T[i % tn + 1], i // tn
						local a = atan2(e.y - p.y, e.x - p.x) + (if rep ~= 0 then (if rep % 2 == 1 then 1 else -1) * .14 * ceil(rep / 2) else 0)
						table.insert(S.shots, { x = p.x, y = p.y, vx = cos(a) * 450, vy = sin(a) * 450, life = 1.4, dmg = s.dmg, pierce = s.pierce, hits = {}, evo = l >= EVO, a = a })
					end
					host.sfx("card", nil, l >= EVO)
				else
					wt.card = .15
				end
			end
		end
		l = Wp.umbrella
		if l and l ~= 0 then
			local s = WEAPONS.umbrella.stat(l)
			if s.combo then
				local gent, quad, Q = truthy(S.fus.gentleman), true, S.umbQ
				if Q then
					Q.t -= dt
					if Q.t <= 0 then
						local fin = Q.n == 2
						local range = (if fin then s.finLen else s.range) * M.area
						local ba = Q.a + (if gent then Q.n * PI / 4 else 0)
						local dirs = { ba, ba + PI / 2, ba + PI, ba - PI / 2 }
						for _, a in ipairs(dirs) do
							local cx, cy = cos(a), sin(a)
							if fin then
								local w, E = s.finW * M.area, S.enemies
								for i = 1, #E do
									local e = E[i]
									if not e.dead then
										local dx, dy = e.x - p.x, e.y - p.y
										local al = dx * cx + dy * cy
										if not (al < -e.r or al > range + e.r) then
											if abs(dx * cy - dy * cx) < w + e.r then
												hit(e, s.fin, cx * s.kb * 2.2, cy * s.kb * 2.2, "umbrella")
											end
										end
									end
								end
							else
								query(p.x, p.y, range, function(e)
									local dx, dy = e.x - p.x, e.y - p.y
									local d = hypot(dx, dy)
									if d > range + e.r then
										return
									end
									local da = abs(angd(atan2(dy, dx) - a))
									if da <= s.half or d < e.r + p.r then
										hit(e, s.dmg, cx * s.kb, cy * s.kb, "umbrella")
									end
								end)
							end
						end
						ev({ k = "stab", a = ba, range = range, n = Q.n, quad = quad })
						host.sfx("swing", nil, fin)
						if fin then
							host.shake(3)
						end
						Q.n += 1
						Q.t = if Q.n == 2 then .2 else .15
						if Q.n > 2 then
							S.umbQ = nil
						end
					end
				elseif ready("umbrella", s.cd * (if gent then .8 else 1), dt) then
					local a = atan2(p.fy, p.fx)
					local T = nearestN(1, s.finLen * M.area)
					if #T > 0 then
						a = atan2(T[1].y - p.y, T[1].x - p.x)
					end
					S.umbQ = { a = a, n = 0, t = 0 }
				end
			elseif ready("umbrella", s.cd, dt) then
				local range = s.range * M.area
				local a = atan2(p.fy, p.fx)
				local T = nearestN(1, range * 1.6)
				if #T > 0 then
					a = atan2(T[1].y - p.y, T[1].x - p.x)
				end
				query(p.x, p.y, range, function(e)
					local dx, dy = e.x - p.x, e.y - p.y
					local d = hypot(dx, dy)
					if d > range + e.r then
						return
					end
					local da = abs(angd(atan2(dy, dx) - a))
					if da <= s.half or (s.both and PI - da <= s.half) or d < e.r + p.r then
						local k = s.kb / (if d ~= 0 then d else 1)
						hit(e, s.dmg, dx * k, dy * k, "umbrella")
					end
				end)
				ev({ k = "swipe", a = a, range = range, half = s.half, both = s.both, evo = false })
				host.sfx("swing", nil, l >= EVO)
			end
		end
		l = Wp.backpack
		if l and l ~= 0 then
			local s = WEAPONS.backpack.stat(l)
			local bull = truthy(S.fus.bulldozer)
			local rad = s.radius * M.area * (if bull then .8 else 1)
			S.orbA += s.spin * dt
			--@unreachable-begin 배낭 철퇴 조합은 backpack 을 0 으로 만들므로 bull 이 참인 채로는 여기 오지 않는다 (원본에 남아 있는 옛 가지)
			if bull then
				local ta = atan2(p.fy, p.fx)
				if S.bullA == nil then
					S.bullA = ta
				end
				local d = atan2(sin(ta - S.bullA), cos(ta - S.bullA))
				S.bullA += d * min(1, dt * 11)
			end
			--@unreachable-end
			local bsz = s.size * (if bull then 1.35 else 1)
			local bfx = if bull then cos(S.bullA) else 0
			local bfy = if bull then sin(S.bullA) else 0
			for k = 0, s.n - 1 do
				local a = if bull then S.bullA + (k - (s.n - 1) / 2) * .44 else S.orbA + k * TAU / s.n
				local ox, oy = p.x + cos(a) * rad, p.y + sin(a) * rad
				query(ox, oy, bsz, function(e)
					if e.bpT > 0 then
						return
					end
					local dx, dy, rr = e.x - ox, e.y - oy, e.r + bsz
					if dx * dx + dy * dy < rr * rr then
						e.bpT = if bull then .2 else .3
						local ex, ey = e.x - p.x, e.y - p.y
						local d = hypot(ex, ey)
						if d == 0 then
							d = 1
						end
						if bull then
							--@unreachable-begin (위와 같음)
							hit(e, s.dmg, bfx * 230, bfy * 230, "backpack")
							--@unreachable-end
						else
							hit(e, s.dmg, ex / d * 130, ey / d * 130, "backpack")
						end
					end
				end)
			end
		end
		l = Wp.coffee
		if l and l ~= 0 then
			local s = WEAPONS.coffee.stat(l)
			if ready("coffee", s.cd, dt) then
				for _ = 1, s.n do
					local qx, qy = pickSpot()
					table.insert(S.lobs, { x0 = p.x, y0 = p.y - 10, x1 = qx, y1 = qy, t = 0, dur = .36, r = s.r * M.area, life = s.dur, dmg = s.tick, slow = s.slow, evo = l >= EVO })
				end
				host.sfx("throw")
			end
		end
		l = Wp.anc
		if l and l ~= 0 then
			local s = WEAPONS.anc.stat(l)
			if ready("anc", s.cd, dt) then
				local r = s.r * M.area
				query(p.x, p.y, r, function(e)
					local dx, dy = e.x - p.x, e.y - p.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					if d < r + e.r then
						hit(e, s.dmg, dx / d * s.kb, dy / d * s.kb, "anc")
					end
				end)
				ev({ k = "ring", r = r, evo = l >= EVO })
				host.sfx("pulse", nil, l >= EVO)
			end
		end
		l = Wp.shout
		if l and l ~= 0 then
			local s = WEAPONS.shout.stat(l)
			if ready("shout", s.cd, dt, .25) then
				local r, E = S.spawnR, S.enemies
				for i = 1, #E do
					local e = E[i]
					if not e.dead then
						local dx, dy = e.x - p.x, e.y - p.y
						local d = hypot(dx, dy)
						if d == 0 then
							d = 1
						end
						if d < r then
							if not e.boss then
								e.stun = max(e.stun, if e.elite then s.stun * .5 else s.stun)
							end
							hit(e, s.dmg, dx / d * 330, dy / d * 330, "shout")
						end
					end
				end
				table.clear(S.bullets)
				ev({ k = "shout", r = r, evo = l >= EVO })
				host.sfx("shout", nil, l >= EVO)
				host.shake(6)
			end
		end
		l = Wp.battery
		if l and l ~= 0 then
			local s = WEAPONS.battery.stat(l)
			local wt = S.wt
			if wt.battery == nil then
				wt.battery = .5
			end
			wt.battery -= dt
			if wt.battery <= 0 then
				local T = nearestN(1, 290)
				if #T > 0 then
					wt.battery = s.cd * M.cd
					local cur = T[1]
					local pts, used, jump = { p.x, p.y - 14 }, {}, 150 * M.area
					local c = 0
					while c <= s.chain and cur do
						table.insert(used, cur.id)
						table.insert(pts, cur.x)
						table.insert(pts, cur.y - 6)
						local cx, cy = cur.x, cur.y
						if s.stun ~= 0 and not cur.boss then
							cur.stun = max(cur.stun, s.stun)
						end
						hit(cur, s.dmg, 0, 0, "battery")
						local nx, nd = nil, jump * jump
						query(cx, cy, jump, function(e)
							if table.find(used, e.id) then
								return
							end
							local dx, dy = e.x - cx, e.y - cy
							local d2 = dx * dx + dy * dy
							if d2 < nd then
								nd = d2
								nx = e
							end
						end)
						cur = nx
						c += 1
					end
					ev({ k = "zap", pts = pts, evo = l >= EVO })
					host.sfx("zap", nil, l >= EVO)
				else
					wt.battery = .2
				end
			end
		end
		l = Wp.scooter
		if l and l ~= 0 then
			local s = WEAPONS.scooter.stat(l)
			local wt = S.wt
			if wt.scooter == nil then
				wt.scooter = .6
			end
			wt.scooter -= dt
			if wt.scooter <= 0 then
				local T = nearestN(1, 520)
				if #T > 0 then
					wt.scooter = s.cd * M.cd
					local a = atan2(T[1].y - p.y, T[1].x - p.x)
					local dirs = if l >= EVO then { a - .32, a, a + .32 } elseif s.n > 1 then { a, a + PI } else { a }
					for _, d in ipairs(dirs) do
						table.insert(S.riders, { x = p.x - cos(d) * 90, y = p.y - sin(d) * 90, dx = cos(d), dy = sin(d), dist = 0, max = s.max * M.area, w = s.w * M.area, dmg = s.dmg, hits = {}, evo = l >= EVO })
					end
					host.sfx("scooter", nil, l >= EVO)
				else
					wt.scooter = .2
				end
			end
		end
		l = Wp.selfie
		if l and l ~= 0 then
			local s = WEAPONS.selfie.stat(l)
			local len = s.len * M.area
			S.selfA += s.spin * dt
			for k = 0, s.n - 1 do
				local a = S.selfA + k * TAU / s.n
				local cx, sy = cos(a), sin(a)
				for d = 26, len, 26 do
					local bx, by = p.x + cx * d, p.y + sy * d
					query(bx, by, 15, function(e)
						if e.sfT > 0 then
							return
						end
						local ex, ey, rr = e.x - bx, e.y - by, e.r + 15
						if ex * ex + ey * ey < rr * rr then
							e.sfT = .4
							if s.stun ~= 0 and not e.boss then
								e.stun = max(e.stun, s.stun)
							end
							hit(e, s.dmg, -sy * 70, cx * 70, "selfie")
						end
					end)
				end
			end
		end
		l = Wp.handle
		if l and l ~= 0 then
			local s = WEAPONS.handle.stat(l)
			local wt = S.wt
			if wt.handle == nil then
				wt.handle = .5
			end
			wt.handle -= dt
			if wt.handle <= 0 then
				local T = nearestN(s.n, 420)
				local tn = #T
				if tn > 0 then
					wt.handle = s.cd * M.cd
					local sp = 560 * s.range * sqrt(M.area)
					for i = 0, s.n - 1 do
						local e, rep = T[i % tn + 1], i // tn
						local a = atan2(e.y - p.y, e.x - p.x) + (if rep ~= 0 then (if rep % 2 == 1 then 1 else -1) * .35 * ceil(rep / 2) else 0)
						table.insert(S.rangs, { x = p.x, y = p.y, vx = cos(a) * sp, vy = sin(a) * sp, ph = 0, t = 0, sp = 0, dmg = s.dmg, size = s.size, hits = {}, evo = l >= EVO })
					end
					host.sfx("throw")
				else
					wt.handle = .15
				end
			end
		end
		l = Wp.alarm
		if l and l ~= 0 then
			local s = WEAPONS.alarm.stat(l)
			if ready("alarm", s.cd, dt) then
				for _ = 1, s.n do
					local qx, qy = pickSpot()
					table.insert(S.lobs, { kind = "alarm", x0 = p.x, y0 = p.y - 10, x1 = qx, y1 = qy, t = 0, dur = .4, r = s.r * M.area, dmg = s.dmg, stun = s.stun, rings = s.rings, evo = l >= EVO })
				end
				host.sfx("throw")
			end
		end
		l = Wp.tie
		if l and l ~= 0 then
			local s = WEAPONS.tie.stat(l)
			if ready("tie", s.cd, dt) then
				local len, w, gent = s.len * M.area, s.w * sqrt(M.area), truthy(S.fus.gentleman)
				S.tieN = (S.tieN or 0) + 1
				if l >= EVO and (gent or S.tieN % 3 == 0) then
					local r = len * (if gent then 1.15 else .95)
					query(p.x, p.y, r, function(e)
						local dx, dy = e.x - p.x, e.y - p.y
						local d = hypot(dx, dy)
						if d == 0 then
							d = 1
						end
						if d < r + e.r then
							hit(e, s.dmg * 1.35, dx / d * s.kb * 1.4, dy / d * s.kb * 1.4, "tie")
						end
					end)
					ev({ k = "lashspin", r = r, w = w, gent = gent })
					host.sfx("lash", nil, true)
					host.shake(3)
				else
					local T = nearestN(1, len + 140)
					local a0 = if #T > 0 then atan2(T[1].y - p.y, T[1].x - p.x) else atan2(p.fy, p.fx)
					local as = if s.both then { a0, a0 + PI } else { a0 }
					for _, a in ipairs(as) do
						local cx, cy = cos(a), sin(a)
						query(p.x + cx * len / 2, p.y + cy * len / 2, len / 2 + w, function(e)
							local dx, dy = e.x - p.x, e.y - p.y
							local al = dx * cx + dy * cy
							if al > -e.r and al < len + e.r and abs(dx * cy - dy * cx) < w + e.r then
								local tip = al > len * .68
								hit(e, s.dmg * (if tip then 1.4 else 1), cx * s.kb * (if tip then 1.5 else 1), cy * s.kb * (if tip then 1.5 else 1), "tie")
							end
						end)
					end
					ev({ k = "lash", as = as, len = len, w = w, evo = l >= EVO })
					host.sfx("lash", nil, l >= EVO)
				end
			end
		end
		l = Wp.laptop
		if truthy(S.fus.remote) then
			local n = 0
			for _, b in ipairs(S.beams) do
				if b.perm then
					n += 1
				end
			end
			if n == 0 then
				for j = 0, 3 do
					table.insert(S.beams, { perm = true, a = j * TAU / 4, da = .75, life = .5, dur = 1, len = 600 * sqrt(M.area), w = 20 * M.area, dmg = 27, tick = 0, evo = true, j = j })
				end
			end
		elseif l and l ~= 0 then
			local s = WEAPONS.laptop.stat(l)
			local wt = S.wt
			if wt.laptop == nil then
				wt.laptop = .7
			end
			wt.laptop -= dt
			if wt.laptop <= 0 then
				local T = nearestN(1, 480)
				if #T > 0 then
					wt.laptop = s.cd * M.cd
					local a0 = atan2(T[1].y - p.y, T[1].x - p.x)
					local len, w, evo = s.len * sqrt(M.area), s.w * M.area, l >= EVO
					local dir = if R() < .5 then -1 else 1
					local sw, dur = (if evo then .8 else .5), (if evo then .9 else .6)
					for j = 0, s.n - 1 do
						table.insert(S.beams, { a = a0 + j * TAU / s.n - dir * sw / 2, da = dir * sw / dur, life = dur, dur = dur, len = len, w = w, dmg = s.dmg * .31, tick = 0, evo = evo, j = j })
					end
					ev({ k = "laptop", evo = evo })
					host.sfx("beam", nil, evo)
				else
					wt.laptop = .2
				end
			end
		end
		do
			local beams = S.beams
			for i = #beams, 1, -1 do
				local b = beams[i]
				local gone = false
				if b.perm then
					if not truthy(S.fus.remote) then
						table.remove(beams, i)
						gone = true
					else
						b.life = .5
					end
				else
					b.life -= dt
				end
				if not gone then
					b.a += b.da * dt
					b.tick -= dt
					if b.tick <= 0 then
						b.tick = if b.perm then .12 else .2
						local zc = 0
						local cx, cy, E = cos(b.a), sin(b.a), S.enemies
						for k = 1, #E do
							local e = E[k]
							if not e.dead then
								local dx, dy = e.x - p.x, e.y - p.y
								local al = dx * cx + dy * cy
								if not (al < -e.r or al > b.len + e.r) then
									if abs(dx * cy - dy * cx) < b.w + e.r then
										hit(e, b.dmg, cx * 45, cy * 45, "laptop")
										-- 재택근무: 광선에 닿은 사람에게서 번개가 옆으로 번진다
										if b.perm and not (e.rzT > 0) and zc < 3 then
											zc += 1
											e.rzT = .45
											local cur = e
											local pts, used = { e.x, e.y - 6 }, { e.id }
											local c = 0
											while c < 4 and cur do
												local nx, nd = nil, 165 * 165
												local ux, uy = cur.x, cur.y
												query(ux, uy, 165, function(o)
													if o.dead or table.find(used, o.id) then
														return
													end
													local ox, oy = o.x - ux, o.y - uy
													local d2 = ox * ox + oy * oy
													if d2 < nd then
														nd = d2
														nx = o
													end
												end)
												if nx then
													table.insert(used, nx.id)
													table.insert(pts, nx.x)
													table.insert(pts, nx.y - 6)
													nx.rzT = .3
													hit(nx, 38, 0, 0, "battery")
												end
												cur = nx
												c += 1
											end
											if #pts > 2 then
												ev({ k = "zap", pts = pts, evo = true, gold = true })
												host.sfx("zap", e.x, true)
											end
										end
									end
								end
							end
						end
					end
					if b.life <= 0 then
						table.remove(beams, i)
					end
				end
			end
		end
		l = Wp.gum
		if l and l ~= 0 then
			local s = WEAPONS.gum.stat(l)
			if ready("gum", s.cd, dt) then
				table.insert(S.puddles, { x = p.x - p.fx * 14, y = p.y - p.fy * 14, r = s.r * M.area, life = s.dur, dur = s.dur, tick = .15, dmg = s.tick, slow = s.slow, evo = l >= EVO, gum = true, ph = R() * TAU })
				host.sfx("gum")
			end
		end
		l = Wp.shoulder
		if l and l ~= 0 then
			local s = WEAPONS.shoulder.stat(l)
			local bull = truthy(S.fus.bulldozer)
			local r, evo = s.r * M.area * (if bull then 1.45 else 1), l >= EVO
			--@unreachable-begin 배낭 철퇴 조합은 shoulder 를 0 으로 만들므로 bull 이 참인 채로는 여기 오지 않는다 (원본에 남아 있는 옛 가지)
			if bull then
				s.cdE = .2
				s.stun = .8
				s.mul *= 1.5
			end
			--@unreachable-end
			-- 큰 한 방은 대시 끝에서만 나온다
			local function burst()
				query(p.x, p.y, r, function(e)
					local dx, dy = e.x - p.x, e.y - p.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					if d < r + e.r then
						if s.stun ~= 0 and not e.boss then
							e.stun = max(e.stun, s.stun)
						end
						e.shT = .3
						hit(e, s.dmg * s.mul, dx / d * s.kb * 1.3, dy / d * s.kb * 1.3, "shoulder")
					end
				end)
				if bull then
					--@unreachable-begin (위와 같음)
					ev({ k = "fcast", t = "bulldozer", r = r })
					host.shake(8)
					--@unreachable-end
				else
					ev({ k = "bump", r = r, evo = evo, a = atan2(if p.ddy ~= 0 then p.ddy else p.fy, if p.ddx ~= 0 then p.ddx else p.fx) })
					host.shake(if evo then 6 else 4)
				end
				host.sfx("bump", nil, evo)
			end
			if p.dashT > 0 then
				S.wasDash = true
				if s.trail then
					query(p.x, p.y, 38, function(e)
						if e.shT > 0 then
							return
						end
						local dx, dy, rr = e.x - p.x, e.y - p.y, 38 + e.r
						if dx * dx + dy * dy < rr * rr then
							e.shT = .5
							hit(e, s.dmg * 1.3, p.ddx * 200, p.ddy * 200, "shoulder")
						end
					end)
				end
			else
				if S.wasDash then
					S.wasDash = false
					burst()
				end
				-- 버티고 서 있으면 부딪혀 오는 사람을 어깨로 받아친다
				local n = 0
				local wt = S.wt
				wt.shN = (wt.shN or 0) - dt
				query(p.x, p.y, p.r + 40, function(e)
					if e.shT > 0 or e.intro > 0 then
						return
					end
					local dx, dy = e.x - p.x, e.y - p.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					if d < p.r + e.r + (if bull then 22 else 9) then
						e.shT = s.cdE
						hit(e, s.dmg, dx / d * s.kb, dy / d * s.kb, "shoulder")
						local seen = n
						n += 1
						if seen < 2 then
							ev({ k = "nudge", x = p.x + dx / d * (p.r + 4), y = p.y + dy / d * (p.r + 4), a = atan2(dy, dx), evo = evo, bag = bull })
						end
					end
				end)
				if n ~= 0 and wt.shN <= 0 then
					wt.shN = .14
					host.sfx("hit", nil, "shoulder")
				end
			end
		end
		l = Wp.hotpack
		if l and l ~= 0 then
			local s = WEAPONS.hotpack.stat(l)
			S.auraT -= dt
			if S.auraT <= 0 then
				S.auraT = s.tick * M.cd
				local r = s.r * M.area
				query(p.x, p.y, r, function(e)
					local dx, dy, rr = e.x - p.x, e.y - p.y, r + e.r * .6
					if dx * dx + dy * dy < rr * rr then
						if s.slow ~= 0 and not e.boss then
							e.slow = .5
							e.slowAmt = max(e.slowAmt, s.slow)
						end
						hit(e, s.dmg, 0, 0, "hotpack")
					end
				end)
			end
		end
	end

	---------------- 레벨 업 ----------------
	local function genChoices(): { any }
		if S.pickMode == "start" then
			local ks, out = table.clone(WEAPON_ORDER), {}
			while #out < 3 do
				local k = table.remove(ks, floor(R() * #ks) + 1)
				local w = WEAPONS[k]
				table.insert(out, { kind = "weapon", key = k, to = 1, name = w.name, desc = w.lv[1], tag = "시작 무기", hint = "진화 짝: " .. PASSIVES[w.pair].name })
			end
			return out
		end
		local pool, evos = {}, {}
		local wn, pn = owned(S.weapons) + owned(S.fus), owned(S.passives)
		for _, k in ipairs(FUSION_ORDER) do
			local f = FUSIONS[k]
			if (S.weapons[f.a] or 0) >= EVO and (S.weapons[f.b] or 0) >= EVO then
				table.insert(evos, 1, { kind = "fuse", key = k, to = 1, name = f.name, desc = f.desc, tag = "히든 조합", hint = WEAPONS[f.a].evoName .. " + " .. WEAPONS[f.b].evoName })
			end
		end
		for _, k in ipairs(WEAPON_ORDER) do
			if not truthy(S.fsrc[k]) then
				local l, w = S.weapons[k] or 0, WEAPONS[k]
				local hint = "진화 짝: " .. PASSIVES[w.pair].name .. (if truthy(S.passives[w.pair]) then " (보유)" else "")
				if l == 0 then
					if wn < MAX_W then
						table.insert(pool, { kind = "weapon", key = k, to = 1, name = w.name, desc = w.lv[1], tag = "새 무기", hint = hint, wt = if truthy(S.passives[w.pair]) then 2.5 else 1 })
					end
				elseif l < WMAX then
					table.insert(pool, { kind = "weapon", key = k, to = l + 1, name = w.name, desc = w.lv[l + 1], tag = "무기 강화", hint = hint, wt = 3 })
				elseif l == WMAX and truthy(S.passives[w.pair]) then
					table.insert(evos, { kind = "evo", key = k, to = WMAX + 1, name = w.evoName, desc = w.evoDesc, tag = "진화", hint = w.name .. " + " .. PASSIVES[w.pair].name })
				end
			end
		end
		for _, k in ipairs(PASSIVE_ORDER) do
			local l, pq, wk = S.passives[k] or 0, PASSIVES[k], PAIR_OF[k]
			local hint = WEAPONS[wk].name .. " 진화에 필요" .. (if truthy(S.weapons[wk]) then " (보유)" else "")
			if l == 0 then
				if pn < MAX_P then
					table.insert(pool, { kind = "passive", key = k, to = 1, name = pq.name, desc = pq.desc, tag = "새 장비", hint = hint, wt = if truthy(S.weapons[wk]) then 3.5 else 1 })
				end
			elseif l < PMAX then
				table.insert(pool, { kind = "passive", key = k, to = l + 1, name = pq.name, desc = pq.desc, tag = "장비 강화", hint = hint, wt = 2 })
			end
		end
		local out = {}
		if #evos > 0 then
			table.insert(out, if evos[1].kind == "fuse" then evos[1] else evos[floor(R() * #evos) + 1])
		end
		while #out < 3 and #pool > 0 do
			local tot = 0
			for _, c in ipairs(pool) do
				tot += c.wt
			end
			local r, i = R() * tot, 1
			while i < #pool do
				r -= pool[i].wt
				if r <= 0 then
					break
				end
				i += 1
			end
			table.insert(out, table.remove(pool, i))
		end
		local heals = {
			{ kind = "heal", key = "heal", to = 0, name = "삼각김밥", desc = "멘탈을 20 회복합니다", tag = "간식", hint = "더 올릴 것이 없을 때 나옵니다" },
			{ kind = "heal", key = "heal2", to = 0, name = "캔커피", desc = "멘탈을 20 회복합니다", tag = "간식", hint = "더 올릴 것이 없을 때 나옵니다" },
			{ kind = "heal", key = "heal", to = 0, name = "편의점 도시락", desc = "멘탈을 20 회복합니다", tag = "간식", hint = "더 올릴 것이 없을 때 나옵니다" },
		}
		local hi = 1
		while #out < 3 do
			table.insert(out, heals[hi])
			hi += 1
		end
		return out
	end
	local function apply(c)
		if c.kind == "fuse" then
			local f = FUSIONS[c.key]
			S.weapons[f.a] = nil
			S.weapons[f.b] = nil
			S.fus[c.key] = 1
			S.fsrc[f.a] = 1
			S.fsrc[f.b] = 1
			ev({ k = "fuse" })
			host.sfx("evo")
		elseif c.kind == "weapon" or c.kind == "evo" then
			S.weapons[c.key] = c.to
		elseif c.kind == "passive" then
			S.passives[c.key] = c.to
			if c.key == "gym" then
				p.hp += 25
			end
		else
			p.hp += 20
		end
		recalc()
		p.hp = min(p.hp, p.maxhp)
	end
	local function openLevelUp()
		if truthy(S.admNoPick) then
			S.pending = 0
			S.pickMode = "level"
			return
		end
		while S.pending > 0 do
			local ch = genChoices()
			if truthy(opts.demo) or opts.autoPick then
				local c
				if opts.autoPick then
					c = opts.autoPick(ch, S)
				else
					c = ch[floor(R() * #ch) + 1]
				end
				apply(c)
				S.pending -= 1
				if S.pending == 0 or S.pickMode == "start" then
					S.pickMode = "level"
				end
				continue
			end
			S.choices = ch
			S.state = "levelup"
			if S.pickMode ~= "start" then
				host.sfx(if S.pickMode == "chest" then "chest" else "level")
			end
			host.levelUp(ch, S.pickMode)
			return
		end
	end
	-- i 는 1부터 (원본은 0부터)
	local function choose(i: number)
		if S.state ~= "levelup" or not S.choices or not S.choices[i] then
			return
		end
		apply(S.choices[i])
		S.choices = nil
		S.pending -= 1
		S.state = "run"
		p.inv = max(p.inv, .7)
		if S.pending == 0 or S.pickMode == "start" then
			S.pickMode = "level"
		end
		if S.pending > 0 then
			openLevelUp()
		end
	end
	local function reroll(): boolean
		if S.state ~= "levelup" or S.rerolls <= 0 or S.pickMode == "start" then
			return false
		end
		S.rerolls -= 1
		S.choices = genChoices()
		host.levelUp(S.choices, S.pickMode)
		return true
	end
	local function dash(): boolean
		if S.state ~= "run" or p.dashCd > 0 then
			return false
		end
		local dx, dy = S.input.x, S.input.y
		local l = hypot(dx, dy)
		if l > .1 then
			dx /= l
			dy /= l
		else
			dx = p.fx
			dy = p.fy
		end
		p.ddx = dx
		p.ddy = dy
		p.dashT = .2
		p.dashCd = S.M.dashCd
		p.inv = max(p.inv, .34)
		S.dashes += 1
		host.sfx("dash")
		ev({ k = "dash", x = p.x, y = p.y })
		return true
	end

	---------------- 매 프레임 ----------------
	-- 하차 인파의 사방 탄막 (원본은 적 루프 안의 화살표 함수)
	local function volley(e, dx: number, dy: number, rg: number)
		local base = atan2(dy, dx)
		local sd = if R() < .5 then -1 else 1
		local g = base + sd * (.5 + R() * .9)
		local gw = .45 - .04 * rg
		for j = 0, 31 do
			local a = j / 32 * TAU
			local da = abs(angd(a - g))
			if da > gw then
				shoot(e.x, e.y, a, 120 + rg * 10, 13, 9, 6, 8)
			end
		end
		host.sfx("rumble", e.x)
	end
	-- 따로 움직이는 종류. 나머지(승객 · 인턴 · 학생 · 아저씨 · 캐리어)는 그냥 다가온다
	local SPECIAL = { zomb = true, runner = true, flyer = true, flyboss = true, doorman = true, carrierboss = true, bagman = true, crowd = true, speaker = true, lead = true }
	-- 적 (원본 update 의 "// enemies" 루프). t, k, cap 은 update 에서 넘겨받는다
	local function stepEnemies(dt: number, t: number, k: number, cap: number)
		local E = S.enemies
		local farR, zk, pcell = S.spawnR * 1.55, S.zk, floor(p.y / GATE_GAP)
		local px, py = p.x, p.y -- 이 루프 안에서는 플레이어가 움직이지 않는다
		local dec = exp(-7 * dt) -- 원본은 적마다 다시 계산한다(같은 값)
		for i = #E, 1, -1 do
			local e = E[i]
			if e.dead then
				local n = #E
				E[i] = E[n]
				E[n] = nil
				continue
			end
			e.anim += dt
			if e.flash > 0 then
				e.flash -= dt
			end
			if e.bpT > 0 then
				e.bpT -= dt
			end
			if e.shT > 0 then
				e.shT -= dt
			end
			if e.rzT > 0 then
				e.rzT -= dt
			end
			if e.sfT > 0 then
				e.sfT -= dt
			end
			if e.slow > 0 then
				e.slow -= dt
			else
				e.slowAmt = 0
			end
			local dx, dy = px - e.x, py - e.y
			local d = hypot(dx, dy)
			if d == 0 then
				d = 1
			end
			local nx, ny = dx / d, dy / d
			local mvx, mvy = 0, 0
			local isBoss = e.boss
			local rg = if isBoss then min(4, S.rage) else 0
			local bdt = if isBoss then dt * (1 + .12 * rg) else dt
			local ty = e.type
			if e.intro > 0 then
				e.intro -= dt
				if e.intro <= 0 then
					ev({ k = "bossland", x = e.x, y = e.y })
					host.shake(12)
					host.sfx("stamp")
					local L = if ty == "lead" then TALK.lead[1] else TALK[ty]
					say(e, if L then L[1] else "")
					host.sfx("voice", e.x, ty)
				end
				continue
			end
			if isBoss and TALK[ty] then
				e.sayT -= dt
				if e.sayT <= 0 then
					e.sayT = 6 + R() * 4
					local L
					if ty == "lead" then
						local day = e.day
						L = TALK.lead[(if day == day then day else 0) + 1]
					else
						L = TALK[ty]
					end
					say(e, L[floor(R() * #L) + 1])
					host.sfx("voice", e.x, ty)
				end
			end
			if e.stun > 0 then
				e.stun -= dt
				e.mv = false
			else
				e.mv = true
				local sp = e.spd * (if e.slow > 0 and not isBoss then 1 - e.slowAmt else 1) * (if isBoss then 1 + .1 * min(4, S.rage) else 1)
				if not SPECIAL[ty] then
					mvx = nx * sp
					mvy = ny * sp
				elseif ty == "zomb" then
					local f = sp / e.spd
					mvx = e.vx * f
					mvy = e.vy * f
				elseif ty == "runner" then
					if e.st == 0 then
						mvx = nx * sp
						mvy = ny * sp
						if d < 250 then
							e.st = 1
							e.tm = .5
							host.sfx("alert", e.x)
						end
					elseif e.st == 1 then
						e.mv = false
						e.tm -= dt
						if e.tm <= 0 then
							e.st = 2
							e.tm = .55
							e.dx = nx
							e.dy = ny
						end
					elseif e.st == 2 then
						mvx = e.dx * 360
						mvy = e.dy * 360
						e.tm -= dt
						if e.tm <= 0 then
							e.st = 3
							e.tm = .9
						end
					else
						mvx = nx * sp * .5
						mvy = ny * sp * .5
						e.tm -= dt
						if e.tm <= 0 then
							e.st = 0
						end
					end
				elseif ty == "flyer" then
					if d > 240 then
						mvx = nx * sp
						mvy = ny * sp
					elseif d < 160 then
						mvx = -nx * sp * .6
						mvy = -ny * sp * .6
					else
						local sd = if e.seed % 2 == 1 then 1 else -1
						mvx = -ny * sp * .5 * sd
						mvy = nx * sp * .5 * sd
					end
					e.tm -= dt
					if e.tm <= 0 then
						e.tm = 3 - k * .6
						if d < 420 then
							shoot(e.x, e.y - 8, atan2(dy, dx), 160 + k * 30, 8 * (1 + k * .5), 2, 3.2, 6)
							host.sfx("flick", e.x)
						end
					end
				elseif ty == "flyboss" then
					if d > 190 then
						mvx = nx * sp
						mvy = ny * sp
					elseif d < 100 then
						mvx = -nx * sp * .6
						mvy = -ny * sp * .6
					else
						mvx = -ny * sp * .5
						mvy = nx * sp * .5
					end
					e.tm -= bdt
					if e.tm <= 0 then
						e.tm = 2.6
						local a0 = atan2(dy, dx)
						for _, j in ipairs(if rg >= 1 then FLY_FAN3 else FLY_FAN2) do
							shoot(e.x, e.y - 8, a0 + j, 160 + rg * 12, 6, 2, 3.4, 6)
						end
						host.sfx("flick", e.x)
					end
					e.t2 -= bdt
					if e.t2 <= 0 then
						e.t2 = 9
						local n = if rg >= 2 then 6 else 4
						for j = 0, n - 1 do
							local a = j / n * TAU
							spawn(if rg >= 2 and j % 3 == 0 then "flyer" else "pass", e.x + cos(a) * 44, e.y + sin(a) * 44)
						end
						say(e, "여기요, 여기!")
					end
					e.t3 -= bdt
					if e.t3 <= 0 then
						e.t3 = 8
						local n, o = 6 + rg * 2, R() * TAU
						for j = 0, n - 1 do
							shoot(e.x, e.y - 8, o + j / n * TAU, 100, 5, 2, 3.6, 6)
						end
						say(e, "받으세요!!")
						host.sfx("paper", e.x)
					end
				elseif ty == "doorman" then
					mvx = nx * sp
					mvy = ny * sp
					e.tm -= bdt
					if e.tm <= 0 then
						e.tm = 3.6
						e.cc += 1
						table.insert(S.zones, { x = e.x + nx * 40, y = e.y + ny * 40, r = 120 + rg * 10, warn = .9, dur = .9, dmg = 22, txt = "비켜요", kind = "door" })
						host.sfx("stamp")
						say(e, "밀지 마요!")
						if rg >= 1 and e.cc % 2 == 0 then
							table.insert(S.waves, { x = e.x, y = e.y, r = e.r, spd = 190, max = 520, dmg = 14, gap = R() * TAU, gw = .7 - .06 * rg, hit = false, kind = "push" })
						end
					end
					e.t2 -= bdt
					if e.t2 <= 0 then
						e.t2 = 5
						local n = 6 + rg
						for j = 0, n - 1 do
							local a = j / n * TAU
							spawn(if j % 2 == 1 then "pass" else "stud", e.x + cos(a) * (e.r + 18), e.y + sin(a) * (e.r + 18))
						end
						host.sfx("boss2", e.x)
						say(e, "다들 이쪽으로 타요!")
					end
					e.t3 -= bdt
					if e.t3 <= 0 then
						e.t3 = 7.5
						local n = 4 + min(2, rg)
						for j = 0, n - 1 do
							table.insert(S.zones, { x = e.x + nx * (70 + j * 92), y = e.y + ny * (70 + j * 92), r = 60, warn = .75 + j * .16, dur = .75 + j * .16, dmg = 20, txt = "쿵", kind = "door" })
						end
						host.sfx("doorslam", e.x)
						say(e, "출입문 닫습니다!")
					end
				elseif ty == "carrierboss" then
					if e.st == 0 then
						mvx = nx * sp
						mvy = ny * sp
						e.t2 -= bdt
						if e.t2 <= 0 and d < 480 then
							e.st = 1
							e.t2 = .65
							e.dx = nx
							e.dy = ny
							e.cc = if rg >= 2 then 1 else 0
							host.sfx("alert", e.x)
							say(e, "비켜 주세요~!")
						end
						e.t3 -= bdt
						if e.t3 <= 0 and d < 520 then
							e.t3 = 6
							local a0, n = atan2(dy, dx), if rg >= 1 then 5 else 3
							for j = 0, n - 1 do
								local o = (j - (n - 1) / 2) * 56
								shoot(e.x - ny * o, e.y + nx * o, a0, 135 + rg * 10, 14, 8, 6, 13)
							end
							host.sfx("wheels", e.x)
							say(e, "어머, 굴러가네~")
						end
					elseif e.st == 1 then
						e.mv = false
						e.t2 -= bdt
						if e.t2 <= 0 then
							e.st = 2
							e.t2 = .9
							e.acc = 0
							host.sfx("wheels", e.x)
						end
					else
						mvx = e.dx * 400
						mvy = e.dy * 400
						e.t2 -= bdt
						e.acc += dt
						if e.acc >= .16 then
							e.acc = 0
							table.insert(S.slicks, { x = e.x, y = e.y, r = 34, life = 3, dur = 3 })
						end
						if e.t2 <= 0 then
							local o, n = R() * TAU, 10 + rg * 2
							for j = 0, n - 1 do
								shoot(e.x, e.y, o + j / n * TAU, 150, 11, 10)
							end
							host.shake(4)
							ev({ k = "crash", x = e.x, y = e.y })
							if e.cc > 0 then
								e.cc -= 1
								e.st = 1
								e.t2 = .45
								e.dx = nx
								e.dy = ny
								host.sfx("alert", e.x)
							else
								e.st = 0
								e.t2 = 3.4
							end
						end
					end
				elseif ty == "bagman" then
					if e.st == 0 then
						mvx = nx * sp
						mvy = ny * sp
						e.t3 -= bdt
						if e.t3 <= 0 and d < 210 then
							e.t3 = 6
							table.insert(S.zones, { x = e.x + nx * 30, y = e.y + ny * 30, r = 100 + rg * 8, warn = .7, dur = .6, dmg = 16, txt = "퍽", kind = "swat" })
							host.sfx("swing", e.x)
							say(e, "어, 뒤에 누구 있었어요?")
						end
						e.tm -= bdt
						if e.tm <= 0 and d < 270 then
							e.st = 3
							e.tm = .75
							host.sfx("alert", e.x)
							say(e, "어? 누가 불렀나?")
						else
							e.t2 -= bdt
							if e.t2 <= 0 and d < 460 then
								e.st = 1
								e.t2 = .65
								e.dx = nx
								e.dy = ny
								e.cc = if rg >= 1 then 1 else 0
								host.sfx("alert", e.x)
								say(e, "잠깐만요, 지나갈게요!")
							end
						end
					elseif e.st == 1 then
						e.mv = false
						e.t2 -= bdt
						if e.t2 <= 0 then
							e.st = 2
							e.t2 = .8
						end
					elseif e.st == 2 then
						mvx = e.dx * 450
						mvy = e.dy * 450
						e.t2 -= bdt
						if e.t2 <= 0 then
							if e.cc > 0 then
								e.cc -= 1
								e.st = 1
								e.t2 = .4
								e.dx = nx
								e.dy = ny
								host.sfx("alert", e.x)
							else
								e.st = 0
								e.t2 = 5.5
							end
						end
					elseif e.st == 3 then
						e.mv = false
						e.tm -= bdt
						if e.tm <= 0 then
							e.st = 4
							e.tm = 1.1
							e.acc = 0
							host.sfx("spin", e.x)
						end
					else
						mvx = nx * sp * 1.3
						mvy = ny * sp * 1.3
						e.tm -= bdt
						e.acc += bdt
						if d < SPIN_R + p.r and p.inv <= 0 then
							hurt(20, false, "spin")
						end
						if e.acc >= .18 then
							e.acc = 0
							e.ang += .7
							local n = if rg >= 2 then 6 else 4
							for j = 0, n - 1 do
								shoot(e.x, e.y, e.ang + j * TAU / n, 150, 10, 5)
							end
						end
						if e.tm <= 0 then
							e.st = 0
							e.tm = 3.6
							local o = R() * TAU
							for j = 0, 7 do
								shoot(e.x, e.y, o + j / 8 * TAU, 110, 9, 5, 3.5)
							end
							host.sfx("zipper", e.x)
						end
					end
				elseif ty == "crowd" then
					mvx = nx * sp
					mvy = ny * sp
					e.tm -= bdt
					if e.tm <= 0 then
						e.tm = 3.2
						if #E < cap + 50 then
							for j = 0, 9 do
								local a = j / 10 * TAU
								spawn(if j % 3 ~= 0 then "pass" else "stud", e.x + cos(a) * (e.r + 18), e.y + sin(a) * (e.r + 18))
							end
						end
						host.sfx("boss2", e.x)
					end
					e.t2 -= bdt
					if e.t2 <= 0 then
						e.t2 = 5
						volley(e, dx, dy, rg)
						say(e, "우르르르!")
						if rg >= 2 then
							e.pend = .7
						end
					end
					if e.pend > 0 then
						e.pend -= dt
						if e.pend <= 0 then
							volley(e, dx, dy, rg)
						end
					end
					e.t3 -= bdt
					if e.t3 <= 0 then
						e.t3 = 9 - rg
						zombieRow()
						say(e, "환승합니다, 비켜요!")
						host.sfx("rumble", e.x)
					end
				elseif ty == "speaker" then
					local rage = (if e.hp < e.maxhp * .5 then 1.4 else 1) * (1 + .12 * rg)
					if zk == "train" then
						if d > 430 then
							mvx = nx * sp
							mvy = ny * sp
						elseif d < 310 then
							mvx = -sign(if dx ~= 0 then dx else 1) * sp * 1.2
						else
							mvy = sin(t * 1.7) * sp * .5
						end
					elseif d > 310 then
						mvx = nx * sp
						mvy = ny * sp
					elseif d < 190 then
						mvx = -nx * sp * .7
						mvy = -ny * sp * .7
					else
						mvx = -ny * sp * .6
						mvy = nx * sp * .6
					end
					e.tm -= bdt * rage
					if e.st == 0 then
						e.acc += bdt * rage
						if zk == "train" then
							if e.tm > 1 then
								e.tm = 1
							end
						elseif e.acc >= .6 and e.t2 < (if rage > 1 then 4 else 3) then
							e.acc = 0
							e.t2 += 1
							-- (원본에는 여기에도 열차용 가지가 있지만 열차 안에서는 이 줄에 오지 않는다)
							local gap
							if zk == "train" then
								--@unreachable-begin 바로 위의 `if zk == "train"` 때문에 열차 안에서는 이 가지에 오지 않는다 (원본 그대로)
								local base = atan2(dy, dx)
								local sd = if R() < .5 then -1 else 1
								gap = base + sd * (.62 + R() * .1)
								--@unreachable-end
							else
								gap = R() * TAU
							end
							table.insert(S.waves, { x = e.x, y = e.y, r = e.r, spd = if rage > 1 then 250 else 210, max = 640, dmg = 15, gap = gap, gw = .55, hit = false })
							host.sfx("wave", e.x)
						end
						if e.tm <= 0 then
							e.st = 1
							e.tm = 1
						end
					elseif e.st == 1 then
						if e.tm <= 0 then
							e.st = 2
							e.tm = 1.9
							e.acc = 0
							e.t2 = 0
							say(e, "이 노래 아세요?")
						end
					elseif e.st == 2 then
						e.acc += bdt * rage
						if e.acc >= (if zk == "train" then .3 else .42) and e.t2 < (if zk == "train" then 5 else 4) then
							e.acc = 0
							e.t2 += 1
							local a0 = atan2(dy, dx) + (if e.t2 % 2 == 1 then .1 else -.1)
							if zk == "train" then
								shoot(e.x, e.y, atan2(dy, dx), 175, 9, 6, 4.5)
							else
								for j = -2, 2 do
									shoot(e.x, e.y, a0 + j * .2, 205, 12, 6, 4)
								end
							end
							host.sfx("note", e.x)
						end
						if e.tm <= 0 then
							e.st = 3
							e.tm = .8
						end
					elseif e.st == 3 then
						if e.tm <= 0 then
							e.st = 4
							e.tm = 1.5
							e.acc = 0
							e.t2 = 0
							say(e, "베이스 갑니다!")
							host.sfx("bass", e.x)
						end
					elseif e.st == 4 then
						e.acc += bdt * rage
						if e.acc >= .3 and e.t2 < (if zk == "train" then 2 elseif rage > 1 then 5 else 3) then
							e.acc = 0
							e.t2 += 1
							local a = R() * TAU
							local o = if e.t2 == 1 then 0 else R() * 90
							table.insert(S.zones, { x = p.x + cos(a) * o, y = p.y + sin(a) * o, r = if zk == "train" then 60 else 78, warn = .95, dur = .95, dmg = 26, txt = "쿵", kind = "bass" })
							host.sfx("stamp")
						end
						if e.tm <= 0 then
							e.st = 5
							e.tm = 1
						end
					else
						if e.tm <= 0 then
							e.st = 0
							e.tm = 2.6
							e.acc = .6
							e.t2 = 0
						end
					end
				else -- lead (김 팀장)
					e.age = (e.age or 0) + dt
					local day = min(4, max(floor((1 - e.hp / e.maxhp) * 5), floor(e.age / 9)))
					if day > e.day then
						e.day = day
						e.label = "김 팀장 · " .. PHASES[day + 1]
						host.banner(PHASES[day + 1], DAY_LINE[day + 1], "boss")
						host.sfx("page", e.x)
						ev({ k = "page", x = e.x, y = e.y })
						host.shake(8)
						table.clear(S.bullets)
						say(e, TALK.lead[day + 1][1])
						e.sayT = 5
					end
					local f = if day >= 4 then 1.45 else 1
					if e.st == 1 then
						e.mv = false
						e.t2 -= bdt
						if e.t2 <= 0 then
							e.st = 2
							e.t2 = .7
						end
					elseif e.st == 2 then
						mvx = e.dx * 560
						mvy = e.dy * 560
						e.t2 -= bdt
						if e.t2 <= 0 then
							e.st = 0
							e.t2 = 3.2
						end
					else
						mvx = nx * sp * f
						mvy = ny * sp * f
						if day >= 4 then
							e.t2 -= bdt
							if e.t2 <= 0 and d < 520 then
								e.st = 1
								e.t2 = .8
								e.dx = nx
								e.dy = ny
								host.sfx("warn")
								say(e, "거기 서!")
							end
						end
					end
					-- 서류: 한 바퀴 탄막과 도는 나선을 번갈아
					e.tm -= bdt * f
					if e.tm <= 0 then
						e.tm = 2.6
						e.cc += 1
						e.ang += .2
						local n = 16 + rg * 3
						if e.cc % 2 == 1 then
							for j = 0, n - 1 do
								shoot(e.x, e.y, e.ang + j / n * TAU, 150, 12, 7)
							end
						else
							for j = 0, n - 1 do
								shoot(e.x, e.y, e.ang + j * .42, 120 + j * 7, 12, 7)
							end
						end
						host.sfx("paper", e.x)
					end
					-- 결재 도장: 서 있는 자리를 따라온다
					e.stp -= bdt * f
					if e.stp <= 0 then
						e.stp = 6.5
						e.sq = 4 + min(3, rg)
						e.acc = 0
						say(e, "결재 올려!")
					end
					if e.sq > 0 then
						e.acc -= dt
						if e.acc <= 0 then
							e.acc = .34
							e.sq -= 1
							table.insert(S.zones, { x = p.x, y = p.y, r = 56, warn = .8, dur = .8, dmg = 24, txt = "결재", kind = "stamp" })
							host.sfx("stamp")
						end
					end
					if day >= 1 then
						e.fan -= bdt * f
						if e.fan <= 0 then
							e.fan = 3
							local a0, h = atan2(dy, dx), 3 + min(2, rg)
							for j = -h, h do
								shoot(e.x, e.y, a0 + j * .15, 210, 12, 3, 4)
							end
							host.sfx("flick", e.x)
							say(e, "이것도, 이것도!")
						end
					end
					if day >= 2 then
						e.z -= bdt * f
						if e.z <= 0 then
							e.z = 4.5
							local n = 3 + min(3, rg)
							for j = 0, n - 1 do
								local a = R() * TAU
								local o = if j ~= 0 then 40 + R() * 90 else 0
								table.insert(S.zones, { x = p.x + cos(a) * o, y = p.y + sin(a) * o, r = 74, warn = 1, dur = 1, dmg = 26, txt = "잔소리", kind = "nag" })
							end
							local base = atan2(dy, dx)
							local sd = if R() < .5 then -1 else 1
							local gap = base + sd * (.7 + R() * .5)
							table.insert(S.waves, { x = e.x, y = e.y, r = e.r, spd = 200 + rg * 15, max = 600, dmg = 16, gap = gap, gw = .6 - .05 * rg, hit = false, kind = "nag" })
							host.sfx("nag", e.x)
							say(e, "내가 자네 때는 말이야!")
						end
					end
					if day >= 3 then
						e.row -= bdt * f
						if e.row <= 0 then
							e.row = 6.5
							zombieRow()
							local n = 8
							for j = 0, n - 1 do
								local a = j / n * TAU
								table.insert(S.zones, { x = p.x + cos(a) * 170, y = p.y + sin(a) * 170, r = 52, warn = 1.1, dur = 1.1, dmg = 22, txt = "회의", kind = "meet" })
							end
							host.sfx("phone", e.x)
							say(e, "전원 회의실로!")
						end
					end
				end
			end
			-- 개찰구: 플레이어와 다른 칸에 있으면 틈을 찾아 지나간다
			if zk == "gates" and not isBoss and e.r <= 20 and e.stun <= 0 and (ty ~= "runner" or e.st == 0 or e.st == 3) then
				local ce = floor(e.y / GATE_GAP)
				if ce ~= pcell then
					local ry = (if ce < pcell then ce + 1 else ce) * GATE_GAP
					local dyr = ry - e.y
					if abs(dyr) < 70 then
						local lx = round(e.x / GATE_PER) * GATE_PER - e.x
						local lim = GATE_HALF - e.r - 1
						local sp = hypot(mvx, mvy)
						if sp == 0 then
							sp = e.spd
						end
						if abs(lx) > lim then
							mvx = sign(lx) * sp
							mvy = if abs(dyr) > GATE_TH + e.r + 5 then sign(dyr) * sp * .35 else 0
						else
							mvx = lx * 5
							mvy = (if ce < pcell then 1 else -1) * sp
						end
					end
				end
			end
			-- 열차 문으로 타는 중
			if e.board > 0 then
				e.board -= dt
				mvx *= .15
				mvy = -sign(e.y) * max(150, e.spd * 2.4)
				if abs(e.y) < AISLE - 16 then
					e.board = 0
					e.ky = -sign(e.y) * 120
				end
			end
			e.x += (mvx + e.kx) * dt
			e.y += (mvy + e.ky) * dt
			if zk == "gates" then
				if not isBoss and e.r <= 20 then
					gateSolve(e, e.r)
				end
			elseif zk == "train" then
				if not (e.board > 0) and (not isBoss or ty == "speaker") then
					local lim = AISLE - min(e.r, 30)
					if e.y > lim then
						e.y = lim
					elseif e.y < -lim then
						e.y = -lim
					end
				end
			elseif zk == "esc" and not isBoss then
				local c = floor(e.x / ESC_W) % 3
				if c ~= 1 then
					e.y += (if c == 0 then -1 else 1) * ESC_PUSH * dt
				end
			end
			e.kx *= dec
			e.ky *= dec
			local far
			if zk == "train" then
				far = abs(dx) > S.spawnX * 1.7
			else
				far = d > farR
			end
			if far then
				if ty == "zomb" then
					if e.vx * dx + e.vy * dy < 0 then
						e.dead = true
						local n = #E
						E[i] = E[n]
						E[n] = nil
					end
				else
					local qx, qy = spawnPos()
					e.x = qx
					e.y = qy
					e.kx = 0
					e.ky = 0
				end
			end
		end
	end
	-- 서로 겹친 적을 밀어낸다 (보스 제외)
	local function separate()
		local E = S.enemies
		local g = grid
		for i = 1, #E do
			local e = E[i]
			if not e.boss then
				-- e 의 자리는 지역 변수에 들고 있다가 밀릴 때마다 표에도 적는다 (이 안에서 e 를 고치는 것은 e 자신뿐)
				local ex, ey, er, eid = e.x, e.y, e.r, e.id
				local cx, cy = floor(ex / CELL), floor(ey / CELL)
				for ax = cx - 1, cx + 1 do
					local kx = (ax + 32768) * 65536 + 32768
					for ay = cy - 1, cy + 1 do
						local a = g[kx + ay]
						if a then
							for j = 1, #a do
								local o = a[j]
								if not (o.id <= eid or o.boss) then
									local ox, oy = o.x, o.y
									local dx, dy, rr = ox - ex, oy - ey, er + o.r
									local d2 = dx * dx + dy * dy
									if d2 < rr * rr and d2 > .0001 then
										local d = sqrt(d2)
										local push = (rr - d) * .25
										local nx, ny = dx / d, dy / d
										ex -= nx * push
										ey -= ny * push
										e.x = ex
										e.y = ey
										o.x = ox + nx * push
										o.y = oy + ny * push
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local function update(dt: number, view: any?)
		if S.state ~= "run" then
			return
		end
		if S.pending > 0 then
			openLevelUp()
			if S.state ~= "run" then
				return
			end
		end
		S.t += dt
		local t, M, k = S.t, S.M, q()
		if view then
			S.spawnR = hypot(view.w, view.h) / 2 + 50
			S.spawnX = view.w / 2 + 70
		end
		if not S.started then
			enterZone(S.zone)
		end
		S.zt += dt
		do
			local G = GATE[ZONES[S.zone + 1].key]
			local phase = S.phase
			if phase == "crowd" then
				if G.crowd and S.zt >= G.crowd then
					boss(G.boss)
					S.phase = "boss"
					S.rage = 0
					S.rageT = D.enrage
				end
			elseif phase == "boss" then
				S.rageT -= dt
				if S.rageT <= 0 then
					S.rage += 1
					S.rageT = ENRAGE_STEP
					local g = S.gate
					if g then
						g.dmg *= 1.08
						say(g, RAGE_TALK[g.type])
						g.sayT = 5
						host.sfx("roar", g.x)
					end
					host.banner("폭주 " .. S.rage .. "단계", "진상의 기술이 강해지고 인파가 더 몰려듭니다", "warn")
					host.sfx("warn")
					ring(8 + S.rage * 4, true)
				end
			elseif phase == "clear" then
				S.clearT -= dt
				if S.clearT <= 0 then
					if S.zone == #ZONES - 1 then
						S.late = S.t > GAME_LEN
						S.state = "won"
						host.finish(true)
						return
					end
					enterZone(S.zone + 1)
				end
			elseif phase == "ride" then
				if not S.optDone and S.zt >= 46 then
					S.optDone = true
					boss(G.opt)
				end
				if G.ride and S.zt >= G.ride then
					enterZone(S.zone + 1)
				end
			end
		end

		-- 미끄러운 바닥은 플레이어에게도 듣는다
		p.slow = 0
		do
			local Sl = S.slicks
			for i = #Sl, 1, -1 do
				local s = Sl[i]
				s.life -= dt
				if s.life <= 0 then
					table.remove(Sl, i)
					continue
				end
				local dx, dy = p.x - s.x, p.y - s.y
				if dx * dx + dy * dy < s.r * s.r then
					p.slow = .45
				end
			end
		end
		if p.slow > 0 and not S.wasSlow then
			host.sfx("slip")
		end
		S.wasSlow = p.slow > 0
		if GAME_LEN - S.t <= 10 and GAME_LEN > S.t then
			local n = ceil(GAME_LEN - S.t)
			if n ~= S.lastTick and n > 0 then
				S.lastTick = n
				host.sfx("tick", nil, n)
			end
		end
		-- 플레이어
		do
			local ix, iy = S.input.x, S.input.y
			local il = hypot(ix, iy)
			p.moving = il > .05
			if p.dashCd > 0 then
				p.dashCd -= dt
				if p.dashCd <= 0 then
					host.sfx("dashready")
				end
			end
			if p.dashT > 0 then
				p.dashT -= dt
				p.x += p.ddx * 640 * dt
				p.y += p.ddy * 640 * dt
				p.fx = p.ddx
				p.fy = p.ddy
				p.inv = max(p.inv, .12)
				p.anim += dt * 2
			elseif p.moving then
				if il > 1 then
					ix /= il
					iy /= il
				end
				local sp = 152 * M.speed * (1 - p.slow)
				p.x += ix * sp * dt
				p.y += iy * sp * dt
				local n = hypot(ix, iy)
				if n == 0 then
					n = 1
				end
				p.fx = ix / n
				p.fy = iy / n
				p.anim += dt
			end
		end
		if S.zk == "gates" then
			gateSolve(p, p.r)
		elseif S.zk == "train" then
			if S.pvx ~= 0 then
				p.x += S.pvx * dt
				S.pvx *= exp(-5 * dt)
				if abs(S.pvx) < 2 then
					S.pvx = 0
				end
			end
			p.y = max(-AISLE + p.r, min(AISLE - p.r, p.y))
		elseif S.zk == "esc" and p.dashT <= 0 then
			local c = floor(p.x / ESC_W) % 3
			if c ~= 1 then
				p.y += (if c == 0 then -1 else 1) * ESC_PUSH * dt
			end
		end
		if p.inv > 0 then
			p.inv -= dt
		end
		if M.regen ~= 0 and p.hp < p.maxhp then
			p.hp = min(p.maxhp, p.hp + M.regen * dt)
		end

		-- 적 생성
		local zdens = ZONES[S.zone + 1].dens
		local dens = (if zdens and zdens ~= 0 then zdens else 1) * D.crowd
		local cap = (150 + t * .55) * dens
		local rate = if S.phase == "clear" then 0 else (1.8 + 12 * k + 13 * k * k) * (1 + .3 * S.rage) * dens * (if S.admRate == nil then 1 else S.admRate)
		S.spawnAcc += rate * dt
		while S.spawnAcc >= 1 do
			S.spawnAcc -= 1
			if #S.enemies < cap then
				local qx, qy = spawnPos()
				spawn(pickType(t), qx, qy)
			end
		end
		if t >= S.nextRow and S.phase ~= "clear" then
			S.nextRow = t + (if t > 300 then 15 else 20)
			zombieRow()
			if t > 420 then
				zombieRow()
			end
		end
		if t >= S.nextElite and S.phase ~= "clear" then
			S.nextElite = t + (if t > 360 then 20 else 28) * D.elite
			spawnElite()
		end

		-- 열차 안: 역마다 문이 열리고 인파가 탄다
		if S.zk == "train" then
			if S.stopIdx < #STOPS and S.zt >= GATE.train.ride / 5 * (S.stopIdx + 1) then
				local st = STOPS[S.stopIdx + 1]
				S.stopIdx += 1
				S.doorT = DOOR_OPEN
				S.doorAcc = 0
				S.side = -S.side
				S.pvx = 150
				for _, e in ipairs(S.enemies) do
					if not e.boss then
						e.kx += 170
					end
				end
				if S.stopIdx >= 3 then
					S.song = 3
				end
				host.banner("이번 역은 " .. st.name, "문이 열립니다. 닫힐 때까지 버티세요", "station")
				host.sfx("station")
				host.shake(5)
				ev({ k = "doors", open = 1 })
			end
			if S.doorT > 0 then
				S.doorT -= dt
				-- 가까운 문마다 사람들이 몰아쳐 들어오고, 문 앞에 선 사람을 밀어낸다
				local surge = .55 + .45 * sin((DOOR_OPEN - S.doorT) * 2.4)
				S.doorAcc += dt * (DOOR_RATE[1] + DOOR_RATE[2] * k) * D.crowd * (if S.doorT > DOOR_OPEN - 1.2 then 2.2 else 1) * surge * 2
				while S.doorAcc >= 1 do
					S.doorAcc -= 1
					if #S.enemies < cap + 70 then
						local dx = round((p.x + (R() * 2 - 1) * 470 - 160) / DOOR_PER) * DOOR_PER + 160
						local sd = if R() < .5 then -1 else 1
						local ty = pickType(t)
						if ty == "zomb" or ty == "carrier" then
							ty = "pass"
						end
						local ex = dx + (R() - .5) * 40
						local ey = sd * (AISLE + 62 + R() * 70)
						local e = spawn(ty, ex, ey)
						e.board = 1.6
					end
				end
				do
					local ox = fmod(fmod(p.x - 160, DOOR_PER) + DOOR_PER * 1.5, DOOR_PER) - DOOR_PER / 2
					if abs(ox) < 48 and abs(p.y) > AISLE - 46 and p.dashT <= 0 then
						p.y -= sign(p.y) * 150 * dt
					end
				end
				if S.doorT <= 0 then
					S.pvx = -130
					for _, e in ipairs(S.enemies) do
						if not e.boss then
							e.kx -= 150
						end
					end
					host.sfx("doorclose")
					ev({ k = "doors", open = 0 })
				end
			end
		end
		-- 차선 위험: 거리의 버스, 승강장의 열차
		local hz = ZONES[S.zone + 1].hazard
		S.trainT -= dt
		if hz and not S.train and S.trainT <= 0 then
			local ln, bus = round(p.y / LANE_GAP), hz == "bus"
			S.train = { kind = hz, len = if bus then 560 else TRAIN_LEN, spd = if bus then 1150 else TRAIN_SPD, y = ln * LANE_GAP, dir = if R() < .5 then 1 else -1, warn = 1.5, on = false, x = 0, hitP = false, hit = {} }
			host.sfx(if bus then "buswarn" else "trainwarn")
			if not S.seen[hz] then
				S.seen[hz] = 1
				host.banner(if bus then "버스가 옵니다" else "열차가 들어옵니다", (if bus then "차도" else "선로") .. " 밖으로 물러나세요. 인파는 치고 지나갑니다", "warn")
			end
			S.trainT = ((if bus then 10 else 13 - 7 * k) + R() * 3) * D.hazard
		end
		if S.train then
			local T = S.train
			if not T.on then
				T.warn -= dt
				if T.warn <= 0 then
					T.on = true
					T.x = p.x - T.dir * (S.spawnR + 60)
					host.sfx(if T.kind == "bus" then "buspass" else "trainpass")
					if abs(p.y - T.y) < S.spawnR then
						host.shake(9)
					end
				end
			else
				T.x += T.dir * T.spd * dt
				local tail = T.x - T.dir * T.len
				local lo, hi, E = min(T.x, tail), max(T.x, tail), S.enemies
				for i = 1, #E do
					local e = E[i]
					if not (e.dead or e.x < lo or e.x > hi or abs(e.y - T.y) > LANE_H + e.r * .4) then
						if e.boss or e.elite then
							if not T.hit[e.id] then
								T.hit[e.id] = 1
								local d = if e.boss then 350 else e.maxhp * .6
								e.hp -= d
								e.flash = .15
								ev({ k = "num", x = e.x, y = e.y - e.r - 8, v = d, crit = true })
								addDmg("train", d)
								if e.hp <= 0 then
									kill(e, "train")
								end
							end
						else
							e.kx = T.dir * 700
							e.ky = (if e.y >= T.y then 1 else -1) * 260
							addDmg("train", e.hp)
							kill(e, "train")
						end
					end
				end
				if p.x > lo and p.x < hi and abs(p.y - T.y) < LANE_H + 4 then
					if not T.hitP then
						T.hitP = true
						hurt(45, true, "train")
						ev({ k = "trainhit", x = p.x, y = p.y })
					end
					p.y = T.y + (if p.y >= T.y then 1 else -1) * (LANE_H + p.r + 8)
					p.dashT = 0
				end
				if (T.dir > 0 and tail > p.x + S.spawnR + 120) or (T.dir < 0 and tail < p.x - S.spawnR - 120) then
					S.train = nil
				end
			end
			if S.state ~= "run" then
				return
			end
		end

		-- 적
		local zk = S.zk
		stepEnemies(dt, t, k, cap)
		buildGrid()
		separate()

		weapons(dt)

		-- 던진 커피 · 알람 시계
		do
			local lobs = S.lobs
			for i = #lobs, 1, -1 do
				local b = lobs[i]
				b.t += dt
				if b.t >= b.dur and b.kind == "alarm" then
					table.insert(S.mines, { x = b.x1, y = b.y1, fuse = .6, dur = .6, r = b.r, dmg = b.dmg, stun = b.stun, rings = b.rings, evo = b.evo })
					table.remove(lobs, i)
					continue
				end
				if b.t >= b.dur then
					table.insert(S.puddles, { x = b.x1, y = b.y1, r = b.r, life = b.life, dur = b.life, tick = 0, dmg = b.dmg, slow = b.slow, evo = b.evo, ph = R() * TAU })
					ev({ k = "splash", x = b.x1, y = b.y1, r = b.r, evo = b.evo })
					host.sfx("splash", b.x1, b.evo)
					if truthy(S.fus.routine) then
						query(b.x1, b.y1, b.r, function(e)
							local dx, dy = e.x - b.x1, e.y - b.y1
							if dx * dx + dy * dy < b.r * b.r then
								if not e.boss then
									e.stun = max(e.stun, .5)
								end
								hit(e, 36, 0, 0, "alarm")
							end
						end)
						ev({ k = "alarmboom", x = b.x1, y = b.y1, r = b.r, evo = true })
						host.sfx("alarmboom", b.x1)
					end
					table.remove(lobs, i)
				end
			end
		end
		-- 알람 시계 · 커피 시한폭탄
		do
			local mines = S.mines
			for i = #mines, 1, -1 do
				local m = mines[i]
				m.fuse -= dt
				if m.fuse <= 0 then
					query(m.x, m.y, m.r, function(e)
						local dx, dy = e.x - m.x, e.y - m.y
						local d = hypot(dx, dy)
						if d == 0 then
							d = 1
						end
						if d < m.r + e.r * .5 then
							if not e.boss then
								e.stun = max(e.stun, if e.elite then m.stun * .5 else m.stun)
							end
							hit(e, m.dmg, dx / d * 150, dy / d * 150, if m.tb then "routine" else "alarm")
						end
					end)
					ev({ k = "alarmboom", x = m.x, y = m.y, r = m.r, evo = m.evo })
					host.sfx("alarmboom", m.x)
					m.rings -= 1
					if m.tb then
						if m.rings > 0 then
							m.dur = .55
							m.fuse = .55
							m.again = true
						else
							table.insert(S.puddles, { x = m.x, y = m.y, r = m.r * .85, life = 4.5, dur = 4.5, tick = 0, dmg = 14.4, slow = .5, evo = true, src = "routine", ph = R() * TAU })
							ev({ k = "splash", x = m.x, y = m.y, r = m.r * .85, evo = true })
							host.sfx("splash", m.x, true)
							table.remove(mines, i)
						end
					elseif m.rings > 0 then
						m.dur = .55
						m.fuse = .55
					else
						if truthy(S.fus.routine) then
							table.insert(S.puddles, { x = m.x, y = m.y, r = m.r * .8, life = 5, dur = 5, tick = 0, dmg = 15, slow = .5, evo = true, ph = R() * TAU })
							ev({ k = "fcast", t = "routine", r = m.r, x = m.x, y = m.y })
						end
						table.remove(mines, i)
					end
				end
			end
		end
		-- 킥보드
		do
			local riders = S.riders
			for i = #riders, 1, -1 do
				local r, st = riders[i], 900 * dt
				r.x += r.dx * st
				r.y += r.dy * st
				r.dist += st
				query(r.x, r.y, r.w, function(e)
					if table.find(r.hits, e.id) then
						return
					end
					local ex, ey, rr = e.x - r.x, e.y - r.y, e.r + r.w
					if ex * ex + ey * ey < rr * rr then
						table.insert(r.hits, e.id)
						local sd = if (ex * -r.dy + ey * r.dx) >= 0 then 1 else -1
						hit(e, r.dmg, -r.dy * sd * 170 + r.dx * 60, r.dx * sd * 170 + r.dy * 60, "scooter")
					end
				end)
				if r.dist > r.max then
					table.remove(riders, i)
				end
			end
		end
		-- 돌아오는 손잡이
		do
			local rangs = S.rangs
			for i = #rangs, 1, -1 do
				local b = rangs[i]
				b.t += dt
				if b.ph == 0 then
					local dc = exp(-3.2 * dt)
					b.vx *= dc
					b.vy *= dc
					if b.vx * b.vx + b.vy * b.vy < 90 * 90 then
						b.ph = 1
						table.clear(b.hits)
						b.sp = 90
					end
				else
					local dx, dy = p.x - b.x, p.y - b.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					b.sp = min(720, b.sp + 1500 * dt)
					b.vx = dx / d * b.sp
					b.vy = dy / d * b.sp
					if d < 20 or b.t > 3 then
						if truthy(S.fus.freepass) and d < 20 then
							local o = R() * TAU
							for kk = 0, 5 do
								local a = o + kk * TAU / 6
								table.insert(S.shots, { x = p.x, y = p.y, vx = cos(a) * 480, vy = sin(a) * 480, life = 1.2, dmg = 30, pierce = 3, hits = {}, evo = true, a = a })
							end
							ev({ k = "fcast", t = "freepass", r = 70 })
							host.sfx("card", nil, true)
						end
						table.remove(rangs, i)
						continue
					end
				end
				b.x += b.vx * dt
				b.y += b.vy * dt
				query(b.x, b.y, b.size, function(e)
					if table.find(b.hits, e.id) then
						return
					end
					local ex, ey, rr = e.x - b.x, e.y - b.y, e.r + b.size
					if ex * ex + ey * ey < rr * rr then
						table.insert(b.hits, e.id)
						hit(e, b.dmg, b.vx * .15, b.vy * .15, "handle")
					end
				end)
			end
		end
		-- 카드
		do
			local Sh = S.shots
			for i = #Sh, 1, -1 do
				local s = Sh[i]
				s.x += s.vx * dt
				s.y += s.vy * dt
				s.life -= dt
				s.a += dt * 16
				if s.life > 0 and s.pierce > 0 then
					query(s.x, s.y, 8, function(e)
						if s.pierce <= 0 or table.find(s.hits, e.id) then
							return
						end
						local dx, dy, rr = e.x - s.x, e.y - s.y, e.r + 8
						if dx * dx + dy * dy < rr * rr then
							table.insert(s.hits, e.id)
							s.pierce -= 1
							hit(e, s.dmg, s.vx * .2, s.vy * .2, "card")
							-- 프리패스: 카드가 가까운 다음 사람에게 갈아탄다
							if truthy(S.fus.freepass) then
								if s.bn == nil then
									s.bn = 5
								end
								if s.bn > 0 then
									local nx, nd = nil, 280 * 280
									query(s.x, s.y, 280, function(o)
										if o.dead or table.find(s.hits, o.id) then
											return
										end
										local ox, oy = o.x - s.x, o.y - s.y
										local d2 = ox * ox + oy * oy
										if d2 < nd then
											nd = d2
											nx = o
										end
									end)
									if nx then
										s.bn -= 1
										s.pierce += 1
										local sp = hypot(s.vx, s.vy)
										local d = sqrt(nd)
										if d == 0 then
											d = 1
										end
										s.vx = (nx.x - s.x) / d * sp
										s.vy = (nx.y - s.y) / d * sp
										s.life = max(s.life, .7)
										ev({ k = "transfer", x = s.x, y = s.y, tx = nx.x, ty = nx.y })
									end
								end
							end
						end
					end)
				end
				if s.life <= 0 or s.pierce <= 0 then
					local n = #Sh
					Sh[i] = Sh[n]
					Sh[n] = nil
				end
			end
		end
		-- 웅덩이 · 껌
		do
			local Pd = S.puddles
			for i = #Pd, 1, -1 do
				local u = Pd[i]
				u.life -= dt
				u.tick -= dt
				if u.tick <= 0 then
					u.tick = .4
					query(u.x, u.y, u.r, function(e)
						local dx, dy, rr = e.x - u.x, e.y - u.y, u.r + e.r * .5
						if dx * dx + dy * dy < rr * rr then
							e.slow = .6
							e.slowAmt = max(e.slowAmt, u.slow)
							hit(e, u.dmg, 0, 0, u.src or (if u.gum then "gum" else "coffee"))
						end
					end)
				end
				if u.life <= 0 then
					local n = #Pd
					Pd[i] = Pd[n]
					Pd[n] = nil
				end
			end
		end
		-- 적의 탄
		do
			local Bl = S.bullets
			for i = #Bl, 1, -1 do
				local b = Bl[i]
				b.x += b.vx * dt
				b.y += b.vy * dt
				b.life -= dt
				b.a += dt * 5
				local dx, dy, rr = b.x - p.x, b.y - p.y, b.r + p.r - 3
				local gone = b.life <= 0
				if not gone and dx * dx + dy * dy < rr * rr and p.inv <= 0 then
					hurt(b.dmg, false, "bullet" .. b.kind)
					gone = true
				end
				if gone then
					local n = #Bl
					Bl[i] = Bl[n]
					Bl[n] = nil
				end
			end
		end
		if S.state ~= "run" then
			return
		end
		-- 음파 고리: 틈에 서 있거나 대시로 지나가지 않으면 맞는다
		do
			local waves = S.waves
			for i = #waves, 1, -1 do
				local w = waves[i]
				w.r += w.spd * dt
				if not w.hit and p.inv <= 0 then
					local dx, dy = p.x - w.x, p.y - w.y
					local dd = hypot(dx, dy)
					if abs(dd - w.r) < 9 + p.r * .5 then
						local da = abs(angd(atan2(dy, dx) - w.gap))
						if da > w.gw then
							w.hit = true
							hurt(w.dmg, false, "wave")
						end
					end
				end
				if w.r > w.max then
					table.remove(waves, i)
				end
			end
		end
		if S.state ~= "run" then
			return
		end
		-- 예고 뒤에 찍히는 자리
		do
			local zones = S.zones
			for i = #zones, 1, -1 do
				local z = zones[i]
				z.warn -= dt
				if z.warn <= 0 then
					local dx, dy = p.x - z.x, p.y - z.y
					if dx * dx + dy * dy < (z.r + p.r * .5) * (z.r + p.r * .5) then
						hurt(z.dmg, false, "zone")
					end
					ev({ k = "boom", x = z.x, y = z.y, r = z.r, txt = z.txt, kind = z.kind })
					host.sfx("boom", z.x)
					host.shake(5)
					table.remove(zones, i)
				end
			end
		end
		if S.state ~= "run" then
			return
		end
		-- 몸에 닿음
		if p.inv <= 0 then
			local worst = 0
			query(p.x, p.y, p.r, function(e)
				local dx, dy, rr = e.x - p.x, e.y - p.y, e.r + p.r - 3
				if dx * dx + dy * dy < rr * rr and e.dmg > worst then
					worst = e.dmg
				end
			end)
			if worst ~= 0 then
				hurt(worst)
			end
		end
		if S.state ~= "run" then
			return
		end

		-- 원두 · 아이템
		local Bn = S.beans
		do
			local pr = 62 * M.pick
			local pr2 = pr * pr
			for i = #Bn, 1, -1 do
				local b = Bn[i]
				local dx, dy = p.x - b.x, p.y - b.y
				local d2 = dx * dx + dy * dy
				if not b.att and d2 < pr2 then
					b.att = true
				end
				if b.att then
					local d = sqrt(d2)
					if d == 0 then
						d = 1
					end
					b.sp = min(b.sp + 1200 * dt, 620)
					local st = b.sp * dt
					if d <= st + 12 then
						p.xp += b.v * M.xp * D.xp * (if truthy(opts.xpMul) then opts.xpMul else 1)
						host.sfx("pick", nil, b.v)
						ev({ k = "pick", v = b.v })
						local n = #Bn
						Bn[i] = Bn[n]
						Bn[n] = nil
						continue
					end
					b.x += dx / d * st
					b.y += dy / d * st
				end
			end
		end
		if zk == "train" then
			local lim = AISLE - 12
			for _, b in ipairs(S.beans) do
				if b.y > lim then
					b.y = lim
				elseif b.y < -lim then
					b.y = -lim
				end
			end
			for _, it in ipairs(S.items) do
				if it.y > lim then
					it.y = lim
				elseif it.y < -lim then
					it.y = -lim
				end
			end
		end
		do
			local It = S.items
			for i = #It, 1, -1 do
				local it = It[i]
				it.t += dt
				local dx, dy, rr = p.x - it.x, p.y - it.y, p.r + 20
				if dx * dx + dy * dy < rr * rr then
					if it.kind == "kimbap" then
						p.hp = min(p.maxhp, p.hp + 25)
						host.sfx("heal")
						ev({ k = "heal", v = 25 })
					elseif it.kind == "pass" then
						for _, b in ipairs(Bn) do
							b.att = true
						end
						host.sfx("heal")
						host.banner("정기권 발견", "흩어진 원두가 모두 모입니다", "good")
					else
						S.pending += 2
						S.pickMode = "chest"
						p.hp = min(p.maxhp, p.hp + 20)
						ev({ k = "heal", v = 20 })
					end
					local n = #It
					It[i] = It[n]
					It[n] = nil
				elseif it.kind ~= "chest" and it.t > 45 then
					local n = #It
					It[i] = It[n]
					It[n] = nil
				end
			end
		end

		-- 레벨
		local need, lv = xpNeed(p.level), false
		while p.xp >= need do
			p.xp -= need
			p.level += 1
			S.pending += 1
			need = xpNeed(p.level)
			lv = true
			if S.M.lvHeal ~= 0 and p.hp < p.maxhp then
				p.hp = min(p.maxhp, p.hp + S.M.lvHeal)
			end
		end
		if lv then
			ev({ k = "level" })
		end
		if S.pending > 0 then
			openLevelUp()
		end
	end

	---------------- 자동 조종 (메뉴 화면의 시연 · 밸런스 검사) ----------------
	-- 돌려주는 값: { x, y, dash }
	local function bot()
		local ax, ay, danger = 0, 0, 0
		local E = S.enemies
		local botRange = if truthy(opts.botRange) then opts.botRange else 1
		for i = 1, #E do
			local e = E[i]
			if not e.dead then
				local dx, dy = p.x - e.x, p.y - e.y
				local dd = hypot(dx, dy)
				if dd == 0 then
					dd = 1
				end
				local d = dd - e.r - p.r
				local lim = (if e.boss then 240 elseif e.elite then 170 else 120) * botRange
				if d < lim then
					local w = (if e.boss then 3 elseif e.elite then 2 else 1) * pow(1 - max(0, d) / lim, 2)
					ax += dx / dd * w
					ay += dy / dd * w
					if d < 7 then
						danger = 1
					end
				end
			end
		end
		for _, b in ipairs(S.bullets) do
			local dx, dy = p.x - b.x, p.y - b.y
			local dd = hypot(dx, dy)
			if dd == 0 then
				dd = 1
			end
			if dd < 110 then
				local w = 2.2 * pow(1 - dd / 110, 2)
				local cross = if dx * b.vy - dy * b.vx > 0 then 1 else -1
				local bl = hypot(b.vx, b.vy)
				if bl == 0 then
					bl = 1
				end
				ax += dx / dd * w * .5 + (-b.vy / bl) * cross * w
				ay += dy / dd * w * .5 + (b.vx / bl) * cross * w
				if dd < 24 then
					danger = 1
				end
			end
		end
		for _, z in ipairs(S.zones) do
			local dx, dy = p.x - z.x, p.y - z.y
			local dd = hypot(dx, dy)
			if dd == 0 then
				dd = 1
			end
			if dd < z.r + 30 then
				ax += dx / dd * 4
				ay += dy / dd * 4
				if z.warn < .25 then
					danger = 1
				end
			end
		end
		for _, w in ipairs(S.waves) do
			local dx, dy = p.x - w.x, p.y - w.y
			local dd = hypot(dx, dy)
			if dd == 0 then
				dd = 1
			end
			local gapd = w.r - dd
			if gapd > -150 and gapd < 25 then
				local da = abs(angd(atan2(dy, dx) - w.gap))
				if da > w.gw - .12 then
					local sg = if angd(atan2(dy, dx) - w.gap) > 0 then -1 else 1
					ax += -dy / dd * sg * 3
					ay += dx / dd * sg * 3
					if gapd > -34 and not w.hit then
						danger = 1
						ax -= dx / dd * 6
						ay -= dy / dd * 6
					end
				end
			end
		end
		if S.train then
			local dy = p.y - S.train.y
			if abs(dy) < LANE_H + 70 then
				ay += (if dy >= 0 then 1 else -1) * 6
			end
		else
			local ln = round(p.y / LANE_GAP) * LANE_GAP
			local dy = p.y - ln
			if abs(dy) < LANE_H + 30 and S.trainT < 4 then
				ay += (if dy >= 0 then 1 else -1) * 1.5
			end
		end
		for _, s in ipairs(S.slicks) do
			local dx, dy = p.x - s.x, p.y - s.y
			local dd = hypot(dx, dy)
			if dd == 0 then
				dd = 1
			end
			if dd < s.r + 20 then
				ax += dx / dd * .8
				ay += dy / dd * .8
			end
		end
		local best, bd = nil, 460 * 460
		for _, b in ipairs(S.beans) do
			local dx, dy = b.x - p.x, b.y - p.y
			local d2 = dx * dx + dy * dy
			if d2 < bd then
				bd = d2
				best = b
			end
		end
		for _, it in ipairs(S.items) do
			local dx, dy = it.x - p.x, it.y - p.y
			local d2 = dx * dx + dy * dy
			if d2 < 650 * 650 and (it.kind ~= "kimbap" or p.hp < p.maxhp * .8) then
				best = it
				break
			end
		end
		if best then
			local dx, dy = best.x - p.x, best.y - p.y
			local d = hypot(dx, dy)
			if d == 0 then
				d = 1
			end
			ax += dx / d * .45
			ay += dy / d * .45
		end
		if S.zk == "gates" and abs(ay) > .05 then
			local ry = (if ay > 0 then floor(p.y / GATE_GAP) + 1 else floor(p.y / GATE_GAP)) * GATE_GAP
			if abs(ry - p.y) < 46 then
				local lx = round(p.x / GATE_PER) * GATE_PER - p.x
				if abs(lx) > GATE_HALF - p.r - 3 then
					local m = hypot(ax, ay)
					ax = sign(lx) * m
					ay *= .15
				end
			end
		end
		if S.zk == "train" then
			ay *= .6
		end
		local l = hypot(ax, ay)
		if l < .02 then
			local a = S.t * .4
			return { x = cos(a), y = sin(a), dash = false }
		end
		return { x = ax / l, y = ay / l, dash = danger > 0 and p.dashCd <= 0 }
	end
	-- 저장용. 원본과 같이 S 의 맵을 그대로 가리킨다(사본이 아니다). wOrder · pOrder · fOrder · dmgOrder 는 Lua 쪽에서 더한 것
	local function serialize()
		return {
			diff = S.diff, zone = S.zone, t = S.t, hp = p.hp, level = p.level, xp = p.xp, kills = S.kills,
			weapons = S.weapons, passives = S.passives, dmg = S.dmg, rerolls = S.rerolls, x = p.x, y = p.y, fus = S.fus, fsrc = S.fsrc,
			wOrder = S.wOrder, pOrder = S.pOrder, fOrder = S.fOrder, dmgOrder = S.dmgOrder,
		}
	end
	return {
		S = S,
		update = update,
		choose = choose,
		reroll = reroll,
		dash = dash,
		bot = bot,
		serialize = serialize,
		dbg = {
			setDiff = function(i)
				i = max(0, min(3, toInt(i)))
				D = DIFFS[i + 1]
				S.diff = i
			end,
			recalc = recalc,
			enterZone = enterZone,
			boss = boss,
			spawn = spawn,
			kill = kill,
			-- Lua 쪽에만: S.weapons · S.passives · S.fus · S.dmg 를 밖에서 갈아 끼운 뒤 순서 목록을 맞춘다 (recalc 도 부른다)
			syncOrder = syncOrder,
		},
	}
end
Sim.createSim = Sim.create

Sim.xpNeed = xpNeed
Sim.clockText = clockText
Sim.TAU = TAU
Sim.GAME_LEN = GAME_LEN
Sim.RAMP = RAMP
Sim.LANE_GAP = LANE_GAP
Sim.LANE_H = LANE_H
Sim.TRAIN_LEN = TRAIN_LEN
Sim.TRAIN_SPD = TRAIN_SPD
Sim.WMAX = WMAX
Sim.EVO = EVO
Sim.PMAX = PMAX
Sim.MAX_W = MAX_W
Sim.MAX_P = MAX_P
Sim.GATE_GAP = GATE_GAP
Sim.GATE_PER = GATE_PER
Sim.GATE_HALF = GATE_HALF
Sim.GATE_TH = GATE_TH
Sim.AISLE = AISLE
Sim.DOOR_PER = DOOR_PER
Sim.DOOR_OPEN = DOOR_OPEN
Sim.ESC_W = ESC_W
Sim.ESC_PUSH = ESC_PUSH
Sim.SPIN_R = SPIN_R
Sim.ENRAGE_STEP = ENRAGE_STEP
Sim.W_SCALE = W_SCALE
Sim.XP_SCALE = XP_SCALE
Sim.CELL = CELL
Sim.ZONES = ZONES
Sim.STOPS = STOPS
Sim.LAST_STOP = LAST_STOP
Sim.ZW = ZW
Sim.ZW_ORDER = ZW_ORDER
Sim.GATE = GATE
Sim.DIFFS = DIFFS
Sim.WEAPONS = WEAPONS
Sim.WEAPON_ORDER = WEAPON_ORDER
Sim.PASSIVES = PASSIVES
Sim.PASSIVE_ORDER = PASSIVE_ORDER
Sim.FUSIONS = FUSIONS
Sim.FUSION_ORDER = FUSION_ORDER
Sim.PAIR_OF = PAIR_OF
Sim.ENEMIES = ENEMIES
Sim.ENEMY_ORDER = ENEMY_ORDER
Sim.DOOR_RATE = DOOR_RATE
Sim.MACE = MACE
Sim.BOMB = BOMB
Sim.GUARD = GUARD
Sim.PHASES = PHASES
Sim.DAY_LINE = DAY_LINE
Sim.TALK = TALK
Sim.RAGE_TALK = RAGE_TALK
Sim.BOSS_LINE = BOSS_LINE
-- 도움 함수 (JS 의 Math.hypot / Math.round / Math.sign 과 같은 값을 낸다)
Sim.hypot = hypot
Sim.round = round
Sim.sign = sign
Sim.angd = angd

return Sim
