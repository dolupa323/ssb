# Task: the world renderer (port of `js/gfx.js`) for Roblox

Read `c:\YJS\Roblox\ssb\tools\briefs\00_common.md` first and obey it.

## Context
We are porting 「출근길 서바이벌」 to Roblox as a pure-GUI 2D game. Already done (read these before coding):
- `src\shared\Sim.luau` — the rules, a faithful port of `commute-survival\js\sim.js`. Reference: `tools\parity\SIM_API.md` (state layout, event kinds in `S.ev`, differences from the JS `S`).
- `src\shared\art\Atlas.luau`, `src\shared\art\pixels\*.luau`, `src\shared\art\Decode.luau`, `assets\*.png` — the original's art baked into atlas pages. Reference: `tools\bake\ART_NOTES.md` (sprite catalogue, what is baked, what must be rebuilt from primitives).
- `tools\mock\` — a headless harness that runs our client under luau.exe with a validating Roblox API mock and renders approximate screenshots. Reference: `tools\mock\README.md`. This is the only way to execute and look at your work (no Studio). Use it constantly.
- The original renderer: `commute-survival\js\gfx.js` (`render` starts near line 796, `resize` near 1197, public API near 1202). Read ALL of it; it is your spec. `js\main.js` shows how it is called.
- Technique reference (READ ONLY, another game of the same user): `C:\YJS\Roblox\sprite-gen\SpriteDemo\src\client\lune\stage.luau`, `sprite.luau`, `canvas.luau` — fixed-coordinate frame + `UIScale`, `ImageLabel` cutting atlas regions with `ImageRectOffset/ImageRectSize` (negative width = flip), `EditableImage` + `WritePixelsBuffer`.

Someone else is writing the UI/host in parallel (`src\client\init.client.luau`, `src\client\ui\*`, `src\client\Input.luau`, `src\client\Stage.luau`, `src\server\*`, `src\shared\Net.luau`). Do not create or edit those files. You own: `src\client\Art.luau`, `src\client\Gfx.luau`, `src\client\gfx\*.luau`, and your scenarios/scaffolding under `tools\world\`.

## Interfaces (fixed — the UI author codes against exactly this)
```lua
-- src/client/Art.luau : runtime access to the baked atlases
Art.init()            -- builds the pages. If `src/shared/art/AssetIds.luau` exists and has an id for a page ({ chars1 = "rbxassetid://123", ... }), use it;
                      -- otherwise decode the page's pixel module into an EditableImage (AssetService:CreateEditableImage + WritePixelsBuffer; pcall it, warn and
                      -- degrade gracefully if it fails). May yield (spread decoding across frames). Idempotent. Art.ready becomes true when done.
Art.ready : boolean
Art.info(name)        -- the Atlas.sprites entry (errors on unknown names)
Art.set(imageLabel, name, flip?) -> info   -- sets Image / ImageContent, ImageRectOffset, ImageRectSize (flip = negative width); does not touch Size/Position
Art.size(name) -> w, h                     -- size in world units (w/s, h/s)

-- src/client/Gfx.luau : mirrors the JS GFX object
Gfx.init(worldFrame, overlayFrame)   -- two full-screen Frames provided by the UI author (world layer below the UI; overlay = screen-space effects above the world, below the UI).
                                     -- Gfx reads worldFrame.AbsoluteSize as W,H, follows changes, and derives zoom as the original resize() does.
Gfx.reset()
Gfx.view() -> { w, h }               -- visible world size, as the original view()
Gfx.size() -> { W, H }
Gfx.render(S, o)                     -- o = { mode = "menu"|"play", dt, running, fx, offX, offY }; consumes S.ev exactly like the original
Gfx.shake(a); Gfx.celebrate(); Gfx.frozen() -> boolean
Gfx.opts({ fx = 0|1|2, shake = 0|1, bloom = 0|1 })
Gfx.icon(key, evo) -> string         -- sprite name usable with Art.set (weapons, passives, fusions, heal choices)
```
The on-screen joystick is drawn by the UI author, not by Gfx (ignore `o.joy`).

## What to build
A renderer that makes the game play and read like the original:
1. Gameplay-critical, must be faithful: camera and zoom; the floor of each of the 7 zones including everything the rules collide with or warn about (street lanes, turnstile rows and gaps, platform edge/track lanes, the train aisle and doors, escalator lanes and their push direction, office); bus/train hazards with their warning phase; player, enemies (correct sprite/variant/frame/facing, elite and boss scale, y-sorted), boss intro, hit flash; enemy bullets by kind; warning zones (with their text), sound-wave rings with the gap, slicks, puddles; beans and items; every weapon's and fusion's visuals (shots, orbiting packs, stab/swipe arcs, rings, zaps, scooters, selfie sticks, boomerang handles, alarm mines, lashes, laptop beams, gum, shoulder bumps, hotpack aura, mace, umbrella guard, coffee bombs, free-pass transfers …); everything driven by `S.ev` (damage numbers, kills, heals, zone change, boss speech `say`, etc.).
2. Juice, approximate is fine: particles, corpses/ghosts, screen shake, hurt/heal/flash overlays, zone wipe, celebration.
3. Lighting/bloom/vignette/ambient tint: simplified (e.g. a tinted overlay per zone); do not burn instances on it.

Roblox constraints and rules:
- Everything is GuiObjects: `ImageLabel` (atlas sprites via Art.set), `Frame` (+ `UICorner` for circles/pills, `UIStroke` for rings/outlines, `Rotation` for lines/beams, `UIGradient` sparingly), `TextLabel` (numbers, zone texts, speech; Korean text works with built-in fonts through fallback — use `Enum.Font` members that exist), `CanvasGroup` only if truly needed. No per-frame `Instance.new`/`Destroy` in steady state: pool everything, hide instead of destroy, and skip property writes whose value did not change (cache last values per pooled object). Budget: aim for ≤ ~1200 simultaneously visible GuiObjects in the worst case (≈450 enemies); scale particle/number counts with `opts.fx`; cull what is off-screen.
- Draw order by `ZIndex` under `ZIndexBehavior.Sibling` (layer frames + y-sort inside the entity layer).
- World → screen: put the world under one Frame with a `UIScale` (= zoom) and move a camera container, or compute screen coordinates yourself — choose what is cheapest and stays sharp; keep sprites `ResampleMode.Default` (the art is smooth vector, not pixel art).
- Arcs/sectors/partial rings cannot be drawn directly: approximate with a few rotated segments or sprites, keeping the gameplay meaning exact (where the gap is, how far it reaches).
- If you find art that should have been baked but was not, you may extend the bake (`tools\bake\`) and regenerate — keep `ART_NOTES.md` current.

## Measured in real Roblox Studio (2026-11-16, place ssb, `src\client\Smoke.client.luau`)
- All 13 pixel modules decode and become `EditableImage`s (138 ms total). `ImageLabel.ImageContent = Content.fromObject(img)` with `ImageRectOffset/ImageRectSize` works, including negative width (flip) and `ScaleType.Tile` + `TileSize` for a whole-page floor texture.
- 500 `ImageLabel`s cut from one EditableImage page: static 58 fps, moved every frame 58.7 fps (0.85 ms of script), moved + `ZIndex` rewritten every frame 51 fps. So position writes are cheap but ZIndex churn is not: write `ZIndex` only when its (coarse) bucket changes.
- Studio throttles to ~15 fps when its window is in the background — never read that as a renderer problem.
- `Sim.update` cost 0.015–0.026 ms at 20–54 enemies in Studio.
- `Smoke.client.luau` is a temporary test: it must not ship. The UI author deletes it when the real entry script lands.

## Verification (required)
- Write mock scenarios under `tools\world\` that create the two frames, run real `Sim` games driven by `sim.bot()` (and `opts.build`/`dbg` to force every weapon, fusion, boss and zone on screen), call `Gfx.render` every frame, and take screenshots at interesting moments at 1280×720 and 844×390. No runtime errors or mock validation errors across full games in every zone.
- LOOK at the screenshots (Read tool) and compare them with the original: render the same situations with the original page in headless Chrome (the original exposes `window.__dbg` when opened with `#dbg`; you can also drive its sim) and view both. Fix what looks wrong. Say plainly what still differs.
- Report per-frame cost under the mock in a heavy scene (instances visible, property writes per frame, ms per `Gfx.render` under luau.exe) and confirm the steady state creates no instances.
- Run `node tools/mock/analyze.mjs` and fix real findings in your files.

## Finish
Reply with: files created, the scenarios and their results (actual output), which screenshots you looked at and what you saw versus the original, known differences/omissions, performance numbers, and what could not be verified without real Roblox (list concrete things to check in Studio).
