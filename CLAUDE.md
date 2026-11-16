# 출근길 서바이벌 — 로블록스 이식 (c:\YJS\Roblox\ssb)

브라우저 게임 「출근길 서바이벌」(`commute-survival/` — 원본 클론, 읽기 전용)을 로블록스 2D 게임으로 옮기는 프로젝트.
진행 상황 · 제가 정한 것 · 사용자에게 물을 것은 `PLAN.md`에 모은다.

## 절대 지킬 것
- **「달의 계승자」를 건드리지 않는다.** `C:\YJS\Roblox\sprite-gen\` (SpriteDemo · 플레이스 96192775933291 · Rojo 포트 34872)는 읽기만 한다. 쓰기 · 지우기 · 그 Studio 창 조작 · 그 포트 사용 금지.
- 이 게임은 **별개의 로블록스 게임**이다: 「ssb」 — 체험 10777076565 · 플레이스 128125794321191(`servePlaceIds` — 이 플레이스에만 연결된다). Rojo 포트 34880. `default.project.json`의 `blockedPlaceIds`에 달의 계승자 플레이스가 들어 있다(그 플레이스에는 연결되지 않는다).
- `commute-survival/`(원본)은 고치지 않는다. 원본을 고쳐야 굽는 도구가 돌 때는 `tools/` 아래에 복사본을 만들어 고친다.

## Studio에서 확인하기 (2026-11-16 사용자: "스튜디오를 따로 열어놔서 … ssb 만 테스트해보면 되는거야")
- Rojo: `rojo serve default.project.json --port 34880` (ssb 플레이스에만 연결된다). Studio의 Rojo 플러그인에서 포트 34880으로 Connect하는 것은 사용자가 누른다.
- Studio 조작은 **반드시** `node tools/studio/mcp.mjs ssb <도구> @인자.json`으로 한다 — 창 목록에서 플레이스 128125794321191인 창을 찾아 그 창에만 보낸다(없으면 아무것도 안 한다). `call`로 직접 부를 때는 `studio_id`를 달의 계승자 창으로 주면 안 된다.

## 구운 그림은 고정 (2026-11-16 사용자: "그림 구웠으니까 그거에 맞춰서 하면되잖아")
- `assets/*.png` 16장(그림 판 13 + 글자 판 3)은 로블록스에 올렸고 번호가 `src/shared/art/AssetIds.luau`에 있다. **다시 굽지 않는다**(`tools/bake/bake.mjs` · `tools/font/bake.mjs`를 돌리면 판의 배치가 바뀌어 올린 그림과 어긋난다).
- 화면을 고칠 때는 코드로 맞춘다. 다시 구워야만 하면 먼저 사용자에게 묻고, 구운 뒤 바뀐 판을 다시 올려 번호를 고친다(크리에이터 허브의 번호는 데칼 번호 — 그 안의 이미지 번호를 적는다: `tools/studio/args/decal2image.json`).

## 구조
- `src/shared/Sim.luau` — 게임 규칙(원본 `js/sim.js`를 줄마다 옮긴 것 · Roblox API 없음 · `tools/luau/luau.exe`로도 돈다)
- `src/shared/art/` — 구운 그림 자료(자동 생성) · `assets/` — 올릴 PNG
- `src/client/` — 화면 · 입력 · UI, `src/server/` — 기록 저장
- `tools/parity/` 규칙 견줌 검사 · `tools/bake/` 그림 굽기 · `tools/mock/` Studio 없이 돌려 보는 검사
