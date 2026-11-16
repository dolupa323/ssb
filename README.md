# 출근길 서바이벌 — 로블록스판 (ssb)

브라우저 게임 [출근길 서바이벌](https://github.com/Jh0-0y/commute-survival)(JS)을 로블록스 2D 게임(Luau)으로 옮긴 것입니다.
원본 코드를 고친 것이 아니라, **같은 동작을 하는 Luau 코드를 새로 썼습니다.** 로블록스 플레이스: 체험 「ssb」(10777076565) · 플레이스 128125794321191.

- 진행 기록 · 정한 것 · 원본과 견준 결과: [PLAN.md](PLAN.md)
- 나중에 입힐 새 컨셉(초안): [retheme/STORY.md](retheme/STORY.md) · [retheme/ASSETS.md](retheme/ASSETS.md)

---

## 1. 실행하기

**받을 것**
1. 이 저장소
2. 원본 (굽는 도구 · 견줌 검사가 읽습니다 — 게임만 돌릴 때는 없어도 됩니다)
   `git clone https://github.com/Jh0-0y/commute-survival.git commute-survival` ← 이 폴더 안에
3. [Rojo](https://github.com/rojo-rbx/rojo/releases) **7.6.1** — Studio의 Rojo 플러그인과 버전이 맞아야 연결됩니다
4. (검사 도구를 쓸 때만) Node 22 이상 · Chrome · Luau 실행기(`luau.exe` `luau-analyze.exe` `luau-compile.exe`를 `tools/luau/`에 — [Luau 릴리스](https://github.com/luau-lang/luau/releases))

**켜기**
```
rojo serve            # 포트 34880 (default.project.json에 적혀 있음)
```
Studio에서 「ssb」 플레이스를 열고 → Rojo 플러그인 → `localhost` : `34880` → Connect → Play.

- `default.project.json`의 `servePlaceIds`가 플레이스 128125794321191만 허용합니다. 다른 플레이스에서 돌리려면 그 줄을 고칩니다.
- **Rojo를 연결하면 이 폴더의 파일이 플레이스의 스크립트를 덮어씁니다.** Studio에서 직접 고친 것은 사라지므로, 고칠 때는 이 폴더의 파일을 고칩니다.
- Studio 창이 뒤에 있으면 Studio가 스스로 15fps로 낮춥니다. 빠르기를 볼 때는 창을 앞에 둡니다.

**조작**: WASD/방향키 이동 · Space/Shift 대시 · P 일시정지 · 1/2/3 카드 고르기 · R 다시 뽑기 · 메뉴에서 Enter 시작. 터치: 화면을 끌면 조이스틱, 끄는 중에 다른 손가락으로 치면 대시.

---

## 2. 원본의 무엇이 어디로 갔나

| 원본 (JS) | 로블록스 (Luau) | 옮긴 방식 |
|---|---|---|
| `js/sim.js` 규칙 | `src/shared/Sim.luau` | 줄마다 그대로. 같은 난수를 넣으면 결과가 원본과 한 자리도 다르지 않음(`node tools/parity/run.mjs` — 18/18) |
| `js/gfx.js` 그리기 | `src/client/Gfx.luau` · `src/client/gfx/*` · `src/client/Art.luau` | 다시 씀. 캔버스 대신 그림 조각(ImageLabel)을 놓음 |
| `index.html` · `js/main.js` 화면 · 입력 | `src/client/ui/*` · `Input.luau` · `Stage.luau` · `init.client.luau` | 다시 씀. `ui/App.luau`가 `main.js` 자리(함수 이름 그대로) |
| `js/audio.js` 소리 합성 | `src/client/Sound.luau` · `src/shared/SoundMap.luau` | 원본이 내는 소리를 파일로 구워 올리고 구간을 틂 |
| 브라우저 저장소 | `src/server/Data.luau` · `src/shared/Net.luau` | DataStore(설정 · 안내 본 것 · 난이도 · 난이도별 최고 기록) |
| `lab.html` · `js/admin.js` 실험실 | 옮기지 않음 | — |

`Sim.luau`를 쓰는 법(상태의 칸 · 이벤트 목록)은 [tools/parity/SIM_API.md](tools/parity/SIM_API.md).

---

## 3. 그림 · 소리 · 글자

원본은 그림 파일 없이 코드로 그리고, 소리도 코드로 합성합니다. 로블록스는 그렇게 할 수 없어서 **원본 코드를 화면 없는 Chrome에서 돌려 파일로 구웠습니다.**

| 종류 | 굽는 도구 | 나온 파일 | 게임이 읽는 것 |
|---|---|---|---|
| 그림 판 13장 (그림 342개) | `node tools/bake/bake.mjs` | `assets/*.png` · `src/shared/art/Atlas.luau` · `src/shared/art/pixels/*` | `src/shared/art/AssetIds.luau` |
| 글자 판 3장 (Do Hyeon · VT323, 622자) | `node tools/font/bake.mjs` | `assets/font_*.png` · `src/shared/font/*` | 같은 `AssetIds.luau` |
| 소리 4개 (효과음 68종 + 음악 6곡) | `node tools/audio/bake.mjs` | `assets/audio/*.wav` · `src/shared/SoundMap.luau` | `src/shared/SoundIds.luau` |

- 올린 곳: 로블록스 계정 dolupa95 (이름 `ssb_…`). 「ssb」 체험 안에서는 누구에게나 나옵니다. **다른 체험에서 쓰려면** 소리는 따로 허용이 필요합니다.
- `AssetIds.luau`에 번호가 없는 판은 코드에 실린 점 자료(`pixels/*`)로 기기 메모리에 직접 만듭니다(EditableImage · 약 37MB). 번호가 있으면 올린 그림을 씁니다.
- **다시 구우면 판의 배치가 바뀝니다.** 그대로 두면 옛 그림에 새 자리표를 대어 그림이 어긋납니다 → 구운 뒤 바뀐 PNG를 다시 올리고 `AssetIds.luau`를 고쳐야 합니다.
- **올릴 때의 함정**: 크리에이터 허브가 보여 주는 번호는 「데칼」 번호라 그대로 쓰면 `Asset type does not match requested type`가 납니다. Studio 편집 상태에서 `InsertService:LoadAsset(데칼 번호)`로 그 안의 `Decal.Texture`(이미지 번호)를 읽어 적습니다(`tools/studio/args/decal2image.json`에 그 코드).
- 게임에 새 글이 들어가면 글자 판에 없는 글자가 생길 수 있습니다. `tools/font/bake.mjs`가 빠진 글자를 찾으면 멈춥니다. 판에 없는 글자가 섞인 글은 게임에서 보통 글꼴로 대신 그려집니다.
- 글꼴 Do Hyeon · VT323 · IBM Plex Sans KR은 SIL Open Font License 1.1입니다(라이선스 글: `tools/font/fonts/*.OFL.txt`).

자세한 것: [tools/bake/ART_NOTES.md](tools/bake/ART_NOTES.md) · [tools/audio/AUDIO_NOTES.md](tools/audio/AUDIO_NOTES.md)

---

## 4. 검사 도구

| 명령 | 하는 일 |
|---|---|
| `node tools/parity/run.mjs` | 원본 `sim.js`와 `Sim.luau`를 같은 난수로 돌려 결과를 견줌 (6분쯤) |
| `node tools/mock/run.mjs` | Studio 없이 클라이언트 · 서버 코드를 돌리고 대략의 화면을 찍음. 쓰는 법 · 흉내 내지 못하는 것: [tools/mock/README.md](tools/mock/README.md) |
| `node tools/mock/analyze.mjs` | 돌리지 않고 코드를 훑어 틀린 이름 · 형을 찾음 |
| `node tools/ui/run.mjs` · `node tools/world/run.mjs` | UI · 세계 그리기의 시나리오 |
| `node tools/studio/compare.mjs` | **실제 Studio**의 ssb 창과 원본 웹게임을 같은 상태로 만들어 장면마다 나란히 찍음 → `tools/studio/shots/cmp/` (5분쯤) |

`tools/studio/*`는 이 PC의 Studio MCP(`%LOCALAPPDATA%\Roblox\mcp.bat`)로 Studio를 조작합니다. 플레이스 번호가 128125794321191인 창에만 보내고, 그 창이 편집 상태가 아니면(누가 플레이 중이면) 아무것도 하지 않습니다. 찍는 5분 동안은 그 창을 건드리지 않아야 합니다.

`src/client/DebugHook.client.luau`는 Studio에서만 켜지는 시험용 창구입니다(원본의 `#dbg` 자리 — 장소 · 보스 · 무기를 바로 만듦). 게시된 게임에서는 아무것도 하지 않습니다.

---

## 5. 원본과 견준 결과 (2026-11-16)

원본 웹게임과 로블록스를 같은 화면 크기 · 같은 상태로 띄워 35장면을 나란히 찍어 봤습니다 — 메뉴, 무기 16종(5레벨 · 진화), 히든 조합 5종, 장소 7곳, 보스 7종, 버스 · 열차, 일시정지/설정, 레벨 업 카드, 정시 출근, 멘탈 0.

**같은 것**: 구성 · 그림 · 글 · 수치 · 자리. 규칙은 검사로 같음을 확인.

**다른 것 (로블록스가 못 하는 것)**
- 본문의 작은 한글은 로블록스 기본 한글 글꼴(원본은 IBM Plex Sans KR). 제목 · 숫자 · 전광판 시계는 구운 글자라 원본과 같음
- 빛 번짐: 2D 화면에 「밝게 겹치기」와 흐림이 없어 여러 겹의 부드러운 그림으로 흉내 냄
- 화면 왼쪽 위에 로블록스 기본 단추가 있어 「레벨」 글이 그 오른쪽으로 감(채팅 단추는 껐음)
- 좌우로 치우치는 소리(pan) 없음 · 무작위 소리는 3가지를 돌려 씀 · 자세한 10가지는 `AUDIO_NOTES.md`
- 화면에 적이 260명을 넘으면 발밑 그림자를 끔(원본에 없는 것 — 물건 수를 줄이려고)
- 창이 뒤로 가거나 로블록스 메뉴가 열리면 일시정지

---

## 6. 아직 확인하지 못한 것

- **소리**: 올린 파일이 Studio에서 읽히는 것까지만 봄. 맞는 순간에 맞는 소리가 나는지 **귀로 들어 본 사람이 없음**
- **진짜 폰**: 조작은 Studio에서 마우스로 흉내 내어 봄(끌기 조이스틱 · 대시 단추 · 일시정지 단추 · 메뉴 굴리기). 손가락 두 개, 폰에서의 빠르기는 못 봄
- **알람 폭발 · 노이즈캔슬링 고리 · 핫팩 불꽃**의 마지막 빛 조정: 고친 뒤 실제 Studio에서 다시 찍지 못함
- 올린 그림 · 소리가 로블록스 **심사를 통과했는지**(주인 계정에서는 보이지만 다른 계정에서는 심사 전에 안 보일 수 있음)
- 게임패드, 처음 하는 사람용 안내 글, 폭주 단계의 화면
- `tools/mock/analyze.mjs`가 `Sim.luau`에서 형 오류 1건을 냄(새 검사기로는 0건 · 실제 버그인지 보지 않음)
