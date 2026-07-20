# SPEC — Wave-Survival Zombie Game

**Ship date: August 2, 2026. Price: $1 on itch.io. This scope is CLOSED.**

Progress is tracked in PROGRESS.md. Build order is in PLAN.md. Cut ideas go to SEQUEL.md, never into the codebase.

---

## Core Loop

**kill → earn → spend → survive**

Player fights endless waves of zombies in one arena, earns points per hit and per kill, spends points at two in-level shop NPCs, survives as long as possible. Death → score screen → restart.

## Arena

- Exactly **1 arena**. The existing dust background + camera.
- Arena has fixed bounds (player and zombies cannot leave).
  - TUNE: arena width = `1280` (world px)
  - TUNE: arena height = `960` (world px)

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

| Type   | Speed      | Life mult        | Contact damage | Size (px)             |
|--------|------------|------------------|----------------|-----------------------|
| Slow   | TUNE: `30` | TUNE: `×2`       | TUNE: `10`     | TUNE: `48` (1.5x)     |
| Fast   | TUNE: `60` | TUNE: `×1`       | TUNE: `10`     | TUNE: `32` (base)     |
| Runner | TUNE: `90` | TUNE: `×0.5`     | TUNE: `15`     | TUNE: `21` (1/1.5x)   |

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
  - TUNE: starting points = `0`

## Economy

- Points per bullet hit and per kill. Points are both currency and score.
  - TUNE: points per hit = `10`
  - TUNE: points per kill (slow) = `50`
  - TUNE: points per kill (fast) = `75`
  - TUNE: points per kill (runner) = `100`

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
- Movable crates (incl. the "push crate" comment in `player.lua` — dead comment, ignore it)
- Ladders / vertical traversal
- Multiplayer
- Story content beyond flavor text
- Additional maps / arenas
- Additional weapons beyond the existing 6
