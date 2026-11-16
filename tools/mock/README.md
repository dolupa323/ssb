# tools/mock — Studio 없이 게임 코드를 돌려 보는 검사 도구

이 세션에서는 Roblox Studio를 쓸 수 없어서(다른 게임이 열려 있다) 만든 것이다.
`src/` 의 Luau 코드를 **Roblox가 아닌 Luau CLI(`tools/luau/luau.exe`)** 위에서 돌린다. Roblox의 `game` · `Instance` · `Enum` · `task` 같은 것은 이 도구가 흉내 낸 것(mock)이다.

**여기서 오류 없이 돈다고 Roblox에서 된다는 뜻이 아니다.** 잡아 주는 것은 「오타 · 틀린 형 · 없는 API · 돌다가 나는 Luau 오류 · 화면의 자리 셈」까지다. 맨 아래 「흉내 내지 않는 것 · 어림하는 것」을 꼭 읽는다.

## 빨리 써 보기

모든 명령은 프로젝트 뿌리(`c:\YJS\Roblox\ssb`)에서 친다.

```
node tools/mock/run.mjs                                  # default.project.json을 돌린다: 서버 → 클라이언트 → 60장(1초)
node tools/mock/run.mjs --frames 600 --shot out.png      # 600장(10초)을 돌리고 끝난 화면을 out.png로
node tools/mock/run.mjs --viewport 844x390 --touch --shot phone.png   # 폰 가로 화면 · 손가락 기기
node tools/mock/run.mjs --script tools/mock/sample/scenarios/ui.luau --project tools/mock/sample/default.project.json --shot-dir tools/mock/sample/shots
node tools/mock/analyze.mjs                              # 돌리지 않고 하는 검사(luau-analyze + API 낱말 검사)
node tools/mock/test.mjs                                 # 이 도구의 자체 시험을 모두 돌린다
```

- 끝날 때의 코드: 오류나 확인 실패가 하나라도 있으면 **1**, 없으면 **0**, 옵션을 잘못 주면 2.
- 「장」 = 화면 한 번 그리는 단위(frame). 기본은 1/60초.
- 찍히는 줄의 앞머리: `[client]` · `[server]` = 그 쪽 스크립트의 `print`, `[harness]` = 시나리오의 `print`.

## 파일

| 파일 | 하는 일 |
|---|---|
| `run.mjs` | 돌리는 명령. 묶음을 만들고 → luau.exe로 돌리고 → 나온 줄을 읽어 적고 → 화면을 찍는다 |
| `bundle.mjs` | Rojo 프로젝트(json)를 읽어 「인스턴스 나무 + 모든 소스」를 Luau 파일 하나로 묶는다(Luau CLI는 파일을 못 읽는다) |
| `shot.mjs` | 화면을 적은 JSON → HTML → 화면 없는 Chrome → PNG |
| `analyze.mjs` | 돌리지 않는 검사 |
| `test.mjs` | 자체 시험 |
| `fetch-ref.mjs` · `gen-api.mjs` | 공개 참고 자료(Roblox API 덤프 · rbx-dom의 기본 속성 값)를 받아(`ref/`) 런타임이 읽는 표(`runtime/apidump.luau`)로 바꾼다. 표는 이미 만들어져 있어서 평소에는 돌릴 일이 없다 |
| `runtime/*.luau` | 흉내 낸 Roblox: `types`(자료형) · `sched`(차례지기 · 신호) · `inst`(인스턴스) · `layout`(화면 자리) · `gui` · `services` · `input` · `dump`(화면 적기) · `harness` · `main` |
| `sample/` | 견본 게임(`client` · `server` · `shared`) · 시나리오(`scenarios/`) · 일부러 틀린 프로젝트(`broken/`) · 찍힌 화면(`shots/`) |
| `work/lune-check/` | 달의 계승자의 `stage` · `canvas` · `sprite`를 **베껴 와** 그대로 돌려 본 것(원본은 건드리지 않았다) |
| `out/` | 돌릴 때 생기는 것(묶음 파일 · 화면 HTML · Chrome 프로필). 지워도 된다 |

Rojo의 이름 규칙을 그대로 따른다: `x.luau` = ModuleScript · `x.client.luau` = LocalScript · `x.server.luau` = Script · `init.luau`(`init.client.luau` · `init.server.luau`)가 있는 폴더 = 그 스크립트 · 그냥 폴더 = Folder · `x.json` = 그 자료를 돌려주는 ModuleScript. `$properties` · `$className` · `$path`를 읽는다. `.rbxm` · `.model.json`은 읽지 못한다(건너뛰고 알린다).

## run.mjs의 옵션

```
--project <json>      Rojo 프로젝트 (기본 default.project.json)
--viewport <WxH>      화면 크기 (기본 1280x720)
--frames <N>          시나리오가 없을 때 넘길 장 수 (기본 60)      --fps <N>  한 장 = 1/N초 (기본 60)
--script <luau>       시나리오 파일
--shot <png>          끝난 뒤의 화면을 찍는다(여러 번 가능)          --shot-dir <dir>  harness.shot("이름.png")이 놓일 폴더
--assets <json>       그림 짝 { "rbxassetid://123": "assets/a.png" } (기본: tools/mock/assets.json이 있으면 그것)
--inset <N>           Roblox 윗줄의 높이 (기본 58)
--touch               손가락 기기처럼 시작(TouchEnabled = true · 글쇠판 · 마우스 없음 · PreferredInput = Touch)
--signals <deferred|immediate>   이벤트에 건 함수를 부르는 방식 (기본 deferred — 새 플레이스의 기본)
--lenient-enums       열거형 속성에 문자열 · 수를 넣어도 받는다(Roblox처럼). 기본은 오류로 막는다
--studio              RunService:IsStudio() = true
--no-start            시나리오가 harness.start()를 부르기 전에는 스크립트를 시작하지 않는다
--tree                끝난 뒤 화면 나무를 글로 찍는다      --dump  찍은 화면의 JSON도 남긴다(.json)
--seed <N>            math.random의 씨앗(기본은 정해진 값)   --user-id · --user-name · --place-id
--latency <초>        원격 이벤트가 건너가는 데 걸리는 시간(기본 0 = 다음 장)   --ds-latency <초>  DataStore 한 번(기본 0.1)
--timeout <초>        luau가 이만큼 넘게 돌면 멈춘다(기본 300)   --codegen · --keep · --json <파일> · --quiet · --no-core-overlay
```

시나리오 없이 돌리면: 서버 스크립트(ServerScriptService) → 플레이어 한 명 만들기(`Player1` · UserId 1001) → StarterPlayerScripts를 PlayerScripts로, StarterGui를 PlayerGui로 베끼기 → `PlayerAdded` → 클라이언트 스크립트 → N장. 그동안 난 오류(파일 · 줄 · 역추적)와 `warn`을 모두 적는다.

## 시나리오 쓰는 법

시나리오는 Luau 파일이고 `harness`를 받는다(`harness`라는 이름으로 바로 쓰거나 `local h = ...`). 맨 바깥에서는 `task.wait`를 쓸 수 없다 — 시간은 `harness.step`으로 넘긴다. 시나리오 안에서는 `game` · `Instance` · `Enum` 을 그대로 쓸 수 있다(서버와 클라이언트 양쪽 권한을 다 가진 「harness」 쪽으로 돈다).

```lua
local h = harness
h.step(30)                                        -- 30장 넘기기
local best = h.get("PlayerGui.Hud.Best")          -- 길로 찾기(없으면 오류 — 어디까지 있었는지 알려 준다)
h.eq(best.Text, "최고 기록: 0", "처음 기록")      -- 값 확인
h.keyDown(Enum.KeyCode.D); h.step(30); h.keyUp(Enum.KeyCode.D)
h.clickOn(h.findByText("시작", true))             -- 글로 찾은 단추의 가운데를 마우스로
h.shot("after.png")                               -- 화면 찍기
```

| 갈래 | 함수 |
|---|---|
| 시간 | `start()` · `step(n?, dt?)` · `advance(초)` · `waitFor(조건함수, 초?)` · `time()` · `frame()` · `wallClock()`(진짜 시계) |
| 찾기 | `find(길)` · `get(길)` · `findByName(이름)` · `findAllByName` · `findByText(글, 꼭같이?, 숨은것도?)` · `findAllByText` · `findAllByClass(클래스)` · `player()` · `playerGui()` · `game` · `services.이름` |
| 화면 | `rect(inst)` → x, y, w, h(화면 좌표) · `center(inst)` · `isVisible(inst)` · `at(x, y)` → 맨 위의 것, 입력을 받는 것 · `tree(root?)` · `shot("이름.png")` · `capture()` · `viewport()` · `resize(w, h)` |
| 글쇠 | `keyDown(k)` · `keyUp(k)` · `keyTap(k, 장?)` — k는 `Enum.KeyCode.W` 나 `"W"` |
| 마우스 | `mouseMove(x, y)` · `mouseDown(x?, y?, 단추?)` · `mouseUp` · `click(x, y)` · `clickOn(inst)` · `wheel(x, y, 방향)` |
| 손가락 | `touchBegin(번호, x, y)` · `touchMove(번호, x, y)` · `touchEnd(번호)` · `tap(x, y)` · `tapOn(inst)` — 번호가 다르면 다른 손가락(InputObject도 다르다) |
| 글 칸 | `focus(textBox)` · `typeText("글")` · `unfocus(enter?)` (칸을 누르고 Enter 글쇠를 눌러도 된다) |
| 기기 | `setDevice({ touch, keyboard, mouse, gamepad, preferred })` · `windowFocus(bool)` · `menu(bool)` |
| 확인 | `expect(값, 글)` · `eq(실제, 기대, 글)`(표는 속까지 견준다) · `near(실제, 기대, 오차)` · `expectError(함수, 들어 있어야 할 글)` · `fail(글)` |
| 오류 | `errors()` · `warnings()` · `takeErrors()`(알고 낸 오류를 거둬 세지 않게) · `notes()`(흉내 내지 않은 것) |
| 쪽 | `asServer(함수)` · `asClient(함수)` · `pcallAs("client", 함수)` · `require(모듈, "client")`(그 쪽이 읽어 둔 모듈의 값) |
| 자료 | `datastore.get(이름, 열쇠)` · `datastore.set(이름, 열쇠, 값)` · `datastore.failNext(번, 글?)` · `datastore.calls()` · `datastore.dump()` · `sounds()`(튼 소리의 기록) · `coreCalls()`(SetCore 기록) |
| 그 밖 | `fire(inst, "이벤트", …)`(아무 이벤트나 낸다) · `shutdown()`(플레이어 나가기 → PlayerRemoving → BindToClose) · `print(…)` |

- `find`/`get`의 길: `"PlayerGui.Hud.Frame"` · `"game.ReplicatedStorage.shared.Sim"` · 앞머리가 없으면 PlayerGui 아래.
- **좌표**: harness에 주는 x, y와 `rect`가 주는 값은 「화면 좌표」(창의 왼쪽 위가 0, 0)다. Roblox의 `AbsolutePosition` · `InputObject.Position` · `MouseButton1Down(x, y)` 은 **Roblox 윗줄(기본 58픽셀) 아래가 0** 이라 y가 58 작다(`IgnoreGuiInset = true`인 화면 틀의 맨 위는 `AbsolutePosition.Y = -58`). mock도 그렇게 돌려준다.
- 견본: `sample/scenarios/` 의 `validate` · `sched` · `layout` · `net` · `ui` · `gallery` · `misc` · `perf`.

## 화면 찍기

`harness.shot` 이나 `--shot` 은 PlayerGui 아래의 보이는 것들을 그리는 차례대로 JSON으로 적고(자리 · 자르는 네모 · 색 · 글 · 그림 조각), `shot.mjs`가 그것을 HTML로 바꿔 화면 없는 Chrome(`--headless=new --screenshot`)으로 찍는다.

- `Content.fromObject(EditableImage)` 로 붙인 그림은 **`WritePixelsBuffer`로 실제로 써 넣은 점**이 그대로 나온다.
- `rbxassetid://…` · `rbxasset://…` 는 짝 파일에 적힌 것만 그 PNG로 그리고, 나머지는 **보라색 빗금 칸**(에셋 번호와 자르는 네모가 적혀 있다)으로 그린다. 짝 파일: `{ "rbxassetid://123": "assets/atlas.png", "456": "assets/b.png" }` (길은 짝 파일이 있는 폴더 기준).
- 왼쪽 위의 점선 네모 둘은 Roblox 기본 단추(메뉴 · 채팅)가 놓이는 자리를 **어림으로** 그린 것이다(가려지는 것을 알아보라고). `--no-core-overlay`로 끈다.
- 빈 곳의 푸른 회색(#3b4a5a)은 「아무 화면 틀도 덮지 않은 곳」이다(Roblox에서는 3D 세계가 보일 자리).

**Roblox 화면과 다른 점(알고 있는 것)**
- 글꼴: Roblox 글꼴이 아니라 Windows의 「맑은 고딕」으로 그린다. 글자 크기는 `TextSize x 0.85` 로 잡는다(Roblox의 TextSize는 줄의 높이). 글의 폭 · 줄 바꿈 자리는 실제와 다르다.
- `TextBounds` · `TextFits` · `TextScaled` · `AutomaticSize`(글) · `TextService:GetTextSize` 는 **어림**이다: 한글 · 한자 · 가나 한 자 = `0.85 x TextSize`, 영문 · 숫자는 글자마다 0.27 ~ 0.86 배(평균 0.5쯤), 줄 높이 = TextSize.
- `UIGradient`는 배경에만(그림 · 글에는 안 입힌다) · 색과 투명도의 점을 CSS 그러데이션으로 옮긴다(Offset은 가로만).
- `UIStroke`: 틀에는 바깥 테두리(둥근 모서리를 따른다), 글에는 글자 테두리. `LineJoinMode` · 테두리의 그러데이션은 없다. `UICorner`가 있으면 옛 테두리(`BorderSizePixel`)는 그리지 않는다.
- 돌린 것(`Rotation`)은 그 가운데를 축으로 아이들과 함께 돈다. 돌린 틀의 `ClipsDescendants`는 Roblox처럼 무시한다. 누른 자리 찾기는 돌리기를 **무시**한다(돌리지 않은 네모로 본다).
- `CanvasGroup`은 아이들의 투명도를 하나씩 곱할 뿐이다(겹친 곳이 Roblox와 다르다). `GroupColor3`은 없다.
- `ScaleType.Slice` · `Tile`은 기본만. `ImageButton`의 `HoverImage` · `PressedImage`, 단추의 `AutoButtonColor`(누를 때 어두워짐)는 없다.
- `ScrollingFrame`의 굴림 막대는 그리지 않는다. `ViewportFrame` · `VideoFrame` · `BillboardGui` · `SurfaceGui` 는 그리지 않는다.
- 꾸밈 글(`RichText`)은 `<b> <i> <u> <s> <br/> <font color size weight transparency> <stroke> <mark> <uc> <sc>` 만.

## 검사하는 것(돌릴 때)

Roblox API 덤프(클래스 955개 · 열거형 662개)에 적힌 대로만 받는다. 다음은 **그 자리에서 오류**가 되고, 파일 · 줄 · 역추적이 찍힌다.

- 없는 클래스(`Instance.new("Fraem")`) · 만들 수 없는 클래스 · 없는 서비스
- 없는 속성을 읽거나 씀(`f.BackgroundColour3 = …` → 「혹시 "BackgroundColor3"?」까지 알려 준다) · 없는 메서드 · 없는 이벤트
- 틀린 형: UDim2 속성에 수 · Color3 속성에 Vector3 · 불 속성에 수 · Content 속성에 문자열 · 열거형 속성에 **다른 열거형** · 열거형 속성에 문자열(Roblox는 맞는 이름이면 받아 주지만 mock은 막는다 — `--lenient-enums`로 푼다)
- 읽기 전용 속성에 씀 · `inst.Method()`(점으로 부름) · 빠진 인자 · 틀린 형의 인자(API 덤프의 인자 목록으로 본다)
- 없는 열거형 · 없는 열거형 값 · 자료형의 없는 칸(`v.Z`) · 자료형 고치기(`v.X = 1`) · `Vector2 + 수`
- `TweenService:Create`의 없는 속성 · 틀린 형 · `EditableImage:WritePixelsBuffer`의 버퍼 길이(폭 x 높이 x 4가 아니면 오류) · 그림판 밖
- 쪽이 틀린 호출: 서버에서 `FireServer` · 클라이언트에서 `FireClient` · 클라이언트에서 DataStore · 서버에서 `RenderStepped` · 서버의 `Players.LocalPlayer`(nil)
- DataStore에 넣을 수 없는 값(함수 · Roblox 자료형 · 섞인 표 · NaN · 50자 넘는 열쇠 · 4MB 넘는 값)
- 서로를 부르는 모듈 · 값을 돌려주지 않는 모듈 · 5초 넘게 기다리는 `WaitForChild`(경고)

받아 주는 것(Roblox도 받아 준다): 문자열 속성에 수 · 수 속성에 수로 읽히는 문자열 · 정수 속성에 소수(버림).

끝에 「mock이 흉내 내지 않거나 어림한 것」 목록이 찍힌다 — 그 실행에서 **불렸지만 흉내 내지 않는** 메서드(아무것도 하지 않고 nil을 돌려준다) · 이제 쓰지 않는(deprecated) 것 · 어림으로 넘긴 것이 한 줄씩 나온다.

## 돌리지 않는 검사 — analyze.mjs

```
node tools/mock/analyze.mjs [--project …] [--solver old|new] [--strict] [--lints] [--all] [--sourcemap 파일.json]
```

1. **luau-analyze**: 이 빌드의 `luau-analyze.exe`에는 Roblox 정의 파일을 읽히는 옵션이 **없다**(`--definitions` 없음 — 있는 옵션은 `--mode` · `--solver` · `--formatter` · `--timetrace` · `--fflags` 뿐). 그래서 소스를 `out/analyze/`에 베껴 파일마다 「Roblox 전역 = any」 머리말을 붙이고, `require(script.Parent.X)` · `require(ReplicatedStorage.shared.Y)` · `require("./X")` 를 파일 길로 바꿔서 돌린다.
   → 잡는 것: 문법 오류 · 없는 변수 · 인자 수 · 순수 Luau 값의 형 · **다른 모듈에 없는 칸**(require를 풀었을 때). 못 잡는 것: Roblox 인스턴스의 속성 오타(전부 `any`다).
   풀지 못한 require(변수로 고른 모듈 같은 것)는 따로 세어 적고 오류로 치지 않는다. 린트는 종류별 개수만(`--lints`로 다 본다).
2. **API 낱말 검사**(이 도구가 직접 한다): `Enum.X.Y` · `Instance.new("X")` · `GetService("X")` · `IsA("X")` · `FindFirstChildOfClass("X")` 들을 API 덤프와 견줘 **틀린 것**을 적는다. 또 `.이름` 가운데 Roblox API에도 프로젝트 어디에도 없는 이름, 값을 넣기만 하고 읽는 곳이 없는 칸을 **의심**으로 적는다(오타일 수도, 그냥 안 쓰는 칸일 수도 있다 — 끝날 때의 코드에는 넣지 않는다).

`ref/globalTypes.d.luau`(luau-lsp의 Roblox 정의)도 받아 두었지만 지금은 **쓰지 못한다**. luau-lsp를 따로 깔면 `--sourcemap sourcemap.json` 으로 만든 나무와 함께 `luau-lsp analyze --definitions=tools/mock/ref/globalTypes.d.luau --sourcemap=sourcemap.json src` 로 Roblox 형까지 볼 수 있다(이 조합은 **돌려 보지 못했다**).

## 자체 시험 — test.mjs

`node tools/mock/test.mjs` 는 견본 프로젝트로 시나리오 9개, 일부러 틀린 프로젝트, 베껴 온 화면 코드, analyze를 돌려 끝날 때의 코드와 나와야 하는 글을 본다. 일부러 실패하는 것 둘(`fail` · `broken`)은 코드 1이 나와야 통과다. 찍힌 화면은 `sample/shots/`.

## 흉내 내지 않는 것 · 어림하는 것

**없는 것(코드가 불러도 아무 일도 없거나 nil)**
- 3D 전부: 캐릭터 · Humanoid · 카메라 움직임 · 물리 · Part · 레이캐스트. `Player.Character`는 늘 nil이고 `CharacterAdded`는 나지 않는다. `CFrame`은 자리(Position)만 있다.
- 진짜 그리기: 화면은 HTML로 옮긴 어림이다(위 목록).
- 진짜 소리: `Sound:Play()`는 「틀었다」고 적고 가상 시간으로 `TimePosition`만 흐른다. 길이(`TimeLength`)는 모든 소리가 **1초**로 되어 있다. 소리가 실제로 있는지 · 심사를 통과했는지는 모른다.
- 에셋 읽기: `rbxassetid://` 그림 · 소리가 있는지 모른다(`IsLoaded`는 늘 true · `PreloadAsync`는 늘 성공). `AssetService:CreateEditableImageAsync`는 빈 64x64 그림판을 준다.
- 네트워크 복제: 서버와 클라이언트가 **한 나무를 같이 본다**. 그래서 클라이언트가 만든 인스턴스가 서버에 보이고, 클라이언트가 ServerStorage · ServerScriptService 안을 볼 수 있다(Roblox에서는 안 된다). 원격 이벤트의 값만 베껴서(표는 복사 · 함수는 nil) 다음 장에 건너간다.
- 플레이어는 한 명. 여러 명 · 팀 · 채팅 · 구매(MarketplaceService) · 뱃지 · 텔레포트 · 글 거르기(`FilterStringAsync`는 글을 그대로 돌려준다) · 지역화.
- `HttpService`의 요청 · `MessagingService` · `MemoryStoreService` · `require(에셋 번호)`.
- 화면 클래스 가운데 `UIPageLayout` · `UITableLayout` · `UIFlexItem` · `UIListLayout.Wraps` · `HorizontalFlex` · `VerticalFlex` · `UIDragDetector` · `ViewportFrame` · `VideoFrame` · `BillboardGui` · `SurfaceGui` · `Path2D` (만들 수는 있지만 자리 · 화면에 아무 영향이 없다 — 만들면 목록에 찍힌다).
- 게임패드는 글쇠 이름(`ButtonA` 같은 것)을 `keyDown`으로 누르는 것까지. 엄지 막대 · 진동 · 자이로 없음. `GuiService.SelectedObject`로 화면을 돌아다니는 것 없음.
- 기기의 「안전 영역」(노치 · 둥근 모서리): 위쪽 띠 하나만 있다. `ScreenInsets`는 `CoreUISafeInsets`(띠를 뺀다)와 그 밖(화면 전체) 두 가지로만 본다.
- 메모리 · 성능의 한계: EditableImage가 메모리를 얼마나 쓰는지, 저사양 폰에서 만들기에 실패하는지 모른다(크기 1024x1024 넘는 것만 막는다). 빠르기도 Roblox와 무관하다.
- 권한 · 보안: 스크립트가 못 쓰는 API(PluginSecurity 같은 것)는 막지만, 그 밖의 Roblox 쪽 제한(요청 횟수 · DataStore 예산 · 원격 이벤트 빈도)은 없다.

**어림 · 다르게 되어 있는 것**
- **시계가 가상이다**: `os.clock` · `os.time` · `tick` · `time` · `task.wait` 은 harness가 장을 넘길 때만 흐른다(`os.clock`은 부를 때마다 100만분의 1초씩 더 흐른다). 스크립트 안에서 `os.clock`으로 잰 「걸린 시간」은 0에 가깝게 나온다 — 진짜 걸린 시간은 `harness.wallClock()`으로 잰다. `os.time()`의 처음 값은 2026-11-16 00:00 UTC로 고정이다.
- **늘 같은 결과**: `math.random`의 씨앗이 고정이다(`--seed`로 바꾼다). Roblox에서는 실행마다 다르다. `Random.new(씨앗)`의 수열은 Roblox의 것과 **다르다**.
- **이벤트를 부르는 때**: 기본은 「미뤄 부르기」(Deferred — 신호를 낸 스레드가 멈춘 뒤에 받는 함수가 돈다). 플레이스의 `Workspace.SignalBehavior`가 Immediate면 `--signals immediate`로 돌린다. 한 장 안의 차례(원격 이벤트 배달 → `task.wait` 깨우기 → 트윈 → `BindToRenderStep` → `PreRender` → `RenderStepped` → `PreAnimation` → `PreSimulation` → `Stepped` → `PostSimulation` → `Heartbeat` → 화면 자리 셈)는 Roblox와 **꼭 같지는 않다**.
- **속성의 기본값**: 두 공개 자료에서 읽었다 — Roblox API 덤프(Full-API-Dump: 클래스가 스스로 가진 속성)와 rbx-dom의 반사 자료(`ref/rbx-dom-database.json`: 윗 클래스에서 물려받은 속성까지, `Instance.new`로 만든 것의 값). 그래서 `Instance.new("TextLabel").TextSize` = 8 · `Font` = Legacy · `ScreenGui.ZIndexBehavior` = Global · `UIListLayout.SortOrder` = Name 같은 값이 나온다 — Studio에서 손으로 넣은 것에서 보던 값(글씨 14 · SourceSans · Sibling)과 다를 수 있다. 코드로 만들 때는 쓰는 속성을 빠짐없이 적는 것이 안전하다. 두 자료에 없는 속성(읽기 전용 · 서비스의 속성 일부 · Font · Content 같은 형)은 「0 · false · 빈 글 · 열거형의 0번」이나 손으로 적은 값이다 — 틀릴 수 있다.
- `UIListLayout` · `UIGridLayout`의 `SortOrder`를 코드에서 정하지 않으면 이름순(`Name`)으로 놓이고, 그때 목록에 알림이 찍힌다.
- `UIScale`: 제 틀의 크기 전체와 아래 것들의 오프셋에 곱한다. `AutomaticSize`: 글의 크기 · 아이들의 끝 · 배치의 내용 크기로 **키우기만** 한다(Scale로 놓인 아이는 0으로 본다). `UIAspectRatioConstraint` · `UISizeConstraint` 는 기본 동작만.
- Roblox 윗줄의 높이는 58로 두었다(`--inset`). 기기마다 다르다.
- 마우스가 올라간 것(`MouseEnter`)은 그 점에 있는 **보이는 것 전부**에 준다. 입력은 맨 위에서부터 처음 만나는 `Active = true`인 것이 받는다(단추 · 글 칸은 기본이 Active). `Interactable = false`인 것은 건너뛴다.
- 원격 이벤트: 받는 쪽이 아직 걸지 않았으면 쌓아 두었다가 처음 걸 때 준다(256개까지). 섞인 표는 배열 부분만, 문자열이 아닌 열쇠는 문자열로 간다.
- DataStore: 기억 속에만 있다(실행이 끝나면 사라진다). 한 번 부를 때 0.1초(가상) 기다린다. 버전 · 메타데이터 · 예산 없음. `UpdateAsync`가 다른 서버와 부딪히는 일도 없다.
- `StarterGui:SetCore`는 늘 바로 성공한다(Roblox에서는 시작 직후 「아직 등록되지 않았다」고 실패하는 때가 있어 다시 시도해야 한다).
- `Clone`은 속성 · 속성(Attribute) · 꼬리표 · 아이를 베낀다. 이벤트에 건 것은 베끼지 않는다(Roblox와 같다).
- 스크립트가 장을 넘기지 않고 끝없이 돌면(`while true do end`) mock도 멈춘다 — `--timeout`초 뒤에 끊는다.

**확인하지 못하고 넣은 가정(Studio에서 한 번은 확인해야 한다)**
- `AbsolutePosition`의 원점이 「Roblox 윗줄 아래」라는 것(`IgnoreGuiInset = true`인 화면 틀의 맨 위가 -58), `InputObject.Position` · `MouseButton1Down(x, y)` 도 같은 좌표라는 것, `GetMouseLocation()`만 화면 좌표라는 것 — 알려진 동작대로 넣었지만 이 세션에서 Studio로 확인하지 못했다.
- 윗줄의 높이 58픽셀(달의 계승자의 `stage.luau` 주석에 「58픽셀쯤」이라고 적혀 있다).
- `UIScale`이 제 틀의 크기 전체에 곱해진다는 것(달의 계승자의 `stage.luau`가 그렇게 쓰고 있어 그대로 따랐다).
- 새 플레이스의 이벤트 방식이 Deferred라는 것.
- 글의 폭 어림(한글 한 자 = 0.85 x TextSize)은 재 본 값이 아니다.

## 고칠 때

- 새 클래스의 동작은 `runtime/` 의 모듈에서 `Inst.hook("클래스")` 에 건다(`get` · `set` · `after` · `methods` · `defaults` · `init`). 이름은 API 덤프에 있어야 한다(없으면 첫 사용 때 「mock 안쪽 오류」).
- API가 바뀌면: `node tools/mock/fetch-ref.mjs --force` → `node tools/mock/gen-api.mjs`.
- 스크립트에 주는 전역을 더하면 `runtime/main.luau`의 `RT.setup`과 `bundle.mjs`의 `GLOBALS`에 같이 적는다.
- `typeof` · `type` · `require` · `script` 는 전역이 아니라 **스크립트마다 첫 줄 앞에 붙이는 지역 변수**다(`local script,require,typeof,type=...;` — 줄 번호는 밀리지 않는다). Luau가 내장 `typeof`를 바로 부르지 않게 하려는 것이다.
