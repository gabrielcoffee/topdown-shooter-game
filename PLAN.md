# PLAN — Build Order

Rule: game playable end-to-end as early as possible — Phase 1 closes the loop, everything after improves a working game. Ugly beats polished. No refactors unless a step is blocked. Details live in SPEC.md; playtest instructions come after each step is built.

## Phase 1 — Close the loop
1. Player HP, zombie contact damage, death → restart
2. Endless wave spawner
3. Points on hit and kill

**→ Loop exists here: spawn, fight, earn, die, restart.**

## Phase 2 — Shops
4. Starting loadout (pistol + knife) + reload
5. Gun shop NPC
6. Item shop NPC (health + armor)

## Phase 3 — Variety
7. 3 zombie types (slow / fast / runner)
8. Knife works (melee fallback)
9. Grenade works
10. Arena bounds

## Phase 4 — Ship
11. Title + death/score screens
12. Tuning pass (yours — playtesting)
13. Ship build on itch ($1)

## Not on this plan (see SPEC cut list)
Building, crates, ladders, multiplayer, story, extra maps, extra weapons. New ideas → SEQUEL.md.
