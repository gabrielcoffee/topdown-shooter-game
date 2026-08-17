# PLAN — Build Order

Rule: game playable end-to-end as early as possible — Phase 1 closes the loop, everything after improves a working game. Ugly beats polished. No refactors unless a step is blocked. Details live in SPEC.md; playtest instructions come after each step is built.

## Phase 1 — Close the loop ✅
1. Player HP, zombie contact damage, death → restart
2. Endless wave spawner
3. Points on hit and kill

**→ Loop exists here: spawn, fight, earn, die, restart.**

## Phase 2 — Mystery box (was: shops) ✅
4. Starting loadout (pistol + knife) + reload
5. 5-slot inventory + hotbar UI (keys 1-5)
6. Mystery box chest (random loot: guns / grenades / med kit)

## Phase 3 — Variety ✅
7. 3 zombie types (slow / normal / fast)
8. Knife works (melee fallback)
9. Grenade works
10. Arena bounds

## Phase 4 — Ship ✅
11. Title + death/score screens
12. Tuning pass (yours — playtesting)
13. Ship build on itch ($1) — **v1.0 live 2026-08-06**

## Phase 5 — Web ✅
14. Browser build via love.js, playable on the itch page — **live 2026-08-14**
    at 60fps. See [docs/web-build-plan.md](docs/web-build-plan.md). Ships from
    the `web-release` branch, NOT from main.

## Phase 6 — LAN co-op ✅ — **v1.1 "The Multiplayer Update", 2026-08-17**
15. Net layer: wire format, ENet transport, UDP discovery beacon
16. Session state machine, player names, server browser + lobby
17. The networked run: host-authoritative, inputs up / snapshots down
18. Downed & revive, per-player money, scoreboard, chat, voice
19. Free window resizing (the blue-band fix that came with it)

Desktop only. A browser tab cannot open a UDP socket, so love.js has no ENet
and MULTIPLAYER is hidden there entirely.

## Not on this plan (see SPEC cut list)
Building, ladders, story, extra maps, extra weapons, shop NPCs, armor.
New ideas → SEQUEL.md.

## Next up — undecided
Nothing is committed after 1.1. The open candidates, roughly in the order they
would pay off:

- **Playtesting co-op with real people.** Nothing below is worth starting first.
  Four players on one map balanced for one is the obvious risk: wave quotas,
  zombie counts and wall-buy prices are all still solo numbers.
- Host migration, or at least a clean "the host left" instead of ending the run
- More maps — the single map is the most-asked-for thing on the itch page
- Steam, which would want lobbies over the internet rather than LAN
