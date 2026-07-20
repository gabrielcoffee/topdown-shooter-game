# CHANGELOG

One entry per completed PLAN.md step. Newest on top. Format: date — step — what changed, player-visible terms.

## [Unreleased]

### 2026-07-20 — Cleanup, hi-res HUD, zombie type test
- Deleted dead files: menu.lua, core/background.lua, entities/grenade.lua, core/sound.lua
- HUD now drawn at native resolution with clean 18px font (world stays pixelated)
- 3 zombie types spawn around player for speed/size testing: Slow (red, 1.5x), Fast (magenta, base), Runner (yellow, small)

### 2026-07-20 — Step 1: Player HP, death, restart
- Player has 100 HP, shown in HUD
- Zombies deal 10 contact damage (1 sec cooldown per zombie)
- HP 0 → "YOU DIED" overlay, R restarts the run

### 2026-07-20 — Project docs
- Added SPEC.md (locked design, TUNE values), PLAN.md (13-step build order), PROGRESS.md (checklist), CHANGELOG.md, .gitignore

### Before docs (commits `4f67ae9`, `a011508`)
- Player movement, mouse aim, 6 weapons drawn, shooting with bullet damage, one test enemy, animations, dust background
