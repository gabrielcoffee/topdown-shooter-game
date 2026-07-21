# SPEC — Wave-Survival Zombie Game

**Ship date: August 2, 2026. Price: $1 on itch.io. This scope is CLOSED.**

Progress is tracked in PROGRESS.md. Build order is in PLAN.md. Cut ideas go to SEQUEL.md, never into the codebase.

**All live gameplay numbers are in `tune.lua`** — edit it with any text editor, press U in game to reload + restart the run. TUNE values in this spec are design intent; `tune.lua` is the live truth.

---

## Core Loop

**kill → earn → spend → survive**

Player fights endless waves of zombies in one arena, earns money per kill (by weapon used), spends it on doors and two in-level shop NPCs, survives as long as possible. Death → score screen → restart.

## Arena

- Exactly **1 arena**, built as a **tile map designed in Tilesetter**: CSV grid of tile IDs + tileset PNG, loaded by `core/map.lua`. Level definition (CSV path, tile-ID→type mapping, object placements) lives in `maps/level1.lua`.
- Arena size comes from the CSV (cols × rows × tile size). Must be at least one screen (640×480 world px) or the camera clamp inverts. Current placeholder: 40×30 tiles = 1280×960.
  - TUNE: tile size = `32` (world px)
- Camera follows the player, clamped to the map edges. Player and zombies cannot leave (border walls + hard clamp).
- Until a real tileset PNG is exported, tiles draw as colored squares per type.

### Tile types

| Type   | Effect                                                                 |
|--------|------------------------------------------------------------------------|
| ground | Walkable. Player's last ground position = hole respawn point.           |
| solid  | Blocks player, zombies, crates. Stops bullets.                          |
| spikes | TUNE: `20` damage/sec to player AND zombies while standing on.          |
| water  | Max speed × TUNE: `0.75` for anything in it.                            |
| mud    | Acceleration and deceleration × TUNE: `0.25`.                           |
| hole   | Player falls → respawn at last ground spot, −TUNE: `50` HP. Zombie falls → dies (no kill money). Crate falls → plugs the hole (tile becomes ground). |

### Movement (player, zombies, crates)

Velocity-based with acceleration/deceleration (new — was instant):
- TUNE: accel time = `0.15` sec to max speed
- TUNE: decel time = `0.10` sec to stop
- TUNE: collision inset = `4` px (AABB shaved per side so 32px bodies fit 32px gaps)

### Map entities (interactive, free-positioned, in `maps/level1.lua` objects list)

- **Crate** — solid 32×32. Player pushing against it for TUNE: `0.5` sec starts it moving freely with the push (not grid-snapped). Blocked by solids/doors/other crates; affected by water/mud; plugs holes.
- **Locked door** — solid 32×32 with per-door price (fallback TUNE: `250`). Touch + `E` with enough money → pay, door opens (removed).

## Waves

- Endless. Wave N ends when all its zombies are dead; short breather, then wave N+1.
- Zombie count and mix scale with wave number.
  - TUNE: zombies in wave 1 = `5`
  - TUNE: zombies added per wave = `2`
  - TUNE: seconds between waves = `5`
  - TUNE: wave number when fast zombies start appearing = `3`
  - TUNE: wave number when runner zombies start appearing = `6`
  - TUNE: spawn distance from player (min) = `300`

## Zombies — 3 types, same behavior

All zombies: move straight toward player, deal contact damage on touch (with per-zombie damage cooldown so contact doesn't insta-kill). No other AI.

Life scales with wave: **base life = 20 × wave** (TUNE: +20 per wave), then per-type multiplier.

All types deal the same contact damage: TUNE: `10`, at most once per second per zombie (TUNE: cooldown `1.0`).

| Type   | Speed      | Life mult        | Size (px)             |
|--------|------------|------------------|-----------------------|
| Slow   | TUNE: `30` | TUNE: `×2`       | TUNE: `48` (1.5x)     |
| Fast   | TUNE: `60` | TUNE: `×1`       | TUNE: `32` (base)     |
| Runner | TUNE: `90` | TUNE: `×0.5`     | TUNE: `21` (1/1.5x)   |

Wave 1 life: slow 40, fast 20, runner 10.

- TUNE: contact damage cooldown per zombie = `1.0` sec

## Player

- WASD move, mouse aim/shoot (already working).
- Walk speed depends on held item (each weapon's `walkSpeed`, all TUNE): knife 130 > USP 120 = grenade 120 > Lupara 100 > M4A1 90 = AK-47 90.
- HP; death at 0 → score screen → restart.
  - TUNE: player max HP = `100`
- Armor (bought at item shop): absorbs damage before HP.
  - TUNE: armor points per purchase = `50`
  - TUNE: armor max = `100`
- Starting loadout: pistol + knife.
  - TUNE: starting money = `0`

## Economy

- Money per kill, by the **weapon that landed the killing blow** (not zombie type). Money is both currency and score.
  - TUNE: kill reward knife = `50`
  - TUNE: kill reward pistol = `20`
  - TUNE: kill reward AK / M4 / shotgun = `10`
  - TUNE: kill reward grenade = `10`
- HUD shows money under HP. Doors (and later shops) spend it.

## Shops — 2 NPCs standing in the arena

Walk up + interact key opens shop menu. Game keeps running or pauses — TUNE: shop pauses game = `yes`.

- TUNE: shop interact key = `e`
- TUNE: shop interact radius = `48`

### Gun shop NPC — the existing 6 weapons only

Damage on the "×10 simple scale": one significant digit each, room to nudge without decimals.

| Weapon  | Display name | Damage | Price          |
|---------|--------------|--------|----------------|
| Pistol  | USP-45       | TUNE: `20` | TUNE: `0` (starting weapon) |
| AK      | AK-47        | TUNE: `40` | TUNE: `1200`   |
| M4      | M4A1 (silenced, 25-rd clip) | TUNE: `35` | TUNE: `1500` |
| Shotgun | Lupara (sawed-off double barrel) | TUNE: `10` per pellet ×14 | TUNE: `1800` |
| Knife   | M9 Bayonet   | TUNE: `60` | TUNE: `0` (starting weapon) |
| Grenade | M67 Frag     | TUNE: `120` (flat inside radius) | TUNE: `300` (per grenade) |

- Buying a gun you own refills its ammo. TUNE: ammo refill price = `250`
- Reload: `r` key refills clip from reserve; reserve refills only via shop.

### Item shop NPC — armor + health only

| Item   | Price        | Effect                          |
|--------|--------------|---------------------------------|
| Health | TUNE: `500`  | TUNE: heal amount = `50` HP     |
| Armor  | TUNE: `750`  | +armor (see Player section)     |

## Screens — exactly 3

1. **Title** — game name, Play button, Quit button. Nothing else.
2. **Run** — the game. HUD: HP, armor, points, wave number, ammo.
3. **Death/score** — final score (points earned total), waves survived, Restart button.

No pause menu, no settings screen, no win screen (game is endless).

## Flavor text

Allowed: shop NPC one-liners, title tagline, death screen quip. That is the entire story budget.

---

## Existing-code notes (do not "fix" unless it blocks a feature)

- Dead files deleted 2026-07-20: `menu.lua` (was broken), `core/background.lua`, `entities/grenade.lua`, `core/sound.lua` (all stubs/unused). Title/death menus (step 11) and grenade (step 9) get built fresh.
- HUD draws at native resolution (not pixel-scaled); world sprites stay pixel-scaled at `SCALE`.

---

## ❌ CUT LIST — out of scope, do not implement, suggest, or scaffold for

If any of these come up mid-build, the answer is no. They go to SEQUEL.md if they survive the cut.

- Building systems
- Ladders / vertical traversal
- Multiplayer
- Story content beyond flavor text
- Additional maps / arenas
- Additional weapons beyond the existing 6
