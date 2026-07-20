# Ammo & Reload — Design

Date: 2026-07-20
Scope: PROGRESS.md Phase 2, Step 4 (reload half; starting loadout separate).

## Decisions

- **Trigger**: R key anytime clip not full; firing on empty clip auto-starts reload.
- **Ammo model**: pooled reserve. Reserve is a bullet count (`bulletsLeft`, starts at maxClip × 3). Reload tops the clip up from the pool; leftover clip bullets are kept, never lost. Enables per-bullet ammo purchases at the Phase 2 shop.
- **Weapon switch mid-reload**: cancels the reload. No bullets move, timer progress lost. Switching back requires restarting the reload.
- **Firing while reloading**: blocked.

## Architecture

**Gun class (`hand_items/gun.lua`)** owns everything ammo: clip count, reserve pool, reloading state and timer, and the reload logic itself (start, tick, complete, cancel). Existing fields `curClip`, `bulletsLeft`, `reloadingTime` are already there; this adds the reloading state machine plus a stored `maxClip` (needed for top-up math).

**Player (`entities/player.lua`)** only wires input:
- R key (edge-detected, same pattern as `leftReleased`) starts reload on the held item if it is a gun.
- Changing `itemIndex` cancels any reload on the previously held item.
- Trigger pull on an empty clip starts reload instead of firing.

Gun identification: check the object itself (guns get an `isGun` flag), not hardcoded item slot indexes. Replaces the existing `itemIndex == 1 or 2 or 3 or 4` check in Player, which breaks if item order changes.

**HUD (`Gun:drawHud`)**: `Ammo: <clip>/<reserve>`. While reloading, show reloading status instead of the count.

## Edge cases

- Reload refuses to start when: already reloading, clip full, or reserve empty.
- Reload completion transfers `min(maxClip − curClip, bulletsLeft)` — partial top-up when reserve runs low.
- Shotgun: one trigger pull = 7 pellets but 1 shell from clip (current behavior, unchanged; clip of 7 = 7 shells).
- Clip empty AND reserve empty: gun dead. Trigger does nothing (until shop exists to buy ammo).

## Out of scope

Starting loadout changes, shop purchasing, reload sound/animation, ammo pickups.

## Testing

Manual playtest: fire to empty (auto-reload kicks in), R mid-clip (leftovers kept), switch mid-reload (cancelled, nothing lost), drain reserve to partial top-up, fully dry gun stays dead. Note results in PROGRESS.md playtest log.
