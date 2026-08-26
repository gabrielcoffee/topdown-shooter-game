# CHANGELOG

One entry per completed PLAN.md step. Newest on top. Format: date — step — what changed, player-visible terms.

## Unreleased — co-op presence

Everything here is about what a teammate looks and sounds like from the other
side of the room. Nothing changes solo.

- **Other players move smoothly.** They used to jump from one network update to
  the next, which looked fine on a fast LAN and terrible on anything else.
  Now every remote body — teammates and zombies both — glides toward where the
  host says it is, and keeps moving on its last known speed between updates.
- **Names float over your teammates**, colored per player, fading with distance
- **You hear teammates reload**, and see the reload, from wherever they are
- **Their guns kick, rack and throw casings** when they fire, instead of firing
  a noise and a muzzle flash with a motionless gun underneath
- Picking things up stays silent to everyone else — a room full of other
  people's inventory clicks is noise, not information

## 1.1 — 2026-08-17 — THE MULTIPLAYER UPDATE

**LAN co-op for up to 4 players, and the window finally resizes.** Download
builds only — the browser version stays singleplayer, because a tab cannot
open a UDP socket.

### Multiplayer
- **MULTIPLAYER on the main menu.** Hosts announce themselves on your network
  once a second, so joining a friend normally needs no typing at all. Direct IP
  is still there for networks that block broadcast.
- Four-player lobby: names, ready flags, and the host's voice-mode toggle
  (everyone hears / nearby only)
- **Everyone plays in one world**: same zombies, same crates, same doors, same
  wave. The host runs the game and everyone else follows it, 60 times a second
- **Money is per player** — you buy your own wall gun, your own box roll. Doors
  open for everybody once one of you pays
- **Voice chat**: hold V to talk. Nearby-only mode makes a teammate two rooms
  away fade out
- **Chat**: press T and type. No slash needed any more
- **Scoreboard**: hold TAB for names, health, score and cash, and a marker
  next to whoever is talking
- **Join a run in progress** — you drop in next to the group with the doors
  they already bought open

### Downed & revive (co-op only)
- Hitting 0 HP puts you on the floor instead of ending the run: you crawl, you
  bleed, and the screen closes in red as the clock runs down
- A teammate holds E for 4 seconds to pick you up, and gets you back on full
  health. Letting go early loses all the progress
- 30 seconds to bleed out. If nobody reaches you, you sit out the rest of the
  wave and come back on the next one with the starting pistol — your money is
  safe
- **Singleplayer is unchanged**: 0 HP is still death, exactly as in 1.0

### The window
- **Resize the window to any size you like**, by dragging its edge. The game
  fills whatever shape you give it
- Fixed: a blue band along the bottom of the screen on laptops (most MacBooks),
  where the game was asked for a window taller than the screen could show
- Wider than 4:3 now shows more of the room, rather than bars
- Resolution list starts at NATIVE, so a first run fits the screen it lands on
- Fixed: the game could open on a second monitor whether you had one or not

### Notes
- macOS and Windows builds now include a README explaining the first-launch
  security warning and how to get past it (both are unsigned; installing
  through the itch.io app skips it)

## 1.0 — 2026-08-06 — FIRST RELEASE

**This is Zombie Chamber v1.0 — the first public release (itch.io).** Every entry below is part of it.

### 2026-08-06 — Release polish
- Crates pay: every weapon hit on a crate earns half that weapon's per-zombie
  hit money (zombie chewing pays nothing)
- Map updated for 1.0; nightmare-wave carriers never drop a nuke anymore
- Game named ZOMBIE CHAMBER (final); v1.0 shown bottom-right on the menu
- Music credit ("MUSIC: NO BIRDS - FRED FRITH") shows for 3s on every menu visit
- Mystery box reworked: 15% gun base odds +2.5% per grenade/molotov/med kit held
  (full inventory = guaranteed gun); consumables drawn from a shuffle bag
- Med kits: carry 3, heal is a 2.5s channel (bar over the hotbar) — you can run
  while healing and while reloading now
- Wall prices: AK $950, M4 $800, shotgun $1200; ammo refill 50% of gun price
- Shotgun pump: 0.7s between shots
- The killing hit's money popup shows hit reward + kill bonus as one sum
- Fixed: chat sometimes refusing input after cmd-tabbing back into the game

### 2026-07-29 — Grenade + med kit sounds, 1s use cooldowns
- CS-style pin pull when a grenade comes into hand (deploy, type cycle, and again
  when the throw cooldown ends with another one in the bag)
- Throw whoosh on release; med kit has a bandage-wrap + confirm-chime heal sound
- Grenades and med kits can only be used once per second — the hotbar slot dims
  and a bar fills back along its bottom edge while it cools down

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
