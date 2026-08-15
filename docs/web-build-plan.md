# Web Build — Zombie Chamber in the browser

Status: **live and playable** at https://coffeebreak1.itch.io/zombiechamber —
`./build.sh web` produces an 8.5MB `dist/web/` that runs the real game in
Chrome, Firefox and Safari, at a locked 60fps. Note it ships from the
`web-release` branch, not `main` (see below).

Toolchain: [Davidobot/love.js](https://github.com/Davidobot/love.js) 11.4.1
(LÖVE 11.5 + Emscripten), **compatibility mode** (`-c`). Compat mode has no
pthreads, which is what forces the audio decisions below. The threaded build
restores streaming but needs SharedArrayBuffer headers and is flakier across
browsers — not worth it for a game that never used threads.

Upload target: `coffeebreak1/zombiechamber:html5`.

```sh
./build.sh web        # -> dist/web/  (~90s first time, ~20s after: audio is cached)
node web/smoke.js     # loads the real build in Chrome, proves it draws
node web/behaviour.js # canvas keeps focus through fullscreen; loop runs hidden
node web/perf.js      # framerate + WebGL call counts, real GPU window
./deploy.sh web       # build + smoke test + butler push
```

---

## What the browser build does differently

| | Desktop | Web |
|---|---|---|
| Menu music | `no_birds.mp3`, 12.8 min, 320kbps | 60s ogg loop |
| Ambience beds | 77–94s ogg, streamed | 40s ogg loops, static |
| All other audio | wav / mp3 | ogg q2 |
| Lights on screen | unlimited | 4 nearest |
| Shadow softness | `shadowBlur = 2` | 0 (hard edges) |
| Light pass resolution | full canvas | half (`shadowScale = 0.5`) |
| Dev console (T) | on | off |
| Menu QUIT | quits | hidden |
| LAN multiplayer | yes | not in the build at all |
| Boot fullscreen | applied | ignored (needs a user gesture) |
| Run save | on window close | every 30s |
| Pause | Escape | Escape **or P** — see below |

Everything else — waves, weapons, map, tuning — is identical. Web values live
in `TUNE.web` in `tune.lua` and are folded over the real values at boot by
`core/web.lua`; anything not listed there keeps its desktop value. The two
builds are told apart by a single marker file that `build.sh web` drops into
the package.

Silently degraded, no action needed: OpenAL EFX does not exist in love.js, so
reverb and the lowpass wall-occlusion / pause muffle become no-ops. Volume
ducking still works. Web sounds slightly flatter.

---

## What the tab takes away, and what it takes to get it back

Three things a browser does that a window does not. All handled in
`web/index.html`; `node web/behaviour.js` is what proves the last two still
work, since neither shows up in a screenshot.

**Escape never arrives.** It belongs to the browser (it exits fullscreen), so
the pause key had to be something else. **P** pauses and unpauses in the web
build, and the controls splash lists it there and only there.

**Fullscreen steals focus.** SDL only sees keys while the canvas has focus, and
both entering and leaving fullscreen hand focus back to the document — the game
kept running but ignored WASD entirely until you clicked it. Focus is taken
back on every `fullscreenchange` (and on the next frame after, for the browsers
that restyle late).

**A hidden tab gets no frames.** Background tabs get zero
`requestAnimationFrame` callbacks, which froze the run while its ambience
carried on playing. A Web Worker's timer drives the loop instead while hidden —
worker timers are not clamped the way window timers are. The catch that made
the first attempt fail: intercepting *future* rAF calls is not enough, because
the frame already handed to the browser is the one that would have asked for
the next. Every frame is tracked now, so the worker can run the outstanding one
itself. Hidden runs a little *faster* than visible (no vsync); LÖVE integrates
wall-clock dt, so the simulation speed is unaffected.

There is no CLICK TO PLAY gate any more. The runtime boots as soon as both
downloads land, behind nothing but a progress bar, and the AudioContext SDL
creates is resumed on the player's first click or keypress.

---

## Two bugs worth remembering

Both were invisible on desktop and would have shipped as "the browser version
looks broken".

**Every canvas was RGBA4444.** LÖVE's GLES2 path refuses to allocate a canvas
as RGBA8 unless the driver advertises `OES_rgb8_rgba8`, and WebGL never
advertises it — even though `RGBA`/`UNSIGNED_BYTE` textures are 8-bit there by
definition. So every render target had 16 levels per channel and every light
falloff came out as wide concentric rings. `web/index.html` swaps the
allocation type back to `UNSIGNED_BYTE` (and expands any 4444 upload into a
converted texture to match). This affects *any* love.js game, not just ours.

**`shadowBlur = 0` erased the world.** The blur shader ends
`return vec4(col.rgb, 1.0)`, and that alpha of 1 was load-bearing: the shadow
buffer gets multiplied over the scene, so a buffer left at alpha 0 multiplies
the world away to a blank blue screen. Upstream never noticed because it ran
the pass unconditionally. `light_world` now writes that alpha directly with a
colour-masked rect, which is also cheaper than the two full-buffer blits it
replaced.

---

## Performance — measured, not guessed

Real GPU, Chrome, 1280×960, wave 1. `node web/perf.js`.

| Configuration | fps |
|---|---|
| 4 lights (shipping) | **60** locked |
| Unlimited (~5 on screen) | 60 median, dips to 53 |
| 2 lights, before the stencil fix | 36 |
| Unlimited, before the stencil fix | 22 |
| Lighting disabled entirely | 60 (vsync cap) |

Lighting was the entire frame budget: 36fps with it on, a locked 60 with it
off. It was **draw calls, not fill rate** — which is why half-resolution light
buffers barely moved it, and why it hurt so much more in a browser than on
desktop. Every GL call from wasm crosses into JS.

The culprit was the stencil pass, not the shadows. `light_world` rasterises
each polygon occluder into its own `Image` at creation so the stencil pass can
stamp it. Every body therefore owns a *different* texture, so LÖVE's batcher
cannot merge any of them: 24 walls in light range × 2 lights was ~48
unmergeable draws a frame. `body:drawStencil` now draws the polygon geometry
instead — untextured, so consecutive bodies collapse into one draw. **130 draws
per frame → 86, and a locked 60.**

The shapes this relies on are convex (chamfered wall rects, crates, doors),
which is what `polygon('fill')` needs. The `image_mask` shader stays bound and
is harmless — an untextured draw samples LÖVE's 1×1 white texture, so nothing
discards.

What else was tried and what it bought:
- **Batching shadow quads into one mesh per light** — worth only ~3fps. LÖVE
  already merges consecutive untextured polygon fills, so these were never
  separate GL draws. Kept: it removes the per-edge Lua overhead.
- **Half-resolution light buffers** (`shadowScale`) — barely moved it. Kept; free.
- **Cutting wasted passes** — the always-empty normal map rebuild and the
  identity blur. Worth a few fps.
- **The moonshine chain** (CRT, vignette, grain) — 6fps at the old framerate
  (36 → 42 bypassed). Left on; it is the game's whole look and there is room now.

The `maxLights` cap is no longer the framerate dial. It went 2 → 4 once the
stencil fix landed: distant torches cast their pools again and it still never
drops a frame. Uncapped dips to 53 in a torch-heavy room, so the cap stays, but
it now costs nothing you can see.

Replacing the stencil approach with black shadow polygons over the light
gradient — the plan when 30fps looked like a rendering-technique problem — is
**not needed** and was not done.

---

## Size

8.5MB total: 4.5MB `love.wasm`, 3.6MB `game.data`, 118KB font, rest loader.
Down from 44MB of raw assets — 30MB of which was the single music track.
Nowhere near itch's limits (500MB extracted, 1000 files, 200MB/file).

`build.sh web` caches the encoded audio in `dist/.cache/web-audio`, so only
the first build pays the minute of ffmpeg. Delete that folder to force a
re-encode after changing a sound.

---

## The web build ships from its own branch

`main` carries the LAN multiplayer work, which is **download-only**. The
browser build is single-player and ships from **`web-release`**: branched at
`79a3225` (the last commit before multiplayer) with the web and perf work
cherry-picked on top.

So a web release is not `./deploy.sh web` on main. It is:

```sh
git worktree add /tmp/web-release web-release   # main stays untouched
cd /tmp/web-release
git cherry-pick <the web/perf commits from main>
ln -s /path/to/repo/node_modules .              # for the smoke test
./deploy.sh web
```

Check `ls core/ | grep net` comes back empty before pushing — that is the
cheapest proof no multiplayer code went into the browser build.

---

## Deploying

One-time, needs Gabriel (butler login is interactive):

1. `./deploy.sh install-butler`, then `butler login` (opens a browser — this is
   the step that cannot be automated). Note there is **no homebrew formula** for
   itch's butler: `brew install butler` installs Many Tricks' Butler.app, an
   unrelated task launcher. `install-butler` pulls the real one from
   `broth.itch.zone` into `~/.local/share/itch-butler` and symlinks it onto PATH.
2. itch.io → Edit game → **Kind of project: HTML**
3. `./deploy.sh web`, then tick **"This file will be played in the browser"**
   on the new upload
4. Embed: **960×720**, click-to-play on, fullscreen button on,
   **mobile-friendly off** — aim is absolute mouse position, touch cannot play it

After that `./deploy.sh web` is the whole story: it builds, refuses to push if
the smoke test cannot see a frame, and replaces the playable build in place.
Desktop uploads keep listing as downloads below the game frame.

**Page text stays manual.** itch's server API is read-only — it can query
games, keys and purchases, but has no write endpoint for the Edit-game form.
`DESCRIPTIONS.md` holds the page copy, so updating the live page is a
copy-paste rather than a rewrite.

---

## Not doing

- **Mobile/touch controls.** Absolute-position mouse aim; touch is a different game.
- **LÖVE 12 / love-web-builder.** An engine upgrade onto an experimental SDL3
  Emscripten port. Revisit only if 11.5 web support rots.
- **SharedArrayBuffer / threaded love.js.** Would restore audio streaming (so
  the full music track could ship) at the cost of browser compatibility.
- **Splitting assets into lazy-loaded packs.** 8.5MB in one blob is fine.
