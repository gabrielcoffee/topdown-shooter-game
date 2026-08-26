# CLAUDE.md

Top-down zombie shooter in LÖVE (Lua). Plan in PLAN.md, progress tracking in PROGRESS.md.

## Working with Gabriel

- **After implementing any feature, end with a simple summary of the most important data/tune values**, as a bullet list, so he can track what's going on and know what to ask to change. Example:
  - ak reload time: 2.7s
  - pistol reload time: 2s
- **Commit only when a feature feels finished** — not every prompt. Commits authored as gabrielcoffee, never any Claude attribution or Co-Authored-By trailer. Push after committing.
- Design/plan discussions stay at macro level (which class owns what, how pieces talk). No function-by-function detail unless asked.
- **`tune.lua` is the source of truth for all gameplay numbers.** Gabriel edits it directly (sometimes in other sessions) — always re-read it before reporting or changing values, never trust conversation memory. New tunable values go in tune.lua, not hardcoded. U key in game reloads it + restarts run.
- **Full-autonomy mode (standing order).** When Gabriel leaves details open or says "come up with the rest / offer ideas": research how the best games/tools do it (web search when useful), decide, and ship a complete polished version — no stubs, no "you could also...". Reference real games (Minecraft, CoD, etc) for feel. Offer 1-3 extra ideas beyond the ask: implement the cheap high-value ones, list the rest for him to pick.

## Running and testing

```sh
love .                        # play it
love . selftest               # ~190 scripted checks; exits nonzero on failure
bash tools/lantest.sh         # two-process LAN co-op run (-v dumps both logs)
love . autotest               # screenshot a run to the save dir, then quit
```

`love . selftest` is the regression gate: it drives a real World through the
input struct rather than the keyboard, so gameplay, co-op rules and the wire
format are all covered without a human at the controls. Run it before any
commit.

Screenshot autotests, one per screen — each writes `autotest.png` to the LÖVE
save dir and quits:

    autotest  autotest_downed  autotest_score  autotest_controls
    autotest_menu  autotest_options  autotest_mp  autotest_lobby
    autotest_keys  autotest_splash  autotest_names

Promo screenshots for the itch page and posts:

```sh
bash tools/promo.sh          # all four into dist/promo/
bash tools/promo.sh fight    # just one
```

Four staged 4-player runs — `squad`, `fight`, `revive`, `board`. The names,
wave number and money are set in `main.lua` under the `promo_` args; edit them
there. Shots come out at the window size, so they are capped by the display.

Add-on args: `shot<N>` screenshots at frame N instead of 90, and
`win<W>x<H>` forces a window size first (`love . autotest win1280x700` — odd
window shapes are what the resize code gets wrong).

`love . fpsprobe` prints framerate, draw calls, and the window / canvas /
light-buffer sizes that have to agree.

## Shipping

```sh
./build.sh                 # dist/ -- mac .app, windows .exe, linux .love, all zipped
./deploy.sh desktop        # build + butler push to itch
./deploy.sh web            # browser build, smoke-tested, pushed  (see below)
```

**The web build ships from the `web-release` branch, never from `main`.** `main`
carries the LAN multiplayer code, which must not enter the browser build — a
tab cannot open a UDP socket, and love.js has no ENet. `ls core/ | grep net`
must come back empty in a web-release worktree before pushing. Full procedure
in [docs/web-build-plan.md](docs/web-build-plan.md).

Version lives in two places and both must move together: `ui/theme.lua`
(`Theme.version`, drawn on the menu) and a git tag (which `deploy.sh` reads for
the itch userversion).
