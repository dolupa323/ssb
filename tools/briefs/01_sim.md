# Task: port the simulation (`js/sim.js`) to Luau, with a parity harness

Read `c:\YJS\Roblox\ssb\tools\briefs\00_common.md` first and obey it.

## Context
Original: `c:\YJS\Roblox\ssb\commute-survival\js\sim.js` (827 dense lines, no DOM, ends with `module.exports` so node can `require` it). It is a "survivors-like": 16 weapons, 16 passives, 5 fusions, 8 enemy types, 7 bosses, 7 zones, hazards (bus/train), a bot (`bot()`), level-up choice generation, etc. Read the whole file carefully before writing anything.

## Deliverable 1 — `c:\YJS\Roblox\ssb\src\shared\Sim.luau`
A faithful, line-by-line port of sim.js as ONE pure-Luau ModuleScript (no Roblox APIs, no `require`, so it runs both in Roblox and under luau.exe). Start it with `--!native` and `--!optimize 2`. Same constants, same formulas, same order of operations, same order of RNG calls as the JS — with the same random sequence both must produce the same game.

API (keep JS names wherever possible):
```lua
local Sim = require(path.to.Sim)
-- constants/tables exported under their JS names: GAME_LEN, WMAX, EVO, PMAX, MAX_W, MAX_P, LANE_GAP, LANE_H, TRAIN_LEN,
-- GATE_GAP, GATE_PER, GATE_HALF, GATE_TH, AISLE, DOOR_PER, DOOR_OPEN, ESC_W, ESC_PUSH, SPIN_R, ZONES, STOPS, LAST_STOP, GATE,
-- DIFFS, WEAPONS, PASSIVES, FUSIONS, ENEMIES, PHASES, MACE, BOMB, GUARD ... (export every top-level const a renderer/UI could need)
-- plus explicit key-order arrays (Luau tables have no insertion order): WEAPON_ORDER, PASSIVE_ORDER, FUSION_ORDER, ENEMY_ORDER,
-- and ordered key lists for the ZW[...] weights.
Sim.xpNeed(l); Sim.clockText(t)
local sim = Sim.create(host, opts)   -- = createSim
-- host = { sfx = function(name, x, arg) end, banner = function(a, b, kind) end, shake = function(a) end,
--          levelUp = function(choices, pickMode) end, finish = function(won) end }   (JS host.end -> host.finish: `end` is a keyword)
-- opts: same as JS (diff, restore, build, demo, autoPick, xpMul, botRange) plus opts.rng = function(): number in [0,1) (default math.random)
sim.S; sim.update(dt, view); sim.choose(i); sim.reroll(); sim.dash(); sim.bot(); sim.serialize(); sim.dbg
```
Conventions (follow them and document them in a header comment):
- Numeric state that is 0-based in JS stays numerically identical: `S.zone` (0..6; index ZONES with `S.zone+1`), `S.diff`, `S.stopIdx`, the lead boss's `day`, `e.st`, etc. Arrays (`S.enemies`, `S.shots`, `S.ev`, `choices`, `pts`, …) are normal 1-based Lua sequences. `sim.choose(i)` takes a 1-based index.
- JS relies on object key insertion order in several places (`for k in WEAPONS`, `Object.keys(S.weapons)`, `for fk in S.fus`, ZW weights, `Object.keys(o).length`, …). Reproduce the exact JS iteration order: use the constant order arrays, and for the dynamic maps `S.weapons`, `S.passives`, `S.fus` maintain insertion-order lists (`S.wOrder`, `S.pOrder`, `S.fOrder`) updated on add/delete (JS `delete` then re-add moves a key to the end) and on restore/build. The UI reads these lists to draw slots in order.
- Swap-remove / splice / shift semantics must match the JS exactly (iteration direction included), since they affect later iteration order.
- Handle each JS-ism deliberately: `|0`, `>>1`, `%` on negatives, `Math.round`, `Math.sign`, `Math.hypot`, `Math.atan2`, truthiness (0, '' and undefined are falsy in JS; 0 and '' are truthy in Lua), comparisons with undefined fields (`e.intro>0` when intro is undefined is false), `(l=Wp.card)` being falsy when 0, `x||y` defaults, array `.length=0`.
- Events: `S.ev` is an array of tables with field `k` (same field names as JS). `host.sfx(name, x, arg)` arguments as in JS.
- Performance matters (runs every frame with up to ~450 enemies): prefer numeric for-loops, avoid creating closures per enemy in hot paths where that is easy, but never at the cost of fidelity.

## Deliverable 2 — parity harness in `c:\YJS\Roblox\ssb\tools\parity\`
- A node runner that loads the ORIGINAL sim.js with `Math.random` replaced by a seeded PRNG, and a Luau runner using the identical PRNG through `opts.rng` (both must yield bit-identical doubles, e.g. a 32-bit generator returning s/2^32 — mind `Math.imul`/`bit32` semantics).
- Scenario A (exact trace): bot-driven runs with `autoPick` drawing from the seeded RNG, fixed dt = 1/60, fixed `view = {w=1280,h=720}`. Print a digest line every N ticks (t, player x/y/hp/level/xp, kills, #enemies, #beans, #bullets, zone, phase, sums of enemy x and y, number of RNG calls so far) and diff JS vs Luau. They should match exactly (or to ~1e-9 relative) for a long time. If they diverge, find the first diverging tick and the cause. Port bugs must be fixed. Accept a divergence as floating-point noise (V8 vs MSVC libm in sin/cos/atan2/exp/pow) only if you demonstrate it (identical RNG-call counts and state up to a tiny epsilon that then grows). The RNG-call counter is the best early detector of a logic mismatch.
- Scenario B (coverage): every code path must execute under Luau without runtime errors and agree with JS: every weapon at every level 1..7, every fusion, every enemy type, every boss (including rage stages and all `lead` phases), every zone kind (use `opts.build`, `opts.restore`, `dbg.enterZone`, `dbg.boss`, `dbg.spawn`), hazards, items, the `chest` and `start` pick modes, reroll, dash, serialize → restore round trip, player death, victory. `opts.demo` disables damage — also run non-demo games to the end.
- Scenario C (statistics): at least 10 seeds of full non-demo bot games per difficulty in both implementations; compare aggregate outcomes (final zone, time, level, kills) to show the distributions agree.
- Performance: ms per `update` at ~300–450 live enemies under `luau.exe -O2` (and with `--codegen` if this build supports it).
- One command reruns everything (`node tools/parity/run.mjs`) and prints a clear PASS/FAIL summary.
- `c:\YJS\Roblox\ssb\tools\parity\SIM_API.md`: a compact reference for the people who will write the renderer and UI on top of Sim.luau — the API, every way the Luau `S` differs from the JS `S` (indexing, order lists, renamed fields), all event kinds in `S.ev` with their fields, all `host.sfx` names with their arguments, all `host.banner` kinds, and all entity arrays with their fields.

## Finish
Reply with: files created, the exact PASS/FAIL output of the harness, where/when traces diverge (if they do) and why, the perf numbers, and anything you could not verify.
