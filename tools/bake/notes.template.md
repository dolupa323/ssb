# 그림 굽기 기록 (ART_NOTES)

> 이 파일은 `node tools/bake/bake.mjs`가 `notes.template.md`에서 다시 만든다 ({{DATE}}). 손으로 고칠 것은 `notes.template.md`에.
> 줄 번호는 모두 원본 `commute-survival/js/gfx.js`의 것이고 굽는 도구가 원본에서 찾아 적는다.

## 1. 무엇을 하나

원본은 모든 그림을 캔버스에 코드로 그린다. 로블록스는 캔버스 코드를 돌릴 수 없으니, 원본 코드를 화면 없는 Chrome에서 그대로 돌려 그림 판(아틀라스)으로 굽는다.

- `tools/bake/bake.mjs` — 전체 순서 (Chrome 띄우기 → 굽기 → 판 짜기 → PNG · Luau 쓰기 → luau.exe로 풀어 검사 → 견본표 → 이 문서)
- `tools/bake/harness.html` · `harness.js` — Chrome 안에서 원본 코드를 불러 조각 그림을 만든다. 무엇을 어떤 이름 · 밀도로 굽는지가 여기 적혀 있다
- `tools/bake/snippets.mjs` — 그리기 반복문 안에 직접 적힌 그림 코드를 「처음 글 ~ 끝 글」로 잘라 내는 표. 잘라 낸 글은 고치지 않고 돌린다
- `tools/bake/sheets.js` — 견본표 그리기 · `tools/bake/zoom.mjs` — 색 줄이기 전후를 크게 견줘 보기
- `tools/bake/lib/` — `cdp.mjs`(Chrome 조종) · `png.mjs`(PNG 쓰기 · 읽기) · `pack.mjs`(판 채우기) · `quant.mjs`(색 줄이기) · `codec.mjs`(점 자료 글로 바꾸기)
- 원본은 고치지 않는다. `work/gfx.patched.js`는 원본에 `__eval` 한 줄(안쪽 이름을 바깥에서 읽고 부르는 문)만 덧붙인 복사본이고 매번 새로 만든다

### 다시 굽기

```
node tools/bake/bake.mjs            # 전부 (약 20~30초 · Chrome을 화면 없이 띄운다 · DevTools 포트 9377 · 바깥으로 나가는 통신은 막아 둠)
node tools/bake/bake.mjs --reuse    # Chrome에서 받아 둔 점 자료(work/raw.*)로 판 짜기부터 다시 (색 수만 바꿔 볼 때)
node tools/bake/zoom.mjs 4 char/player/0/0 fx/flame    # out/zoom.png: 왼쪽 PNG 판, 오른쪽 점 자료를 푼 것, 4배
```

두 번 연달아 구우면 PNG · Atlas.luau · 점 자료 모듈이 바이트까지 같다(확인함). 원본 `gfx.js`가 바뀌어 잘라 낼 글을 못 찾으면 굽기가 멈추고 어느 조각인지 말한다.
밀도 · 팔레트 색 수는 `bake.mjs` 맨 위 `CFG`, 그림마다의 밀도는 `harness.js`.

### 나오는 것

- `assets/<판>.png` — 로블록스에 올릴 PNG (곧은 알파 · 색 줄이기 전의 온전한 그림)
- `src/shared/art/Atlas.luau` — 목록 (판 · 그림의 자리 · 기준점 · 캐릭터 정보)
- `src/shared/art/pixels/<판>.luau` (+ `<판>_2.luau` …) — 올리지 않고도 돌게 코드에 실은 점 자료
- `src/shared/art/Decode.luau` — 점 자료를 푸는 순수 Luau 코드 (손으로 쓴 것 · 굽는 도구가 만들지 않는다)
- `tools/bake/out/contact_*.png` 견본표 · `out/report.json` 숫자 · `out/atlas.json` 목록(JSON)

## 2. 판과 크기

밀도는 「세계 단위당 점 수」다. 원본 화면은 짧은 변이 약 520 세계 단위이니 1080p에서는 1단위가 약 2점이다.

{{PAGES}}

- 「최대 오차」는 PNG의 점과 점 자료를 푼 점의 차이(알파를 곱한 색과 알파, 0~255 가운데 가장 큰 값). 「그대로」는 색을 하나도 줄이지 않았다는 뜻.
- 푸는 시간은 `tools/luau/luau.exe`로 잰 `Decode.page` 시간(모듈을 읽어 들이는 시간은 뺐다). 로블록스 안에서는 재 보지 못했다.
- 캐릭터 · 효과 · 아이콘 판은 2048색(점마다 2바이트), 세계 판은 1024색, 바닥은 256색(점마다 1바이트)까지 줄였다. 견줘 본 값: 모두 256색이면 합계 약 0.94 MB에 최대 오차 30~43(불꽃 · 열기 같은 번지는 색에 띠가 보였다), 하나도 안 줄이면 약 2.2 MB.
- 바닥 무늬는 원본과 같은 밀도 2로 굽는다(1024×1024 판 · 2026-11-16에 1에서 2로 올림 — 실제 Studio에서 벽돌 줄눈이 흐려 보였다. 1일 때보다 점 자료가 약 0.5 MB 늘었다). 밀도를 낮춘 것: 선로 · 차도 1.5(원본 2), 그림자 · 빛 · 연기 · 가로수 그늘 0.5~1, 핫팩 열기 0.5, 웅덩이 1, 화면 가장자리 0.25, 집중선 0.5, 열차 벽 · 이음매 1. 나머지는 2(작은 것 몇 개는 4). 보스 캐릭터도 2.

### 판 위에 놓은 방식

- 그림 사이는 투명 2점. 캐릭터만 「보이는 점」의 네모로 잘랐다(종류 안에서는 모든 변형 · 걸음이 같은 네모). 나머지는 원본 캔버스 크기 그대로라 원본의 `drawImage(그림, x, y, w, h)`를 그대로 옮기면 된다.
- 가면(mask) 판은 캐릭터 판과 같은 자리 배치다. `sprites["mask/…"]`의 x, y, w, h는 `char/…`와 같고 page만 다르다.
- 이어 붙는 그림(`st/tact` `st/track` `ws/road`는 가로, `ws/esc` `ws/stair`는 세로)은 이어 붙는 쪽 바깥 2점에 반대편 점을, 다른 쪽 바깥 2점에 가장자리 점을 덧댔다. 열차 벽 · 이음매도 가장자리 점을 덧댔다. 그래서 늘이거나 줄여도 솔기에 틈이 안 생긴다. 목록의 x, y, w, h는 덧댄 부분을 뺀 본래 그림이다.
- 바닥 무늬는 그림 한 장이 판 한 장이다(여백 없음 · 1024×1024점 = 512×512 단위). 통째로 512×512 단위마다 놓으면 된다.
- 투명한 점 가운데 보이는 점과 맞닿은 것에는 이웃의 색을 넣어 두었다(알파는 0). 로블록스가 그림을 늘이고 줄일 때 가장자리에 검은 테가 끼는 것을 막으려는 것이다. 「투명한가」는 알파로만 판단할 것.

## 3. 게임에서 쓰는 법

```lua
local Atlas  = require(art.Atlas)
local Decode = require(art.Decode)
-- (가) 올리지 않고: 판마다 EditableImage를 만든다
local buf, w, h = Decode.load(function(name) return require(art.pixels[name]) end, "chars1")
local img = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
-- (나) 올린 뒤: 같은 판 이름의 PNG(assets/<판>.png)의 에셋 번호를 쓴다. 자리 · 크기는 같다.

local e = Atlas.sprites["char/pass/2/0"]
label.ImageRectOffset = Vector2.new(e.x, e.y)
label.ImageRectSize   = Vector2.new(e.w, e.h)            -- 좌우 뒤집기: Offset.x = e.x + e.w, Size.x = -e.w
label.Size     = UDim2.fromOffset(e.w / e.s * k, e.h / e.s * k)                       -- k = 화면 배율 × 원본의 sc
label.Position = UDim2.fromOffset(X - e.ox * k, Y - e.oy * k)                          -- (X, Y) = 기준점을 놓을 자리
-- 뒤집었을 때는 Position.x = X - (e.w / e.s - e.ox) * k
```

- 캐릭터: 원본 `drawChar(type, v, frame, dir, fl, x, feetY, sc)`는 그림 이름 `(fl and "mask/" or "char/") .. type .. "/" .. v .. "/" .. Atlas.chars[type].frames[frame + 1]`, 기준점 (x, feetY), k = sc.
  네 걸음 가운데 1번과 3번이 점 하나까지 같아서(굽는 도구가 견줘 확인) 0, 1, 2 세 장만 구웠다.
  원본이 머리 위 자리를 `top = feet - (d.oy - 4) * sc`로 구하는 곳에서는 `Atlas.chars[type].oy`(원본 값)를 쓴다. 그림 항목의 ox, oy는 잘라 낸 뒤의 값이다.
- 색 입히기: `fx/glow`(원본 `glow('r,g,b')`)는 흰색 한 장만 구웠다. `ImageColor3`로 색을, `ImageTransparency`로 알파를 준다. `fx/flare` `fx/puff` `fx/spark` `fx/shard` `fx/dashring` `ui/vig/amb` `prim/*`도 흰색이다.
- 더하기 섞기: 원본은 빛 · 효과를 `globalCompositeOperation='lighter'`(더하기)로 그리고 그 위에 번짐(bloom) 층을 한 번 더 얹는다. 로블록스 GUI에는 더하기 섞기가 없다 — 보통 섞기로 놓으면 원본보다 덜 밝다. 화면 담당이 투명도로 맞출 것.
- 모듈 크기: 로블록스는 코드로 `Script.Source`를 넣을 때 20만 자를 넘기지 못한다고 알려져 있다(Rojo 플러그인으로 동기화할 때 걸린다 · [DevForum](https://devforum.roblox.com/t/increase-script-source-property-character-limit-from-200000-to-support-code-generation-and-export-tools/3928089) · 공식 문서로는 확인하지 못했다). 그래서 점 자료 글을 18만 자씩 잘라 `<판>.luau`, `<판>_2.luau` …로 나눴다. `rojo build`로 만든 파일에서는 17개 모듈이 모두 들어가는 것을 확인했다.

## 4. 점 자료 형식 (v = 1)

`pixels/<판>.luau`는 `{ v, w, h, n, raw, z, parts, data }`를 돌려준다. 조각이 여럿이면 `<판>_2.luau` …가 글만 돌려준다. 글을 차례로 이으면:

1. **85진 글자** — 글자 5개가 4바이트. 글자는 문자 33~117(`!`~`u`), 값 = Σ (글자 − 33) × 85^(4−i), 그 값을 작은 쪽 먼저(little-endian)인 32비트 수로 쓴다. 전체 z바이트(끝은 0으로 채움). Luau에서는 `[=[ … ]=]` 긴 문자열 안에 넣었다(역슬래시 · 따옴표가 그대로 글자다).
2. **deflate** (zlib의 머리 없는 raw deflate, node `zlib.deflateRawSync` 9단계) — 풀면 raw바이트.
3. **팔레트 + 번호** — 팔레트 n색 × 4바이트(R, G, B, A · 곧은 알파), 이어서 점마다 팔레트 번호(윗줄 왼쪽부터 w×h개).
   n ≤ 256이면 번호는 1바이트. n > 256이면 2바이트인데, 아랫자리 바이트 면(w×h) 뒤에 윗자리 바이트 면(w×h)이 따로 온다(많이 쓰는 색이 앞 번호라 윗자리 면은 거의 0이고 잘 줄어든다).
   팔레트 0번은 언제나 완전 투명 (0,0,0,0).

`Decode.page(head, {나머지 조각})` → `buffer`(RGBA8 · w×h×4 · 윗줄부터 · 곧은 알파), w, h. `EditableImage:WritePixelsBuffer`에 그대로 넣는다. `Decode.load(get, 이름)`은 조각을 `get`으로 가져와 이어 준다. 로블록스 API를 쓰지 않는다.

색 줄이기(`lib/quant.mjs`): 넓게 칠해진 색은 그대로 팔레트에 두고, 남은 자리는 「지금 팔레트로 가장 크게 틀리는 색」부터 채운 뒤 k-평균으로 다듬는다. 거리는 알파를 곱한 색 + 알파로 재고, 불투명한 점은 불투명한 색으로만 간다.

검사: `bake.mjs`가 `work/verify.luau`를 만들어 `luau.exe`로 판마다 풀고, 푼 점 전체의 검사 합(32비트 낱말을 더해 가는 두 합, 4294967291로 나눈 나머지)을 node가 「나와야 하는 점」으로 셈한 값과 견준다. 하나라도 다르면 굽기가 실패한다. PNG는 쓴 파일을 다시 읽어 점마다 견준다.

## 5. 글자가 든 그림과 글꼴

원본은 Google Fonts의 「Do Hyeon」을 받아 쓴다. 굽는 Chrome은 바깥 통신을 막았고 이 PC에 그 글꼴이 없어서, 그림 안의 글자는 원본 글꼴 목록의 다음 차례인 「맑은 고딕」으로 구워졌다. 해당: `ws/bus`의 「출근」, `fx/exitsign`의 「출구」, `st/chest` · `icon/payday`의 「₩」(sans-serif 지정이라 원본도 같다), `ws/gate`의 「GO」(sans-serif).
`fx/shoutburst/*` 말풍선의 폭은 글자 폭으로 정해지는데 이것도 맑은 고딕으로 쟀다. 글자를 뺀 것(`fx/exitsign/blank`, `fx/shoutburst/*`, `tr/sign`, `ui/warn/*`)은 화면 쪽에서 TextLabel을 얹는다.

## 6. 굽지 않은 것 — 화면 담당이 기본 도형으로 다시 만들어야 하는 것

로블록스 GUI의 Frame(네모) · UICorner(둥근 모서리 · 동그라미) · UIStroke(테두리 · 고리) · UIGradient · TextLabel · Rotation과, 위에서 구운 그림에 색을 입힌 것으로 만든다. 괄호 안은 gfx.js 줄.

**배경**
- 승강장 `drawPlatform`({{L:function drawPlatform(}}): 초록 안내선과 흰 가장자리 줄(네모 · {{L:ctx.fillStyle='rgba(0,168,77,.78)'}}), 역 이름 글자 「○○역」 92px({{L:ctx.fillText(st.name+'역'}}), 타는 곳 번호 「1-1」 12px({{L:ctx.fillText((1+Math.floor(n/4))}}), 선로 가의 신호 점(네모 8×3, 색이 상태로 바뀜 · {{L:ctx.fillRect(x+20,ly-61,8,3)}}), 진입 경고 때 선로를 덮는 붉은 네모({{L:ctx.fillRect(x0,ly-56,vw,112)}}). 바닥 · 빛 웅덩이 · 쓰레기 · 화살표 · 세모 · 선로 · 점자 블록 · 갈매기표는 구웠다.
- 역 앞 `drawStreet`({{L:function drawStreet(}}): 「역삼역 2번 출구」 74px 글자({{L:ctx.fillText('역삼역 2번 출구'}}). 나머지는 구웠다(횡단보도 = `sc/crosswalk`).
- 개찰구 `drawGates`({{L:function drawGates(}}): 「타는 곳 / 나가는 곳」 70px 글자({{L:'나가는 곳':'타는 곳'}}), 노란 줄 두 개(네모 · {{L:ctx.fillRect(x0,ry-34,vw,4)}}), 개찰구 날개(움직이는 짧은 선 · {{L:ctx.lineTo(gx+sd*(GATE_HALF-10),ry-14*fl)}}).
- 에스컬레이터 `drawEsc`({{L:function drawEsc(}}): 양옆 손잡이의 움직이는 흰 줄(네모 3×24 · {{L:ctx.fillRect(x+5,y,3,24)}}). 발판 · 계단 · 화살표는 구웠고, 움직임은 놓는 자리를 밀어서 낸다.
- 회사 앞 `drawOffice`({{L:function drawOffice(}}): 비스듬한 빛 띠(45도로 돌린 네모 · {{L:ctx.fillStyle='rgba(60,44,20,.07)'}}), 「구로구 / 출근 9:00」 64px 글자({{L:'출근 9:00':'구로구'}}).
- 열차 안 `drawTrainIn`({{L:function drawTrainIn(}}): 검은 바탕({{L:ctx.fillStyle='#0b0f12';ctx.fillRect(x0-2,y0-2}}), 터널 벽의 줄({{L:for(const yy of[-150,-162,150,162])}}), 지나가는 터널 등(네모 + `fx/glow` · {{L:ctx.fillStyle='rgba(255,240,190,.55)'}}), 창밖 승강장 바닥(네모 · {{L:ctx.fillStyle='#cdc9be'}}), 역명판 글자({{L:ctx.fillText(nm,x+150,sy-4)}}), 통로 가장자리 줄({{L:ctx.fillStyle='rgba(40,56,64,.1)'}}), 문 위 안내판 글자 「다음 역 ○○」 10px({{L:'이번 역 ':'다음 역 '}}). 줄 선 사람 · 앉은 사람은 `char/pass/…`. 벽 · 창문 · 문짝 · 문턱 · 이음매 · 의자 · 봉 · 손잡이 · 문빛 · 역명판 바탕은 구웠다(문짝은 `tr/doorpanel`을 doorA만큼 밀어 놓는다).
- `drawTrainOver`({{L:function drawTrainOver(}}): 천장 봉(가로 선 · {{L:ctx.strokeStyle='rgba(205,212,216,.5)'}}). 손잡이의 흔들림은 `tr/strap`을 조금 돌려서 낸다.
- 달리는 열차 `drawTrain`({{L:function drawTrain(}}) · 버스 `drawBus`({{L:function drawBus(}}): `st/cab` + `st/car` ×4, `ws/bus` ×2에 `fx/glow`(색 255,240,170)를 놓으면 된다.
- 해 질 녘 덧칠(화면 전체 네모 · {{L:ctx.fillStyle='rgba(10,14,34,.1)'}}).

**캐릭터에 덧그리는 것** (`drawEnemy` {{L:function drawEnemy(}} · `drawCrowd` {{L:function drawCrowd(}} · `drawPlayer` {{L:function drawPlayer(}})
- 하차 인파의 바닥 그림자(타원 · {{L:ctx.ellipse(e.x,e.y+22,e.r*1.25,e.r*.62}}), 뛰는 승객의 속도선 세 줄({{L:ctx.moveTo(x-e.dx*14-e.dy*k*7}})과 「!」({{L:ctx.strokeText('!',x,top-2)}}), 기절 별 세 개(작은 동그라미 · {{L:ctx.arc(x+Math.cos(a)*9,top+2+Math.sin(a)*3.5,2.2}}), 정예 적 체력 막대({{L:rr(ctx,x-bw/2-1,top-9,bw+2,6,3)}}), 김 팀장의 안경 빛(동그라미 두 개 · {{L:ctx.arc(x+dir*5-7,top+25,6.5}})과 「팀장」 이름표({{L:ctx.fillText('팀장',x,top-8)}}), 「미끌!」 글자({{L:ctx.fillText('미끌!'}}), 보스 말풍선(둥근 네모 + 글자 · {{L:ctx.measureText(sy.txt)}} — 꼬리는 `ui/bubbletail`).
- 돌진 잔상(가면 그림을 흐리게 세 장 · {{L:drawChar(stype,e.seed%d.nv,(fr+k)%4,dir,true}}), 쓰러지는 모습(캐릭터 그림을 돌리며 흐리게 · {{L:for(const c of corpses)}}), 플레이어 잔상({{L:for(const g of ghosts)}}) — 구운 그림으로 된다.
- 플레이어 발밑 고리: `fx/pring/0`(바탕) 위에 `fx/pring/1…8`(대시 대기 1/8 단위). 원본은 연속으로 차오른다.
- 스피커 빌런의 소리 물결 · 백팩 빌런의 회전 꼬리는 멈춘 한 장면(`fx/soundwave` · `fx/spintrail`)만 구웠다. 원본의 움직임({{S:soundwave}} · {{S:spintrail}})은 크기 · 투명도 · 회전으로 흉내 낸다.

**바닥에 깔리는 것** (`render`의 ground layer {{L:/* ground layer */}}부터)
- 기름 · 웅덩이: 멈춘 한 장면만 구웠다(`fx/slick` · `fx/puddle/*`). 원본은 가장자리가 꿈틀거리고 방울이 올라온다({{S:slick}} · {{S:puddle}}).
- 알람 · 시한폭탄({{L:for(const m of S.mines)}}): 범위 원(동그라미), 점선 테두리(`fx/dashring`), 차오르는 테두리(부채꼴 호 · {{L:ctx.arc(m.x,m.y,m.r,-Math.PI/2,-Math.PI/2+TAU*q)}}), 시곗바늘({{L:const ha=-Math.PI/2+TAU*q}}), 김({{L:const sy=m.y-30-((time*22+sd*5)%10)}}), 울림 호({{L:ctx.arc(m.x+sd*8,m.y-18,9+q*5}}).
- 핫팩: 퍼지는 고리 두 개(UIStroke · {{L:ctx.arc(p.x,p.y,r*(.3+.7*q),0,TAU)}})와 둘레에 놓는 `fx/flame`. 바탕은 `fx/heatring/*`.
- 도장 자국 「결재」(둥근 네모 테두리 두 겹 + 글자 · {{L:ctx.fillText('결재',0,2)}}).
- 공격 예고({{L:for(const z of S.zones)}}): 색 원 두 겹(동그라미), 점선 테두리(`fx/dashring`), 번쩍이는 굵은 테두리(UIStroke), 스피커 원({{L:ctx.arc(z.x,z.y,z.r*.22*b}}), 잔소리 말풍선과 글자({{L:const W=['말이야','라떼는'}}), 「쿵」 같은 글자({{L:ctx.fillText(z.txt||'쿵'}}), 휘두르는 호({{L:ctx.arc(z.x,z.y,z.r*.6,a-.7,a)}}). 도장 · 문짝 · 탁자 · 백팩은 구웠다.
- 퍼지는 물결({{L:for(const w of S.waves)}}): 틈이 난 큰 호 네 겹 + 「잔소리!」 글자 + 작은 세모 + 틈 끝의 초록 점. 호는 굽지 못했다 — 짧은 선분(돌린 네모)을 이어 만들어야 한다.
- 보스 예고: 회전 범위 원({{L:ctx.arc(e.x,e.y,SPIN_R,0,TAU)}}), 돌진 길(굵은 선 · {{L:ctx.lineTo(e.x+e.dx*len,e.y+e.dy*len)}}), 보스 등장({{L:else if(f.k==='bossin')}}: 타원 · 점선 타원 · 빛기둥 · 「!」).
- 레벨 업({{L:if(f.k==='level'){ctx.globalCompositeOperation='lighter';}}): 타원 고리, 빛살 8개(`prim/tri`), 빛기둥(UIGradient). 대시 자국({{L:else if(f.k==='dash')}}): 번지는 선.
- 상자: 도는 빛살 6개(`prim/tri` · {{L:ctx.lineTo(-9,-62)}}), 빛기둥({{L:const pg=ctx.createLinearGradient(0,by-190,0,by)}}).

**무기 · 효과** (`fxLayer` {{L:const fxLayer=()=>}}부터)
- 선 · 호 · 자국으로 된 것은 굽지 않았다: 배낭 철퇴의 끈과 휘두른 자국({{L:if(S.fus&&S.fus.bulldozer&&S.mace)}}), 신사 우산의 자루({{L:if(S.fus&&S.fus.gentleman&&S.gent)}}), 백팩 회전의 자국 · 불도저 날({{L:const bull=S.fus&&S.fus.bulldozer,fl=bagFling}}), 셀카봉의 봉과 부채꼴 자국({{L:l=wl(S,'selfie');}}), 킥보드의 꼬리({{L:for(const r of S.riders){const a=Math.atan2}}), 손잡이 · 카드의 꼬리({{L:for(const b of S.rangs)}} · {{L:for(const s of S.shots){const fp}}), 노트북 광선({{L:for(const b of S.beams)}}), 순환선 표시({{L:if(f.k==='route')}}), 어깨빵 충격파({{L:else if(f.k==='bump')}}), 재택근무 광선 · 번개({{L:if(T==='remote')}}), 프리패스 고리({{L:else if(T==='freepass')}}), 광선 발사({{L:else if(f.k==='beam')}}), 노이즈캔슬링 물결 고리({{L:else if(f.k==='ring')}}), 외침의 고리와 방사선({{L:else if(f.k==='shout')}}), 번개({{L:else if(f.k==='zap')}}).
- 그림은 구웠고 움직임만 다시 만들 것: 넥타이 채찍(`fx/tie/*`는 곧게 편 모습 — 원본은 물결친다 · {{S:lash}} · 한 바퀴 돌리기 {{L:else if(f.k==='lashspin')}}), 우산 찌르기 · 휘두르기(`fx/gstab/*` `fx/gstabT` `fx/umb` + `fx/flare` · {{L:else if(f.k==='stab')}} · {{L:else if(f.k==='swipe')}}), 조합 발동(`fx/hazardring` `fx/gentspiral` `fx/routinerays` `fx/remote/*` · {{L:else if(f.k==='fcast')}}), 외침 말풍선(`fx/shoutburst/*` + 글자).
- 입자 `drawParts`({{L:function drawParts(}}): 연기 = `fx/puff`, 별 = `fx/glow` + `fx/flare`, 불꽃 = `fx/flame`, 불똥 = `fx/spark`(+ 흰 점), 파편 = `fx/shard`, 방울 · 점 = `prim/disc`, 종이 = 네모, 고리 = UIStroke, 꼬리표 = 둥근 네모 테두리, 글자 = TextLabel. 입자를 만드는 규칙은 `consume`({{L:function consume(}}) · `stepFx`({{L:function stepFx(}}).
- 번짐(bloom) 층({{L:if(bloomOn&&bloomAuto&&!reduce){const main=ctx}}): 효과를 1/4 크기로 한 번 더 그려 흐리게 얹는다. 로블록스 GUI로는 그대로 못 한다.
- 숫자({{L:for(const n of nums)}}) · 화면 밖 표시의 글자({{L:'버스 진입':'열차 진입'}}): TextLabel.

**화면 전체** ({{L:/* screen space: lighting, flashes, joystick */}}부터)
- 장면 바뀜 검은 막({{L:if(wipeT>0)}}), 폭주 때 붉은 덧칠({{L:if(S.rage>0&&o.mode==='play')}}), 흰 번쩍임({{L:if(flash>0&&!reduce)}}), 조이스틱({{L:const j=o.joy}}): 네모 · 동그라미. 가장자리 어둠 · 붉은/초록 가장자리 · 집중선은 구웠다(`ui/vig/*` · `ui/speedlines` — 16:9로 구웠으니 화면에 맞춰 늘인다).

**원본에 있지만 쓰이지 않아 굽지 않은 것**: `FX.gumb`({{L:FX.gumb=}}) · `FX.golf`({{L:FX.golf=}}) — 만들기만 하고 그리는 곳이 없다. `drawMonday`({{L:function drawMonday(}}) — 부르는 곳이 없다.

### 게임이 스스로 만드는 도움 그림 판 (굽지 않는다 — `src/client/Art.luau`의 buildPrims)

`Art.init`이 280×168 판 하나를 셈으로 그려 `EditableImage`로 만든다(에셋 번호를 쓰는 때에도 이 판만은 늘 그렇게 만든다). `Art.set` · `Art.info`에서 구운 그림과 똑같이 이름으로 쓴다.

| 이름 | 무엇 |
|---|---|
| `prim/ring` · `prim/ringb` | 흰 고리 (96칸 안에 반지름 45 · 굵기 3 / 반지름 40 · 굵기 10) — 타원 고리로 늘여 쓴다 |
| `prim/grad` | 왼쪽이 진하고 오른쪽으로 사라지는 흰 띠 (빛기둥 · 꼬리) |
| `prim/soft` · `prim/softgrad` | 가장자리가 부드러운 흰 띠 / 그것이 오른쪽으로 사라지는 것 (광선 · 번개 · 빛 번짐) |
| `prim/glow2` | 가운데가 넓게 꽉 찬 둥근 빛 — 밝은 바닥에서 `fx/glow` 대신 쓴다(원본의 「더하기 섞기」로 하얗게 날아간 모양) |
| `prim/cone` | 열린 열차 문으로 드는 빛(사다리꼴 · 위쪽 문 · 기준점 = (문 가운데, 0)) — `tr/doorlight` 대신 흰빛으로 쓴다 |
| `prim/wave/nag` · `push` · `bass` | 음파 고리의 단면(원본의 네 겹 선을 한 장에 · 세로가 반지름 방향) — 호를 따라 토막으로 놓는다 |

## 7. 그림 목록
{{CATALOGUE}}
