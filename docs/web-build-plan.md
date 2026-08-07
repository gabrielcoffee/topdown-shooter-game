# Web Build Plan — Zombie Chamber in the browser

Goal: `coffeebreak1.itch.io/zombiechamber` playable in-browser, ~8MB download, 60fps on a
mid laptop, one command to ship an update. Desktop builds keep full quality and are not
touched.

Toolchain: [Davidobot/love.js](https://github.com/Davidobot/love.js) (LÖVE 11.5 + current
Emscripten), **compatibility mode** (`-c`). Compat mode disables pthreads, which is what
forces the audio decisions below. The non-compat build restores threads but needs
SharedArrayBuffer headers (itch has an experimental toggle) and is flakier across browsers —
not worth the risk for a game that doesn't need threads.

Upload target: `coffeebreak1/zombiechamber:html5`.

---

## Divergences from desktop (the only things a player could notice)

| | Desktop | Web |
|---|---|---|
| Menu music | `no_birds.mp3`, 12.8 min, 320kbps | ~60s ogg loop |
| Ambience beds | 77–94s ogg, streamed | ~40s ogg loops, static |
| Dev console (T) | on if `TUNE.dev.enabled` | always off |
| Menu QUIT item | quits the game | hidden |
| Boot fullscreen | applied from saved settings | ignored (browsers need a user gesture) |

Everything else — waves, weapons, map, tuning — is identical. `tune.lua` stays the single
source of truth; web overrides live in one table, not scattered.

Why the music has to shrink: compat mode has no threads, so `love.audio` **stream** sources
don't work — every source must be `static`, i.e. fully decoded into RAM. The 12.8-min track
as static PCM is ~135MB. There is no version of this plan where the full track ships to web.

---

## Phase 0 — Engine fixes (desktop benefits too)

These are real defects that happen to be fatal on WebGL.

1. **`lib/light_world/shaders/postshaders/blurv.glsl:6` and `blurh.glsl:6`**
   ```glsl
   for(int i = 1; i <= int(steps); i++)   // steps is a UNIFORM
   ```
   GLSL ES 1.00 (Appendix A) requires constant loop bounds. Fails to compile on WebGL1/ANGLE,
   and this shader runs **every frame** via `lib/light_world/init.lua:205`
   (`TUNE.lighting.shadowBlur = 2`, `tune.lua:508`).
   Fix: unroll to a fixed 2-tap radius, drop the `steps` uniform.

2. **`lib/light_world/postshader.lua:30-45` compiles all 18 postshader `.glsl` files at
   require time**, not on demand. Any single compile failure throws during
   `require('lib.light_world')` → startup crash with a black canvas and no error.
   Only `blurv`/`blurh` are ever invoked. `phosphor.glsl:85,93` also calls raw `texture2D()`
   instead of `Texel()`, which breaks under LÖVE's GLSL3 path.
   Fix: delete the 16 unused `.glsl` files.

3. **`main.lua:38` — `for _, a in ipairs(arg)`.** A love.js loader that omits
   `Module.arguments` leaves `arg` nil → hard crash in `love.load`. Fix: `arg or {}`.

4. **`core/decor.lua`** — declare the `vBounds` varying `highp`. On GLES2 it defaults to
   `mediump` in the fragment stage, and it clamps atlas UVs at `decor.lua:74`; ~1/1024
   precision can bleed neighbouring atlas cells.

**Verify:** desktop build runs, decor/lighting look unchanged, no shader warnings in stderr.

---

## Phase 1 — Build pipeline

New `build.sh web` target (existing targets untouched), producing `dist/web/`.

Steps it performs:

1. Stage a copy of the project into `dist/.cache/web-src/`.
2. **Transcode audio in the staging copy** (ffmpeg, already installed):
   - all `.wav` → `.ogg` q3
   - all short `.mp3` → `.ogg` q3
   - `assets/music/no_birds.mp3` → 60s loop, `.ogg` q3 mono-ish
   - `assets/sounds/ambient/*_bed.ogg` → 40s loops, q2
   - drop `assets/(outdated)/` entirely (1MB of dead files)
3. Drop a marker file `WEB_BUILD` into the staging copy (Phase 2 reads it).
4. Zip staging → `dist/.cache/ZombieChamber-web.love`.
5. `love.js -c -t "Zombie Chamber" -m <bytes> <love> dist/web/`
6. Overwrite the generated `index.html` with our template (below).

Free win: `core/audio.lua:135` already discovers `footsteps/`, `ambient/`, `zombies/` by
directory and accepts `ogg` — those transcode with **zero code changes**. Only the ~45
hardcoded paths at `core/audio.lua:20-72` need their extensions swapped, and that's done via
the web-flag indirection in Phase 2, not by editing the table twice.

**Custom `index.html`** — the love.js default is a white page with a bare progress bar. Ours:
- game-themed loading screen (black, Press Start 2P, progress bar) — first impression on itch
  is an 8MB download
- `preventDefault` on `wheel` (weapon cycling, `states/playing.lua:90`), `space`
  (menu activate, `ui/menu_list.lua:121`), `tab`, and `contextmenu`
- the IndexedDB sync glue from Phase 2

**Verify:** `python3 -m http.server` in `dist/web/`, game boots to menu in Chrome, Firefox,
Safari. Payload ≤10MB.

---

## Phase 2 — Web adaptations behind a flag

`_G.WEB = love.filesystem.getInfo('WEB_BUILD') ~= nil`, set early in `main.lua`. One flag,
checked in six places. No parallel codebase.

1. **Audio → static.** `core/audio.lua:325` (ambience bed) and `:397` (menu music) switch
   `'stream'` → `'static'` when `WEB`. Extension resolution for the hardcoded registry
   (`audio.lua:20-72`) goes through one helper that prefers `.ogg` on web.
2. **Global voice cap.** `TUNE.audio.poolSize = 8` per sound × ~60 registered names = a
   ~480-source ceiling, plus ad-hoc fire-loop sources (`audio.lua:248`). Desktop OpenAL
   absorbs this; OpenAL-wasm has a much tighter budget. Add a hard cap on live sources,
   stealing the one nearest completion (the per-pool logic at `audio.lua:168-186` already
   does exactly this — lift it to global).
3. **Save persistence.** `core/save.lua` is pure `love.filesystem` (good — it maps to an
   IDBFS mount), but nothing calls `FS.syncfs`, so writes never reach IndexedDB.
   - `index.html`: sync-on-dirty, debounced, plus on `pagehide` and `visibilitychange`.
   - Sync **once after `writeFile` returns**, never per-op — `save.lua:47-62` does 5 fs ops
     per save and would otherwise fire 5 IndexedDB transactions.
   - `main.lua:168` `love.quit` autosaves the run, but **tab close never fires `love.quit`**.
     Add a periodic run autosave on web (wave end + every 30s) so the
     "close the window, your run is there" contract survives.
4. **Menu QUIT hidden** on web (`states/menu.lua:43-46`) — `love.event.quit()` in a tab
   leaves a dead black canvas with no way back but a reload.
5. **Boot fullscreen skipped** on web (`main.lua:34` → `ui/screen.lua:80`). Browsers reject
   fullscreen without a user gesture. itch's auto-generated fullscreen button covers this.
6. **Dev console off** on web (`states/playing.lua:103`). Kills every remaining input
   conflict in one move: clipboard (`ui/chat.lua:308,426`, blocked in browsers anyway), Tab
   autocomplete (`chat.lua:470`), and Ctrl/Cmd+A/C/V/X (`chat.lua:415-441`).

Also silently degraded, no action needed, noted so nobody hunts for them later: OpenAL EFX is
absent in love.js, so reverb (`core/audio.lua:147-154`, already `pcall`-guarded) and the
lowpass wall-occlusion / pause-muffle filters (`audio.lua:197,225,463-523`) become no-ops.
Volume ducking still works. Web will sound slightly flatter. Acceptable.

**Verify:** saves survive a tab close and reopen. Music loops without a gap. No console
errors on wheel/space/tab.

---

## Phase 3 — Performance pass

The unknown. Measure before tuning — do not pre-optimise.

The hot path is `lib/light_world/init.lua:133-208` (`drawShadows`): **per visible light** it
does a full-screen `shadowMap` clear, two `love.graphics.stencil` passes, per-body shadow
geometry, and a full-screen shader pass. Light count = player + one per torch tile
(`core/lighting.lua:98`, `torchRange = 190`) + muzzle flashes + fire patches. Realistically
6–10 lights on screen → 6–10 full-screen clears and shader passes per frame, before moonshine
adds 2 (gameplay) to 9 (menu). Stencil-heavy multipass is precisely where WebGL trails native.

Levers, cheapest first:
- `TUNE.lighting.shadowBlur` → 0 (removes 2 full-screen passes/frame)
- cap simultaneous lights on web, nearest-first
- `crtInGame` default off on web (drops the overlay chain from gameplay)
- `glowStrength = 4` (`tune.lua:426`) → `support = 12` → 25 texture fetches × 2 passes,
  full-screen, in the **menu**. Halve it for web if the menu stutters.
- particle capacities (`core/vfx.lua`: fire 900, dust 600, boom 300) scaled on web
- `core/world.lua:582` allocates a comparator closure and sorts the visible list every frame —
  hoist the closure (helps desktop too)

Two of the seven light_world canvases (`init.lua:76-82`) are allocated but never used
(`glowMap`, `refractionMap` — `disableGlow`/`disableMaterial` set at `core/lighting.lua:61`).
Free VRAM if it matters.

Web-specific values live in a `TUNE.web` override table applied at boot when `WEB`, so
`tune.lua` stays the one place numbers live.

**Verify:** 60fps at wave 10 with 60 zombies alive (`tune.lua:590 maxAlive`) in Chrome and
Firefox on the MacBook. Record the numbers in PROGRESS.md.

---

## Phase 4 — itch.io deploy

One-time setup (manual, ~2 min, can't be automated):
1. `brew install butler && butler login`
2. Edit game page → **Kind of project: HTML**
3. First push, then tick **"This file will be played in the browser"** on that upload
4. Embed: **960×720**, click-to-play on, auto-generate fullscreen button on,
   **mobile-friendly off** (aim is absolute mouse position, `main.lua:149` — touch can't play it)

Then forever after:
```sh
butler push dist/web coffeebreak1/zombiechamber:html5 --userversion 1.0.0
```
Same channel = the playable build updates in place. Desktop uploads are untouched and keep
showing as downloads below the game frame.

---

## Phase 5 — Automation

`deploy.sh` — build + push, version from the current git tag:
```sh
./deploy.sh web        # build.sh web  → butler push :html5
./deploy.sh all        # every platform, every channel
```

**Pre-push smoke test.** A love.js shader-compile failure is a *silent black canvas* — no
error, no crash, nothing in the itch UI to tell you the build is dead. Headless Chrome loads
`dist/web/index.html`, waits for the canvas to paint non-black, screenshots it, and fails the
deploy if it doesn't. Cheap insurance against shipping a brick.

**Page text stays manual.** itch's server API is read-only — it can query games, keys and
purchases, but has no write endpoints for the Edit-game form. Only a scripted browser login
could change page copy, which is fragile and ToS-grey. Instead: `docs/itch-page.md` holds the
page copy as source of truth, so updating the live page is a copy-paste, not a rewrite from
memory. Devlogs likewise.

---

## Not doing

- **Mobile/touch controls.** Absolute-position mouse aim; a touch scheme is a different game.
- **LÖVE 12 / love-web-builder.** Would mean an engine upgrade onto an experimental SDL3
  Emscripten port. Revisit only if 11.5 web perf is unsalvageable.
- **SharedArrayBuffer / threaded love.js.** Restores audio streaming, costs browser
  compatibility. Only if the static-audio route proves unworkable.
- **Splitting assets into lazy-loaded packs.** ~8MB in one blob is fine for itch. Complexity
  with no payoff at this size.
