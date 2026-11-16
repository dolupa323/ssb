# Task: bake the original's synthesised audio to files and build the Roblox sound module

Read `c:\YJS\Roblox\ssb\tools\briefs\00_common.md` first and obey it.

## Context
The original game synthesises ALL audio at runtime with WebAudio: `commute-survival\js\audio.js` (261 long lines; object `AudioSys` with `init()`, `vol(music, sfx)`, `sfx(name, pan, arg)`, `music(state)`). Roblox cannot synthesise audio — it only plays uploaded audio assets. The user decided (2026-11-16): bake the original sounds, upload them, and use them. Uploading to Roblox is done later by someone else; your job ends with upload-ready files and a sound module that only needs asset ids filled in.

Callers: `js\sim.js` calls `host.sfx(name, x, arg)` (the host turns x into a pan), `js\main.js` calls `AudioSys.sfx(...)` for UI sounds and `AudioSys.music({scene, station, boss, muffled, late, lowhp, crowd})` every frame. Read audio.js completely, plus every call site, and list every sfx name with the `arg` values it is actually called with (some sounds change with `arg`: weapon source, evolved flag, countdown number, bean value, boss type …).

Roblox facts to design around (verify against the official docs at create.roblox.com/docs if unsure; do not guess silently): accepted upload formats include `.mp3`, `.ogg`, `.wav`, `.flac`; a clip may be at most 7 minutes; uploads are rate-limited per month and each file is moderated — so FEW files is much better than many. A `Sound` can play a sub-range of a longer asset with `PlaybackRegionsEnabled = true` and `PlaybackRegion = NumberRange.new(t0, t1)` (and `LoopRegion` for loops), so many effects can be packed into one "sound sheet" with silence gaps between them. Overlapping effects need several `Sound` instances (a small pool). `SoundGroup`s give separate music/sfx volume; an `EqualizerSoundEffect` can muffle; there is no simple stereo pan on a non-spatial `Sound` — dropping pan is acceptable.

## Deliverables
1. `tools\audio\bake.mjs` (+ harness page): `node tools/audio/bake.mjs` renders everything from the ORIGINAL audio.js code in headless Chrome (drive it over the DevTools protocol; no npm installs). Use `OfflineAudioContext` (or an equivalent faithful capture) through a patched COPY of audio.js under `tools\audio\work\` so the baked sounds are what the original really plays. Encode 16-bit PCM WAV yourself (44.1 kHz; mono where the source is effectively mono, to halve size).
2. Upload-ready files in `c:\YJS\Roblox\ssb\assets\audio\`:
   - Sound sheets: all one-shot effects (every name × every meaningful `arg` variant; where the original randomises pitch/timbre per call, bake a few variants) packed into as few WAV files as reasonable, each under 7 minutes, with ≥ 0.15 s of silence between entries and each entry trimmed to its audible length.
   - Music: understand how `music(state)` builds the soundtrack (menu vs play, per-station songs 0–4, boss layer, late/low-hp/muffled/crowd modifiers) and bake loopable pieces that let Roblox reproduce it sensibly: seamless loops per scene/song (exact loop length in the map), plus separate layers only where the original clearly layers. Modifiers such as muffled/late/low-hp should be done at runtime with volume/pitch/EQ rather than more files.
   - Keep the total number of files small (ideally ≤ 8) and report each file's duration and size.
3. `src\shared\SoundMap.luau` (generated): for every sfx name/variant → `{ sheet = "sfx1", t0 = 12.345, t1 = 12.801, vol = 1 }` and how `arg` selects a variant; for music → file, loop length, layers. `src\shared\SoundIds.luau`: `{ sfx1 = "", sfx2 = "", music_menu = "", ... }` — one entry per baked file, ids EMPTY (do not invent asset ids); a comment explains that the id of the uploaded file goes there as `"rbxassetid://123"`.
4. `src\client\Sound.luau` — the Roblox implementation with the original's interface:
   ```lua
   Sound.init()                      -- creates SoundGroups and the pooled Sound instances; safe to call more than once
   Sound.vol(music, sfx)             -- 0..1 each
   Sound.sfx(name, pan, arg)         -- plays the mapped region; unknown name → warn once; empty asset id → silent no-op
   Sound.music(state)                -- state = { scene = "menu"|"play"|"off", station, boss, muffled, late, lowhp, crowd }; called every frame, must be cheap and only act on changes
   ```
   Reproduce the original's rate limiting / voice stealing where it has any (e.g. many `hit` or `pick` calls in one frame must not spawn dozens of voices). No per-call `Instance.new` in steady state.
5. Verification:
   - LISTEN-equivalent checks you can actually do: for every baked entry compute peak and RMS and confirm it is not silent and not clipped; confirm entry boundaries (silence before/after); confirm music loops are seamless numerically (compare the samples around the loop point / render two loops and check continuity). Render spectrogram or waveform PNGs of the sheets and of a few entries and look at them with the Read tool.
   - Run `Sound.luau` under the headless mock (`tools\mock\`, see its README once it exists — it is being built in parallel; if it is not ready yet, write the test so it can be run later and say so): every sfx name the sim/UI can emit resolves to a map entry; calls with empty ids are silent no-ops without errors; with fake ids the right `SoundId`/`PlaybackRegion`/volume are set; the voice pool does not grow under a burst.
6. `tools\audio\AUDIO_NOTES.md` (Korean): the list of files to upload with durations, the full name → region table, what differs from the original (pan, dynamic layers, randomisation), and step-by-step what remains to be done after upload (which ids go where).

## Finish
Reply with: files created (with durations/sizes), the sfx name list with variants, how music was mapped, verification numbers and what you looked at, differences from the original, and anything you could not verify (nobody has listened to these files — say so).
