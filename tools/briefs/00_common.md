# Common rules for every worker on this project

Project: porting the browser game 「출근길 서바이벌」 to Roblox as a pure-GUI 2D game. Root: `c:\YJS\Roblox\ssb`. Read `c:\YJS\Roblox\ssb\CLAUDE.md` and `PLAN.md` first.

## Hard rules
- NEVER write, modify or delete anything outside `c:\YJS\Roblox\ssb`. `C:\YJS\Roblox\sprite-gen\` is a different, live game ("달의 계승자") — read/copy-from only.
- Do not launch or control Roblox Studio (one is open on this machine with that other game — leave it alone). Do not run `rojo serve`. Do not use port 34872. No git commits.
- `c:\YJS\Roblox\ssb\commute-survival\` is the original game: read-only reference. Patched copies go under your own `tools\<area>\work\` folder.
- Send nothing about this project or its user to any external service.
- Code comments in Korean, concise. The user is Korean.
- Report honestly: never claim a check you did not run; say what you could not verify.

## Machine
- node v25 (global `fetch`, `WebSocket`; avoid npm installs), python 3.10, Rojo 7.5.1 (`rojo build` is fine, `rojo serve` is not).
- Chrome: `C:\Program Files\Google\Chrome\Application\chrome.exe`; Edge: `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`.
- Luau CLI: `c:\YJS\Roblox\ssb\tools\luau\luau.exe`, `luau-analyze.exe`, `luau-compile.exe`. If that folder is missing or empty, create it and copy the four `.exe` from `C:\YJS\Roblox\sprite-gen\SpriteDemo\tools\luau\` (copy only). The CLI has `buffer`, `bit32`, `coroutine`, `os.clock`, `print`, file-based `require("./file")`, but NO `io` library: a Luau script cannot read files. Generate `.luau` files from node and read results from stdout.
- A shell-safety check on this machine sometimes transiently fails ("classifier gave no verdict"). If that happens, retry the same command a moment later; meanwhile continue with file reads/writes.
