# CHANGELOG

One entry per completed PLAN.md step. Newest on top. Format: date — step — what changed, player-visible terms.

## [Unreleased]

### 2026-07-29 — Inventory stacks, quick-knife, spawn/economy rebalance
- Slot 4 is now ONE shared pool: 4 throwables total, any mix of grenades and molotovs
- Slot 5 stacks 2 med kits; using one keeps the kit out while a spare is left
- Med kit HUD tells you what it's worth: "MED KIT x2" + "CLICK: HEAL +50 HP"
- Quick-knife: Q (or pressing 3 while the knife is out) flicks to the knife and back
  to whatever was in hand, with a 0.15s deploy instead of 0.3s
- Waves start at 5 zombies (was 4) — every wave is +1
- Fast zombies show up on wave 3 (was 4); the heaviest mix starts wave 6 (was 8)
- Money: USP 8/hit + 15 kill, AK 5/hit, molotov 5/burn tick, knife kill bonus 30
- Mystery box $300 (was $350); freeze / double points / fire sale last 20s (was 30)
- /give medkit added to chat

### 2026-07-21 — Mystery box, 5-slot hotbar, grenade throw, med kit (steps 4/5/6/9)
- Shops cut: loot now comes from a BO2-style mystery box chest ($150, reusable, 2s spin)
- Gun rolls need a second E within 5s or they're lost; duplicate gun = full ammo refill
- Loot odds: AK 15% / M4 15% / Shotgun 10% / grenade 30% / med kit 30% (full categories reroll)
- New inventory: [1] gun A, [2] gun B, [3] knife, [4] grenades x3 max, [5] med kit — keys 1-5
- Minecraft-style hotbar bottom center: icons, selection highlight, clip/grenade counters
- Start loadout is now USP + knife only (was: everything)
- Grenades throw toward the cursor: 1.2s fuse, 80px blast, 120 flat damage, blast light + particles
- Med kit heals 50 on click, consumed; auto-switch to knife when a slot empties
- Run save carries the new inventory; old saves load with health/money kept

### 2026-07-20 — tune.lua: all gameplay numbers in one file
- Every tunable value (guns, zombies, player, bullet) moved to tune.lua
- U key reloads tune.lua and restarts the run — edit/save/U tuning loop, no IDE needed

### 2026-07-20 — Uniform contact damage + diagonal speed fix
- All zombie types deal 10 contact damage (fast was 15), 1s cooldown per zombie unchanged
- Fixed diagonal movement being 1.41x faster (vector normalized)

### 2026-07-20 — Simple-scale damage rework + wave-scaling zombie life
- Weapon damage on x10 scale: shotgun 10/pellet, pistol 20, rifles 40, knife 60, grenade 120
- Zombie life = 20 x wave, with multipliers: slow x2, normal x1, fast x0.5
- Zombie speeds: 30 / 60 / 90

### 2026-07-20 — Circle hitboxes + zombie separation
- Placeholder entities draw as outline circles (not filled boxes)
- H key toggles green collision-circle overlay on all entities (works over sprites)
- AABB check kept as collidesWithBox for future rectangular colliders
- All entity collision now circle-based (radius = half sprite width), no library
- Zombies push apart each frame — no more stacking into one blob
- (user-built) Reload system: R key, clip/reserve, reload cancel on weapon switch

### 2026-07-20 — Speed tweak + test spawn key
- Rifles both 90 walk speed, Shotgun 100
- Z key spawns one of each zombie type around player (debug)

### 2026-07-20 — Walk speed per weapon, real gun names, zombie speed bump
- Held weapon sets walk speed (knife 130 … AK-47 90)
- Real names in HUD: USP-45, AK-47, M4A1, Shotgun, M9 Bayonet, M67 Frag
- Zombie speeds: slow 40, normal 70, fast 110
- SEQUEL.md created (machinegun, alien gun — cut)

### 2026-07-20 — Cleanup, hi-res HUD, zombie type test
- Deleted dead files: menu.lua, core/background.lua, entities/grenade.lua, core/sound.lua
- HUD now drawn at native resolution with clean 18px font (world stays pixelated)
- 3 zombie types spawn around player for speed/size testing: Slow (red, 1.5x), Normal (magenta, base), Fast (yellow, small)

### 2026-07-20 — Step 1: Player HP, death, restart
- Player has 100 HP, shown in HUD
- Zombies deal 10 contact damage (1 sec cooldown per zombie)
- HP 0 → "YOU DIED" overlay, R restarts the run

### 2026-07-20 — Project docs
- Added SPEC.md (locked design, TUNE values), PLAN.md (13-step build order), PROGRESS.md (checklist), CHANGELOG.md, .gitignore

### Before docs (commits `4f67ae9`, `a011508`)
- Player movement, mouse aim, 6 weapons drawn, shooting with bullet damage, one test enemy, animations, dust background
