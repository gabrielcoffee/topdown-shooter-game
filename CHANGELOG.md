# CHANGELOG

One entry per completed PLAN.md step. Newest on top. Format: date — step — what changed, player-visible terms.

## [Unreleased]

### 2026-07-20 — Speed tweak + test spawn key
- Rifles both 90 walk speed, Lupara 100
- Z key spawns one of each zombie type around player (debug)

### 2026-07-20 — Walk speed per weapon, real gun names, zombie speed bump
- Held weapon sets walk speed (knife 130 … AK-47 90)
- Real names in HUD: USP-45, AK-47, M4A1, Lupara, M9 Bayonet, M67 Frag
- Zombie speeds: slow 40, fast 70, runner 110
- SEQUEL.md created (machinegun, alien gun — cut)

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
