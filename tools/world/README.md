# tools/world — 세계 그리기(Gfx) 장면 시험

`src/client/Gfx.luau`(원본 `commute-survival/js/gfx.js`를 옮긴 것)를 Studio 없이 돌려 보고, **같은 장면을 원본으로도 찍어** 나란히 견준다.

```
node tools/world/run.mjs                               # 모든 장면: 우리 것(mock) + 원본(화면 없는 Chrome) · 1280x720
node tools/world/run.mjs --only street,train           # 이름이 그 글로 시작하는 장면만
node tools/world/run.mjs --viewport 1280x720,844x390   # 화면 크기를 여럿
node tools/world/run.mjs --no-orig                     # 우리 것만 (원본은 장면마다 1분쯤 걸린다)
node tools/world/run.mjs --no-mock                     # 원본만
python tools/world/cmp.py 1280x720 street.fight 0.62   # 원본(왼쪽) | 우리 것(오른쪽)을 한 장으로 → work/cmp/
python tools/world/cmp.py 1280x720 street.fight 1.3 340 100 620 500   # 그 가운데 (x y w h)만 크게
```

- 찍힌 화면: `shots/<화면 크기>/<장면>.<이름>.png`(우리 것) · `<장면>.<이름>.orig.png`(원본).
- 끝날 때의 코드: 오류 · 확인 실패가 하나라도 있으면 1.

## 어떻게 같은 장면이 되나

- 장면은 `scenes.mjs`에 적는다: 씨앗 · 난이도 · 처음 무기 · 차례로 할 일(`run` 몇 장 · `enterZone` · `boss` · `spawn` · `build` · `set` · `shot` …). `tools/parity`의 시나리오와 같은 꼴이다.
- 두 쪽이 그것을 같은 뜻으로 읽는다: `driver.luau`(우리 Sim.luau + Gfx.luau, mock 위에서) · `orig/driver.js`(원본 sim.js + gfx.js, Chrome에서).
- 규칙의 난수는 같은 씨앗 난수(mulberry32)이고, 그리기 쪽 난수는 따로 둔다. 한 장 = 1/60초, 매 장 `render`를 부른다.
  그래서 `shot` 때의 플레이어 자리 · 적 수 · 난수 호출 수가 두 쪽에서 같다(`견줌:` 줄 — 원본 쪽 값은 `orig/driver.js`가 `<pre id="log">`에 적는다).
- 원본은 고치지 않는다. `work/orig/<장면>.<크기>.html`이 원본의 `js/sim.js` · `js/gfx.js`를 그대로 불러 쓴다(index.html은 열지 않는다 — 바깥 글꼴을 받으려 하기 때문).
  Chrome은 `--host-resolver-rules=MAP * ~NOTFOUND`로 바깥 통신을 막고 띄운다.
- 원본 화면은 한 번 돌리면서 `shot`마다 큰 캔버스에 세로로 쌓아 한 장으로 찍은 뒤 `split.py`로 자른다.

## 파일

| 파일 | 하는 일 |
|---|---|
| `run.mjs` | 장면마다 시나리오(.luau)와 원본용 HTML을 만들어 돌린다 |
| `scenes.mjs` | 장면 목록 (장소 7곳 · 보스 7종 · 무기 16종의 1 · 6 · 진화 · 조합 5종 · 아이템 · 적 450 · 메뉴 시연 · 색종이 · 끝까지 가는 판 4개) |
| `driver.luau` | 우리 쪽 몸통: 화면 틀 둘을 만들고 `Art.init` → `Gfx.init` → 장면을 돌리며 `Gfx.render` · 숫자를 잰다 |
| `orig/driver.js` | 원본 쪽 몸통 |
| `world.project.json` | 시험용 프로젝트: `src/shared` + `src/client`의 `Art` · `Gfx` · `gfx/`만 넣는다(UI 쪽 스크립트는 넣지 않는다). `art/AssetIds`는 빈 Folder로 가려 둔다 — mock은 올린 에셋을 그리지 못하므로 코드에 실린 점 자료로 그리게 하려는 것이다(판의 내용은 같다) |
| `cmp.py` · `split.py` | 그림 나란히 붙이기 · 자르기 |
| `scenarios/smoke.luau` | 가장 짧은 확인(판 만들기 → 5초 그리기) |
| `scenarios/assetids.luau` · `world_ids.project.json` · `scenarios/AssetIds.sample.luau` | `src/shared/art/AssetIds.luau`가 있을 때 `Art.luau`가 번호가 적힌 판은 올린 에셋으로, 나머지는 코드에 실린 점 자료로 붙이는지 본다: `node tools/mock/run.mjs --project tools/world/world_ids.project.json --script tools/world/scenarios/assetids.luau` |
| `shots/` · `work/` | 찍힌 화면 · 돌릴 때 생기는 것(지워도 된다) |

## 재는 것

`driver.luau`가 장면 끝에 찍는 줄: 적 최대 · **보이는 GuiObject 최대** · **한 장면에 쓴 속성 수 최대** · 만든 GuiObject 수 · `Gfx.render` 한 번의 평균/최대 시간(luau.exe + mock 기준 — Roblox의 시간이 아니다).
`steady` 단계는 같은 상황을 몇 백 장 돌린 뒤 「새로 만든 GuiObject 수」를 적는다(풀이 다 찬 뒤에는 0이어야 한다).
