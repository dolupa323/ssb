# Sim.luau 쓰는 법 (화면 · UI 를 만드는 사람용)

`src/shared/Sim.luau` 는 원본 `commute-survival/js/sim.js` 를 줄마다 옮긴 게임 규칙이다. Roblox API 도 `require` 도 쓰지 않는다.
같은 난수를 넣으면 원본과 비트까지 같은 게임이 나온다 — `node tools/parity/run.mjs` 가 견준다(아래 「검사」).

## 1. API

```lua
local Sim = require(ReplicatedStorage.shared.Sim)   -- default.project.json: ReplicatedStorage.shared = src/shared

local host = {
    sfx     = function(name, x, arg) end,    -- 소리. x = 소리가 난 자리의 x (없으면 nil), arg = 소리마다 다른 덧붙임 (4절)
    banner  = function(a, b, kind) end,      -- 큰 알림. a = 제목, b = 설명, kind = "station" | "boss" | "warn" | "good"
    shake   = function(amount) end,          -- 화면 흔들기 (3 ~ 12)
    levelUp = function(choices, pickMode) end, -- 선택 창을 연다. choices = 선택지 3개, pickMode = "level" | "chest" | "start"
    finish  = function(won) end,             -- 판이 끝남 (JS 의 host.end). won = true 도착 / false 멘탈 0
}
local sim = Sim.create(host, opts)           -- = JS 의 createSim. Sim.createSim 도 같은 함수
```

`opts` (모두 선택):

| 칸 | 뜻 |
|---|---|
| `diff` | 난이도 0 여유 · 1 보통 · 2 혼잡(기본) · 3 지옥철 |
| `restore` | `sim.serialize()` 가 낸 표. 이어 하기. `restore.weapons` 가 있어야 쓰인다. 원본 그대로 **그 장소의 처음부터**(zt = 0, 적 없음) 다시 시작하고 저장된 `x, y` 는 쓰지 않는다. 순서 목록(`wOrder` …)이 없으면 상수 순서로 채운다 |
| `build` | `{ weapons = {card=3,…}, passives = {…}, wOrder = {…}?, pOrder = {…}? }` 로 시작 (메뉴 시연 · 실험실) |
| `demo` | 참이면 피해를 받지 않고 선택지를 스스로 고른다 (메뉴 화면의 시연) |
| `autoPick` | `function(choices, S) return choices[i] end` — 선택 창 대신 이 함수가 고른다 |
| `xpMul`, `botRange` | 경험치 배율, 봇이 적을 피하는 거리 배율 |
| `rng` | `[0,1)` 난수 함수. 기본 `math.random` (Lua 쪽에만 있는 칸) |

`sim` 이 가진 것:

| | |
|---|---|
| `sim.S` | 게임 상태 표 (2절). 화면은 이것을 읽어 그린다 |
| `sim.update(dt, view)` | 한 걸음. `view = { w = 화면 폭, h = 화면 높이 }` (세계 좌표 단위 — 적이 생기는 거리를 정한다). 원본은 한 프레임을 1/60초 이하의 걸음으로 나눠 부른다: `n = max(1, ceil(dt/(1/60)))`, `h = dt/n` |
| `sim.choose(i)` | 선택지 고르기. **i 는 1부터** (JS 는 0부터) |
| `sim.reroll()` | 선택지 다시 뽑기. 되면 `true` (`S.rerolls` 가 줄고 `host.levelUp` 이 다시 불린다). 시작 무기 고르기에서는 안 된다 |
| `sim.dash()` | 대시. 되면 `true`. 방향은 `S.input`, 입력이 없으면 보는 쪽 |
| `sim.bot()` | 자동 조종이 낸 입력 `{ x, y, dash }`. 원본 메뉴: `local b = sim.bot(); S.input = b; if b.dash then sim.dash() end` |
| `sim.serialize()` | 저장용 표 `{diff, zone, t, hp, level, xp, kills, weapons, passives, dmg, rerolls, x, y, fus, fsrc, wOrder, pOrder, fOrder, dmgOrder}`. **S 의 표를 그대로 가리킨다(사본 아님)** — 저장할 때 바로 복사/직렬화할 것 |
| `sim.dbg` | `setDiff(i)`, `recalc()`, `enterZone(i)`, `boss(type)`, `spawn(type, x, y)`, `kill(e, src)`, `syncOrder()`(Lua 쪽에만) |

입력: 매 걸음 전에 `S.input = { x = …, y = … }` (길이 1 이하의 방향. 1 을 넘으면 규칙이 줄인다).

모듈이 내보내는 것: `Sim.xpNeed(level)`, `Sim.clockText(t)`("08:29"), `Sim.hypot/round/sign/angd`(JS 의 `Math.hypot/round/sign` 과 같은 값),
상수 `GAME_LEN WMAX EVO PMAX MAX_W MAX_P LANE_GAP LANE_H TRAIN_LEN TRAIN_SPD GATE_GAP GATE_PER GATE_HALF GATE_TH AISLE DOOR_PER DOOR_OPEN ESC_W ESC_PUSH SPIN_R ENRAGE_STEP W_SCALE XP_SCALE RAMP CELL TAU LAST_STOP`,
표 `ZONES STOPS ZW GATE DIFFS WEAPONS PASSIVES FUSIONS PAIR_OF ENEMIES DOOR_RATE MACE BOMB GUARD PHASES DAY_LINE TALK RAGE_TALK BOSS_LINE`,
JS 객체의 키 순서를 담은 배열 `WEAPON_ORDER PASSIVE_ORDER FUSION_ORDER ENEMY_ORDER`, `ZW_ORDER[zk]`.

## 2. JS 의 S 와 다른 점

1. **0부터 세는 "숫자 상태"는 숫자 그대로**: `S.zone` 0..6 → `Sim.ZONES[S.zone + 1]`, `S.diff` → `Sim.DIFFS[S.diff + 1]`, `S.stopIdx` → `Sim.STOPS[S.stopIdx + 1]`,
   김 팀장의 `e.day` 0..4 → `Sim.PHASES[e.day + 1]`, `e.st`, 광선의 `b.j`(0부터), `zone` 이벤트의 `i`.
2. **배열은 1부터**: `S.enemies`, `S.shots`, `S.ev`, `choices`, `zap` 이벤트의 `pts`, `WEAPONS[k].lv`(`lv[1]` = 1레벨 설명 … `lv[6]`), `TALK.lead[day + 1]`. `sim.choose(i)` 도 1부터.
3. **넣은 순서 목록** (Lua 표에는 순서가 없어서): `S.wOrder`(무기), `S.pOrder`(장비), `S.fOrder`(조합), `S.dmgOrder`(피해량 기록) — JS 의 `Object.keys(S.weapons)` 등과 같은 순서.
   칸을 그릴 때는 `for _, k in ipairs(S.wOrder) do local lv = S.weapons[k] … end`. 선택을 적용할 때마다(`recalc`) 맵에 맞춰진다.
   `S.weapons` 등을 밖에서 통째로 갈아 끼우면 `S.wOrder` 도 같이 바꾸거나 `sim.dbg.syncOrder()` / `sim.dbg.recalc()` 를 부를 것. `S.buildVer` 는 빌드가 바뀔 때마다 1씩 는다.
4. **`host.end` → `host.finish`**.
5. **JS 에서 없던(undefined) 칸**: `e.intro`, `e.shT`, `e.rzT`, `e.board` 는 0 으로 채워져 있다 → `if e.intro > 0 then`(등장 중) 처럼 숫자로 견줄 것 (`if e.intro then` 은 늘 참).
   보스 전용 칸 `e.t3 e.sayT e.cc e.pend`(와 김 팀장의 `e.day e.z e.fan e.row e.stp e.sq`)은 `dbg.spawn` 으로 바로 만든 보스에서는 NaN 이다 (`dbg.boss` · 자연 등장은 숫자).
6. **참·거짓**: 0 과 `""` 은 Lua 에서 참이다. `S.train`, `S.gate`, `S.boss`, `S.choices`, `S.mace`, `S.gent`, `S.umbQ` 는 없을 때 `nil`.
7. `nearestN` 등 안쪽 함수는 내보내지 않는다. `S.dmg`, `S.takenBy`, `S.wt`, `S.seen`, `S.fsrc` 는 이름 → 값 맵 그대로.

## 3. 상태 `S`

| 칸 | 뜻 |
|---|---|
| `state` | `"run"` · `"levelup"`(선택 창이 열림 — `update` 는 아무것도 하지 않는다) · `"over"` · `"won"` |
| `t`, `zt` | 판 전체 시간(초), 이 장소에 들어온 뒤의 시간 |
| `zone`, `zk`, `song` | 장소 번호(0..6), 장소 종류 `street gates plat train esc office`, 음악 번호 |
| `phase` | `"crowd"`(인파) · `"boss"`(진상 등장) · `"clear"`(통과, 1.5초 뒤 다음 장소) · `"ride"`(열차: 90초 탄다) |
| `rage`, `rageT` | 폭주 단계, 다음 폭주까지 남은 초 |
| `gate`, `boss`, `bosses` | 이 장소의 문지기 보스, 마지막으로 나온 보스, 살아 있는 보스들 |
| `late` | 끝났을 때 `t > GAME_LEN`(9시를 넘김) |
| `stopIdx`, `doorT`, `side`, `pvx` | 열차: 지난 역 수, 문이 닫힐 때까지 남은 초(>0 이면 열림), 인파가 주로 오는 쪽, 관성 |
| `train` | 차선의 버스/열차 `{kind="bus"|"train", len, spd, y, dir, warn, on, x, hitP, hit}` 또는 `nil`. `on=false` 인 동안은 예고 |
| `trainT` | 다음 버스/열차까지 |
| `pending`, `pickMode`, `choices`, `rerolls` | 밀린 선택 수, `"level" "chest" "start"`, 지금 열린 선택지, 남은 다시 뽑기 |
| `p` | 플레이어 `{x, y, r=11, hp, maxhp, inv(무적 남은 초), fx, fy(보는 쪽), level, xp, moving, anim, dashT, dashCd, ddx, ddy, slow}` |
| `weapons`, `passives`, `fus`, `fsrc` | 무기 레벨(1..7, 7=진화), 장비 레벨(1..5), 조합(값 1), 조합에 들어간 재료 무기(값 1) |
| `M` | 장비로 계산한 배율 `{might, cd, area, speed, pick, regen, bossDmg, low, lvHeal, armor, xp, dashCd, crit, luck, invT}` |
| `wt` | 무기별 대기 시간 맵 |
| `dmg`, `taken`, `takenBy` | 무기별 준 피해(결과 화면), 받은 피해 합, 까닭별(`contact bullet2 wave zone spin train` …) |
| `kills`, `dashes`, `buildVer`, `spawnR`, `spawnX`, `input` | |
| `orbA`, `selfA`, `mace`, `gent`, `umbQ`, `bullA` | 그리기에 쓰는 무기 각도 · 상태 (`mace = {a, sl, rad, x, y, sd, x0, y0}`, `gent = {a, cd, auto, fl}`, `umbQ = {a, n, t}`) |
| `ev` | 이번 걸음의 이벤트 (5절). **화면이 읽은 뒤 `table.clear(S.ev)`** — 400개에서 더 쌓이지 않는다 |
| `admNoPick`, `admRate` | 실험실용: 선택 창 끄기, 적 생성 배율 |

### 배열과 그 안의 것

| 배열 | 칸 |
|---|---|
| `enemies` | `id type def x y hp maxhp r sc spd dmg xp kx ky stun slow slowAmt flash bpT sfT anim vx vy st tm t2 acc ang dx dy seed dead boss elite mv intro shT rzT board`, 보스: `t3 sayT cc pend`, 김 팀장: `day label z fan row stp sq age`. `def = Sim.ENEMIES[type]` (`def.spr`, `def.sc`, `def.name`). `dead` 인 것은 다음 걸음에 빠진다. `mv` = 걷는 중, `flash > 0` = 맞아서 번쩍, `seed` = 겉모습 씨앗(0..999) |
| `shots` (카드) | `x y vx vy life dmg pierce hits evo a`, 프리패스: `bn` |
| `puddles` (커피 · 껌) | `x y r life dur tick dmg slow evo ph`, 껌: `gum=true`, 시한폭탄: `src="routine"` |
| `lobs` (던진 것) | `x0 y0 x1 y1 t dur r dmg evo`, 커피: `life slow`, 알람: `kind="alarm" stun rings` |
| `mines` (알람 · 시한폭탄) | `x y fuse dur r dmg stun rings evo`, 시한폭탄: `tb=true`, 두 번째 울림: `again=true` |
| `riders` (킥보드) | `x y dx dy dist max w dmg hits evo` |
| `rangs` (손잡이) | `x y vx vy ph(0 나감 · 1 돌아옴) t sp dmg size hits evo` |
| `beams` (노트북 광선) | `a da life dur len w dmg tick evo j`, 재택근무: `perm=true` |
| `bullets` (적의 탄) | `x y vx vy life dmg r kind a`. `kind`: 2 전단지 · 3 김 팀장 부채꼴 · 5 백팩 빌런 · 6 스피커 음표 · 7 김 팀장 서류 · 8 캐리어 · 9 하차 인파 · 10 캐리어 충돌 |
| `beans` (원두) | `x y v att sp ph` |
| `items` | `kind("chest" "kimbap" "pass") x y t` |
| `zones` (예고 장판) | `x y r warn dur dmg txt kind("door" "swat" "bass" "stamp" "nag" "meet")`. `warn` 이 0 이 되면 터진다 |
| `slicks` (미끄러운 바닥) | `x y r life dur` |
| `waves` (음파 고리) | `x y r spd max dmg gap gw hit`, `kind("push" "nag")` 또는 없음. `gap ± gw` 각도가 틈 |

선택지 하나: `{ kind = "weapon" | "evo" | "fuse" | "passive" | "heal", key, to, name, desc, tag, hint, wt? }`.

## 4. `host.sfx(name, x, arg)`

`x` 가 있는 것(소리가 난 자리): `hit(x, src)`, `crit`, `kill`/`elitedie`/`bossdie`/`trainkill`, `alert`, `flick`, `paper`, `boss2`, `doorslam`, `wheels`, `swing`(보스가 낼 때), `spin`, `zipper`, `rumble`, `wave`, `note`, `bass`, `page`, `nag`, `phone`, `roar`, `voice(x, 적 종류)`, `alarmboom`, `splash(x, evo)`, `boom`, `zap(x, true)`(재택근무).

`x = nil` 이고 `arg` 가 있는 것: `card(evo)`, `swing(evo 또는 세 번째 찌르기)`, `pulse(evo)`, `shout(evo)`, `zap(evo)`, `scooter(evo)`, `beam(evo)`, `lash(evo)`, `bump(evo)`, `hit(nil, "umbrella" | "shoulder")`, `pick(nil, 원두 값)`, `tick(nil, 남은 초 10..1)`.

덧붙임 없는 것: `zone`, `boss`, `warn`, `elite`, `evo`, `chest`, `level`, `dash`, `dashready`, `hurt`, `slip`, `throw`, `gum`, `stamp`, `station`, `doorclose`, `buswarn`, `trainwarn`, `buspass`, `trainpass`, `heal`.

`host.banner` 의 `kind`: `"station"`(장소에 들어옴 · 역 도착), `"boss"`(보스 등장 · 김 팀장 단계), `"warn"`(폭주 · 진상 승객 · 버스/열차), `"good"`(통과 · 정기권).
`host.shake`: 3(넥타이 한 바퀴 · 골프 우산 마무리 · 우산 방패) 4(캐리어 충돌 · 어깨빵) 5(역 도착 · 장판) 6("내릴게요!" · 진화한 어깨빵) 8(피격 · 김 팀장 단계) 9(버스/열차 · 철퇴 내려찍기) 12(보스 착지 · 보스 처치).

## 5. 이벤트 `S.ev[i] = { k = 종류, … }`

| `k` | 칸 | 언제 |
|---|---|---|
| `num` | `x y v crit` | 피해 숫자 |
| `hit` | `x y src` | 맞았지만 살아 있음 |
| `kill` | `x y type seed sc vx vy boss elite src?` | 적이 쓰러짐 |
| `hurt` / `heal` / `pick` | `v` | 플레이어 피격 / 회복 / 원두 줍기 |
| `level`, `fuse` | (없음) | 레벨 업, 조합 성립 |
| `dash` | `x y` | 대시 시작 |
| `zone` | `i` | 다음 장소로 (i = 장소 번호, 0부터) |
| `bossin` / `bossland` | `x y` | 보스가 내려오기 시작 / 착지 |
| `say` | `id txt` | 보스 대사 (`id` = 적 id) |
| `page` | `x y` | 김 팀장 단계 넘어감 |
| `crash` | `x y` | 캐리어 돌진 끝 |
| `doors` | `open`(1 · 0) | 열차 문 |
| `trainhit` | `x y` | 버스/열차에 치임 |
| `boom` | `x y r txt kind` | 예고 장판이 터짐 |
| `swipe` | `a range half both evo` | 장우산 |
| `stab` | `a range n quad` | 골프 우산 (n = 0 · 1 · 2번째) |
| `ring` / `shout` | `r evo` | 노이즈캔슬링 / "내릴게요!" |
| `zap` | `pts evo gold?` | 보조배터리 (pts = {x1, y1, x2, y2, …}) |
| `laptop` | `evo` | 노트북 발사 |
| `lash` | `as len w evo` | 넥타이 (as = 각도 배열) |
| `lashspin` | `r w gent` | 넥타이 한 바퀴 (gent = 풀정장 신사) |
| `bump` | `r evo a` | 어깨빵 대시 충격 |
| `nudge` | `x y a evo bag` | 어깨로 받아침 |
| `splash` | `x y r evo` | 커피가 떨어짐 |
| `alarmboom` | `x y r evo` | 알람이 울림 |
| `transfer` | `x y tx ty` | 프리패스 카드가 갈아탐 |
| `parry` | `x y` | 풀정장 신사가 탄을 막음 |
| `macehit` / `maceslam` / `macedash` | `x y` / `x y r` / `a` | 배낭 철퇴 |
| `fcast` | `t r x? y?` | 조합 기술 (`t` = `"freepass"` · `"routine"`; `"bulldozer"` 는 원본에서도 나오지 않는다) |

## 6. 검사

```
node tools/parity/run.mjs                 전부 (PASS/FAIL 요약, 자세한 것은 tools/parity/work/report.txt)
node tools/parity/run.mjs --only=A,B      고른 것만: math static self A mut Anative B C perf
node tools/parity/run.mjs --seeds=3       A · C 의 씨앗 수를 줄여 빨리
```

- **math**: 씨앗 난수, 견줌용 수학 함수(softmath), `hypot/round/sign` 이 JS 와 비트까지 같은가.
- **static**: 표 · 수치 · 글 (xpNeed, 무기 수치, 설명 글 …).
- **self**: Lua 쪽에만 있는 것(순서 목록, 순서 목록 없는 복원, `syncOrder`, 1부터 세는 `choose` …)의 단독 검사.
- **A**: 같은 난수 · 같은 수학 함수로 봇이 하는 판을 처음부터 끝까지 — 60 tick 마다 요약 줄(위치 · 멘탈 · 개수 · 난수 호출 수 · 이벤트 해시 …)이 비트까지 같은가.
- **mut**: Sim.luau 사본을 일부러 한 군데 틀리게 고치면 견줌이 잡아내는가 (검사 도구의 검사).
- **Anative**: V8 과 MSVC 의 원래 `sin/cos/atan2/exp/pow` 로 돌리면 어디서 갈라지는가 (마지막 비트 차이에서 시작해 자라는 잡음).
- **B**: 모든 갈래(무기 · 조합 · 보스 · 장소 · 아이템 · 저장/복원 …) + 밟은 줄.
- **C**: 난이도마다 여러 씨앗의 결과 분포.
- **perf**: `update` 한 번에 걸리는 시간.

Sim.luau 를 고쳤으면 이 검사를 다시 돌린다. `--@@MATH-BEGIN/END` 사이의 한 줄과 `--@unreachable-begin/end` 표시는 검사 도구가 쓰니 지우지 않는다.
