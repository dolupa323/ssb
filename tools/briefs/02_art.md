# Task: bake the original's procedural art into atlases for Roblox

Read `c:\YJS\Roblox\ssb\tools\briefs\00_common.md` first and obey it.

## Context
The original game (`commute-survival\index.html`, `js\sim.js`, `js\gfx.js`, `js\main.js`) draws everything procedurally on a 2D canvas. `js\gfx.js` (1199 long lines, an IIFE `const GFX=(function(){…})()`) builds cached off-screen canvases with `mk(w,h,fn,ss)`: chibi characters (`SPR`, `sprite(type,v,frame,dir,fl)`), static sprites (`buildStatic()` → `ST.*`: beans, items, card, pack, cup, bullets `ST.bul[]`, stamp, door, table, track, tactile tile, …), glows, weapon/passive/fusion icons (`GFX.icon(key, evo)` returns a data URL), floor textures, vehicles (bus, train), etc. Read ALL of gfx.js and inventory every pre-rendered canvas and every piece of art the Roblox renderer will need as an image.

In Roblox the game is drawn with `ImageLabel`s that cut regions out of atlas pages (`ImageRectOffset`/`ImageRectSize`; horizontal flip = negative rect width). Roblox cannot run canvas code, so we bake the art by executing the original drawing code in headless Chrome. Drive Chrome over the DevTools protocol from node yourself (launch with `--headless=new --remote-debugging-port=<port> --user-data-dir=<temp dir under tools\bake\work>`), no npm installs. Check whether Pillow is importable before relying on python for images; PNG encoding can be done in the browser via `canvas.toDataURL`.

## Deliverables
1. `tools\bake\bake.mjs` (+ harness html/js): `node tools/bake/bake.mjs` regenerates everything below from the original source. It loads sim.js and a patched COPY of gfx.js that exposes the internals you need.
2. Atlas PNGs in `c:\YJS\Roblox\ssb\assets\` — each page at most 1024×1024, as few pages as reasonable, 1–2 px transparent padding between sprites, straight (non-premultiplied) alpha. Contents:
   - Characters: every `SPR` type × every variant × the distinct walk frames (find which of the 4 frames are identical and bake each distinct one once), facing right only. 2 atlas px per world unit for normal characters; a smaller density for the big boss sprites if needed to fit. Also a white-silhouette ("flash") version of every character sprite in the same layout on separate page(s) (same rects), used for hit flashes.
   - Every static sprite the renderer draws via `drawImage` (all `ST.*`, bullets, items, weapon projectiles/props, vehicles, floor/track/tile textures, glows/shadows/light) — 2 px per world unit unless huge.
   - Icons for all 16 weapons (normal and evolved), 16 passives, 5 fusions and the heal choices (`heal`, `heal2`) via the original icon code, sized for 64–96 px UI display.
   - Parts of the scene drawn directly in the render loop with canvas calls that would be impractical to rebuild from plain rectangles/circles in Roblox (e.g. the bus, train cars, turnstile cabinets, train interior fixtures, escalator steps, office props, repeating floor patterns): bake them too by calling the original draw code into an off-screen canvas. List what you baked and what you left for the renderer to rebuild from primitives.
3. `src\shared\art\Atlas.luau` — generated manifest (ModuleScript returning a table):
   ```lua
   return {
     pages = { { name = "chars1", file = "chars1.png", w = 1024, h = 1024 }, ... },
     sprites = {
       -- x,y,w,h in atlas pixels; s = atlas pixels per world unit; ox,oy = anchor in world units from the sprite's top-left
       -- (characters: the feet point SPR.ox, SPR.oy; centred sprites: the centre)
       ["char/pass/0/0"] = { page = 1, x = 0, y = 0, w = 96, h = 116, ox = 22, oy = 52, s = 2 },
       ["mask/pass/0/0"] = {...}, ["st/bean/0"] = {...}, ["icon/card"] = {...}, ["icon/card/evo"] = {...}, ...
     },
     -- per character type: what the renderer needs (variant count, frame remap for the 4-step walk, logical size, extra scale)
     chars = { pass = { nv = 4, frames = {0,1,2,1}, w = 48, h = 58, ox = 22, oy = 52, sc = 1 }, ... },
   }
   ```
   Clear, stable names; document the naming scheme at the top of the file.
4. Embedded pixel data so the game can run WITHOUT uploading images: for each page a ModuleScript `src\shared\art\pixels\<page>.luau` returning the page's pixels as compact 7-bit-ASCII string data (design a simple scheme — e.g. palette + run-length + a base64/base85 text encoding; the art is flat-coloured vector shapes with anti-aliased edges, so slight colour quantisation is fine if visually lossless), and a pure-Luau decoder `src\shared\art\Decode.luau` with `Decode.page(data) -> buffer, width, height` (RGBA8, w*h*4 bytes, row-major, straight alpha — what `EditableImage:WritePixelsBuffer` takes). Start Decode.luau with `--!native` and `--!optimize 2`; no Roblox APIs in it. Budget: all pixel modules together ideally under ~1.5 MB of source, no single module over ~900 KB; decoding everything should take well under a second in the plain interpreter (measure with luau.exe). If a page would blow the budget, reduce its density and say so.
5. Verification:
   - Under luau.exe: decode every page and compare a checksum (and the max per-channel error if you quantise) against the PNG's pixels computed in node. Report numbers.
   - Contact sheets (`tools\bake\out\contact_*.png`: every sprite on a mid-grey background with its name; character sprites next to the same character rendered by the original code at the same size). LOOK at them yourself with the Read tool. Fix anything cut off, misaligned, blank or wrong. Check anchors (feet on the anchor point).
6. `tools\bake\ART_NOTES.md`: the sprite catalogue (name → what it is, logical size, where the original draws it in gfx.js with line numbers), pages and sizes, the pixel-format description, how to rerun, and — for the renderer author — a list of everything in the original render loop that is NOT baked and must be rebuilt from primitives, with line references.

## Finish
Reply with: files created, page list with sizes (PNG bytes and Luau module bytes), decode timings and checksum results, what you visually checked and what you saw, the art deliberately not baked, and anything you could not verify.
