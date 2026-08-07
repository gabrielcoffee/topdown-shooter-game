# Web Build — Zombie Chamber in the browser

Status: **built and working.** `./build.sh web` produces an 8.5MB `dist/web/`
that runs the real game in Chrome, Firefox and Safari. The only thing left is
the one-time itch.io setup, which needs Gabriel's login (see Deploying).

Toolchain: [Davidobot/love.js](https://github.com/Davidobot/love.js) 11.4.1
(LÖVE 11.5 + Emscripten), **compatibility mode** (`-c`). Compat mode has no
pthreads, which is what forces the audio decisions below. The threaded build
restores streaming but needs SharedArrayBuffer headers and is flakier across
browsers — not worth it for a game that never used threads.

Upload target: `coffeebreak1/zombiechamber:html5`.

```sh
./build.sh web        # -> dist/web/  (~90s first time, ~20s after: audio is cached)
node web/smoke.js     # loads the real build in Chrome, proves it draws
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
| Lights on screen | unlimited | 2 nearest |
| Shadow softness | `shadowBlur = 2` | 0 (hard edges) |
| Light pass resolution | full canvas | half (`shadowScale = 0.5`) |
| Dev console (T) | on | off |
| Menu QUIT | quits | hidden |
| Boot fullscreen | applied | ignored (needs a user gesture) |
| Run save | on window close | every 30s |

Everything else — waves, weapons, map, tuning — is identical. Web values live
in `TUNE.web` in `tune.lua` and are folded over the real values at boot by
`core/web.lua`; anything not listed there keeps its desktop value. The two
builds are told apart by a single marker file that `build.sh web` drops into
the package.

Silently degraded, no action needed: OpenAL EFX does not exist in love.js, so
reverb and the lowpass wall-occlusion / pause muffle become no-ops. Volume
ducking still works. Web sounds slightly flatter.

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
| Lighting disabled entirely | **60** (vsync cap) |
| 1 light | 37 |
| 2 lights (shipping) | **~30** |
| 3 lights | 24 |
| 4 lights | 21 |
| Unlimited (~5 on screen), before any of this work | 15 |

Lighting is the entire frame budget; everything else in the game runs at
vsync. The moonshine chain (CRT, vignette, grain) costs nothing measurable —
bypassing it changed nothing. Cost is **linear in light count**, roughly 7ms
per light, on top of ~10ms of fixed lighting overhead.

What was tried and what it bought:
- **Half-resolution light buffers** (`shadowScale`) — barely moved it. Proof
  the bottleneck is not fill rate. Kept anyway; it is free.
- **Cutting wasted passes** — the always-empty normal map rebuild and the
  identity blur. Worth a few fps.
- **Capping light count** (`maxLights`) — the only big lever. 15 → 30fps.

The remaining cost is per-light framebuffer and stencil churn: each light
means its own buffer clear, ~3 stencil clears and a full-buffer shader pass,
and Apple's tile-based GPU hates that pattern. Getting past ~30fps would mean
changing how shadows are drawn — the standard trick is to drop the stencil and
just draw shadow polygons in black over the light gradient, which needs no
stencil buffer at all. That is a real rewrite of `light_world`'s core and would
change desktop rendering too, so it is deliberately **not** done here. If 30fps
in the browser turns out to bother people, that is the next move.

Cost of the cap, visually: only the 2 nearest lights (always including the
player's) cast their pool. Distant torches still show their flame sprite but
light nothing. In a dark game it is noticeable if you look for it.

---

## Size

8.5MB total: 4.5MB `love.wasm`, 3.6MB `game.data`, 118KB font, rest loader.
Down from 44MB of raw assets — 30MB of which was the single music track.
Nowhere near itch's limits (500MB extracted, 1000 files, 200MB/file).

`build.sh web` caches the encoded audio in `dist/.cache/web-audio`, so only
the first build pays the minute of ffmpeg. Delete that folder to force a
re-encode after changing a sound.

---

## Deploying

One-time, needs Gabriel (butler login is interactive):

1. `brew install butler && butler login`
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
