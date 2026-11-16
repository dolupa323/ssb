# 새 컨셉용 임시 에셋 조사

쓴 날: 2026-11-16. 이야기와 대응표는 [STORY.md](STORY.md). **아직 아무것도 게임에 넣지 않았고, 내려받지도 않았다** — 무엇을 쓸 수 있는지만 조사했다.

표의 「확인」 칸은 제가 **직접 읽은 것**만 「읽음」이라고 적었다. 검색 결과의 요약으로만 본 것은 「요약으로만」이라고 적었다 — 쓰기 전에 그 페이지를 직접 열어 확인해야 한다.

---

## 1. 이미 갖고 있는 것 (`C:\YJS\Roblox\` 안)

| 묶음 | 자리 | 라이선스 | 상업 게임에 써도 되나 | 확인 |
|---|---|---|---|---|
| **Ninja Adventure** (Pixel-boy · AAA) | `Ninja Adventure - Asset Pack\` | **CC0 1.0** — 「상업 게임에도 써도 된다. 출처 표시는 안 해도 되지만 고맙다」 | ✅ 된다 · 표시 의무 없음 | `LICENSE.txt` · `README.md` 읽음 + [itch 페이지](https://pixel-boy.itch.io/ninja-adventure-asset-pack) 읽음 |
| **Tiny Questers — Free Starter Pack** (Bobddadoo) | `Assets\Topdown\tiny-questers-free-starter-pack\` | 「개인 · 상업 프로젝트 모두 무료」 · 그림을 묶음째 다시 나누거나 팔지 말 것 · AI 학습에 쓰지 말 것 (GameDev Market 약관을 따름) | ✅ 된다 | `README.txt`의 라이선스 부분 읽음 (GameDev Market 약관 원문은 읽지 않음) |
| **Luneblade / Jesshiyoo 묶음** (Little Riven · Mooni · Axion · Reaper …) | `Assets\character\Luneblade…` | 「개인 · 상업 프로젝트에 써도 된다 · 고쳐도 된다 · 표시는 안 해도 됨」 · 되팔기 · 다시 나누기 · NFT · AI 학습 금지 | ✅ 되지만 **쓰지 않는 편이 낫다** — 달의 계승자의 주인공 그림이라 두 게임이 같은 얼굴이 된다 | `License.txt` 읽음(Little Riven 것) |
| **TOP-DOWN Adventure Pack** (o_lobster) | `Assets\Topdown\Top_Down_Adventure_Pack_v.1.0\` | itch 페이지의 표기로는 **CC BY 4.0**(출처 표시를 하면 상업 사용 가능) | ⚠️ 될 것으로 보이나 확인 필요 — 쓰면 「o_lobster」 표시 | 폴더의 `README.txt`에는 만든 이 이름만 있음. 라이선스는 [itch 페이지](https://o-lobster.itch.io/adventure-pack) — **요약으로만** |
| **Little Dreamyland — Free Pack** (Starmixu · Utaskuas) | `Assets\Topdown\Little Dreamyland - Free Pack\` | 「**비상업 프로젝트에 무료**」 · 표시 의무 | ❌ **안 된다** — 로블록스에 내는 게임은 수익이 나는 상업 프로젝트다 | `LICENSE.txt` 읽음 |
| The Fan-tasy Tileset (Free) · Tiny Adventure Pack Plus · TAP_Enemies_v2 · `sound\sonniss_gdc2024` · `sound\boss_candidates` | `Assets\map` · `Assets\Topdown` · `Assets\sound` | — | ❓ **모른다** | 라이선스 글을 찾아 읽지 않았다 |

### Ninja Adventure 묶음에 들어 있는 것 (폴더를 직접 세어 봄)

| 폴더 | 개수 | 쓸 곳 |
|---|---|---|
| `Actor/Character` | 95종 (Boy · Child · NinjaBlue · Master · OldMan …). 한 종마다 `Walk` · `Idle` · `Attack` · `Dead` · `Jump` · `Special1` · `Special2` · `Item` · `Faceset` · `SpriteSheet` | 주인공 · 사범 · 마을 사람 |
| `Actor/Monster` | 66종 (Slime 1~4 · Mushroom · Octopus · Racoon · Mouse · Owl · Bear · Panda · TRex · Bamboo · Kappa · Spirit · Snake · Bat …) | 적 8종 — 대응표의 것이 모두 있음 |
| `Actor/Boss` | 20종 (GiantRacoon · GiantFrog · GiantBamboo · TenguRed/Blue · GiantSlime · DemonCyclop · GiantRedSamurai · DragonBlue/Green · GiantSpirit · Squid …) | 보스 7종 — 대응표의 것이 모두 있음 |
| `Actor/Animal` | 27종 | 배경의 동물 |
| `Items/Projectile` | Shuriken · Kunai · Caltrop · Bomb · Dynamite · Arrow | 수리검 · 표창 · 마름쇠 · 폭탄 |
| `Items/Weapons` | 23종쯤 (Lance · Whip · Ninjaku · Katana · MagicWand · Hammer · Sai · Bow …) | 창 · 채찍 · 쌍절곤 · 구슬 |
| `Items/Food` | 24종 (Onigiri · Sushi · TeaLeaf · Seed 여러 종 · Nut · Noodle …) | 주먹밥 · 경험치 조각(콩 · 밤) |
| `Items/Scroll` · `Potion` · `Treasure` | 7 · 6 · 10 | 부적 · 두루마리 · 보물 상자 |
| `FX` | Attack · Elemental · Magic · Particle · Projectile · Slash · Smoke | 무기 효과 · 「펑」 연기 |
| `Backgrounds/Tilesets` | 20종 (Field · House · Nature · Towers · Floor · FloorB · Water · Relief · Interior · Dungeon · Desert …) | 장소 7곳의 바닥 |
| `Backgrounds/Vehicles` | Boat · Crane · FishNet · Sail뿐 | **수레 · 열차가 없다** |
| `Ui` | 있음(세지 않음) | 임시 UI |

**이 묶음으로 덮이지 않는 것** (만들거나 따로 구해야 함):
- 돌진하는 **멧돼지 수레**(원본의 버스)와 **급행 열차**(원본의 열차 · 열차 안의 벽 · 문)
- **도는 삿갓**(원본의 백팩 회전)
- 폭포 돌계단의 **물살이 흐르는 그림**(원본의 에스컬레이터 발판)
- 소리: 내려받아 둔 폴더에 **음악 · 효과음이 없다**(그림 폴더만 있다). itch 페이지에는 「음악 37곡 · 효과음 100개 이상」이 들어 있다고 적혀 있으니, 쓰려면 다시 내려받아야 한다.

**그림을 하나하나 열어 보지는 않았다.** 본 것은 묶음의 미리보기 그림 한 장(`preview-part-1.png`)과 폴더 · 파일 이름이다. 도트 크기는 16x16, 위에서 본 그림.

---

## 2. 인터넷에서 구할 수 있는 것 (내려받지 않음)

| 이름 | 라이선스 | 들어 있는 것 | 확인 |
|---|---|---|---|
| **Kenney의 모든 에셋** | **CC0** — 「상업 프로젝트에도 자유롭게 · 출처 표시 불필요」 | 2D · 3D · 소리 · UI 수백 묶음 | [kenney.nl/support](https://kenney.nl/support) 읽음 |
| Kenney — Tiny Dungeon | CC0 | 16x16 타일 130개 (던전 · 하수도) | [페이지](https://kenney.nl/assets/tiny-dungeon) 읽음 |
| **0x72 — 16x16 DungeonTileset II** | **CC0 1.0** (코드는 MIT) — 「마음대로 써도 된다」 | 16x16 던전 타일 · 기사 · 마법사 · 고블린 · 좀비 등 | [페이지](https://0x72.itch.io/dungeontileset-ii) 읽음 |
| Ninja Adventure (전체판) | CC0 | 위의 것 + 음악 37곡 · 효과음 100개 이상 · 글꼴 2개 | [페이지](https://pixel-boy.itch.io/ninja-adventure-asset-pack) 읽음 |

찾아보지 않은 것: OpenGameArt의 CC0 묶음들, 로블록스 Creator Store의 무료 에셋, 무료 음악. 필요하면 이어서 조사한다.

---

## 3. 에셋을 밖에서 안 구하는 길 — 원본의 그림 코드를 고쳐 그리기

지금 게임의 그림은 파일이 아니라 **동업자분의 코드가 그린 것**이고(`commute-survival/js/gfx.js`), 이것을 `tools/bake`가 아틀라스로 굽는다. 캐릭터는 「몸 색 · 머리 모양 · 얼굴 · 앞뒤에 붙는 소품」을 적은 표(`SPR`)로 만들어진다.

- **할 수 있는 것:** 그 표를 고쳐 닌자 옷 · 몬스터 모양을 새로 그리고 다시 굽는다. 저작권 문제가 전혀 없고(우리 코드가 그린 그림), **지금의 매끈한 그림체가 그대로** 유지된다.
- **드는 것:** 몬스터 8종 + 보스 7종 + 무기 소품 + 바닥 6장을 코드로 새로 그려야 한다. 사람 모양 틀(`chibi`)은 사람만 그리므로 슬라임 · 문어 같은 것은 그리는 함수를 새로 써야 한다.
- 원본을 고치지 않고 `tools/bake/work` 아래 복사본에서 한다(지금 굽는 도구가 이미 그렇게 한다).

---

## 4. 정리 — 어느 길로 갈 수 있나

| 길 | 임시 에셋으로 바로 되는가 | 그림체 | 저작권 |
|---|---|---|---|
| **가. Ninja Adventure(CC0)를 그대로** | 거의 다 된다(수레 · 열차 · 삿갓 · 물살만 만들면 됨) | 16x16 도트로 통째로 바뀜 | 문제 없음(CC0) |
| **나. 원본 그림 코드를 고쳐 새로 그림** | 그릴 것이 많다 | 지금 그림체 유지 | 문제 없음(우리 것) |
| **다. 섞기** — 캐릭터 · 몬스터는 나, 아이콘 · 음식은 가 | 그림체가 섞여 어색할 수 있다 | 섞임 | 문제 없음 |

제 의견: 「임시」로 빨리 보려면 **가**, 낼 때의 그림으로는 **나**가 맞다고 봅니다. 어느 쪽이든 [STORY.md](STORY.md)의 대응표는 그대로 씁니다. — 이것은 판단이고, 고르는 것은 사용자와 동업자분의 몫입니다.

---

## 5. 쓸 때 지킬 것

- **Little Dreamyland Free Pack은 쓰지 않는다**(비상업 전용).
- CC BY 묶음(o_lobster)을 쓰면 게임 소개나 게임 안의 「만든 이」에 이름을 적는다.
- 「되팔기 · 다시 나누기 금지」인 묶음(Tiny Questers · Jesshiyoo)의 그림 파일은 **공개 저장소에 그대로 올리지 않는다** — 게임에 넣어 쓰는 것은 되지만, 그림 파일 자체를 깃허브에 공개하면 「다시 나누기」가 된다. `ssb` 저장소가 공개인지 비공개인지에 따라 달라진다(확인하지 않았다).
- 로블록스에 그림을 올리면 로블록스의 심사를 거친다. CC0 그림이라도 심사는 따로다.
