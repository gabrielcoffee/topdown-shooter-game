# PROGRESS

What has shipped, and what is built but not yet playtested. Build order lives
in PLAN.md; player-visible detail per release lives in CHANGELOG.md.

## 🚀 Releases

| Version | Date | What |
|---|---|---|
| **1.1 — The Multiplayer Update** | 2026-08-17 | LAN co-op 4p, downed & revive, voice, scoreboard, free window resize. Desktop only. |
| **1.0 web** | 2026-08-14 | Browser build live at 60fps, singleplayer, ships from `web-release` |
| **1.0** | 2026-08-06 | First public release on itch.io (Windows / macOS / Linux) |

itch.io: https://coffeebreak1.itch.io/zombiechamber

## Built and shipped, never formally playtested

Everything through 1.0 was built, shipped and tuned by playing it, but the
per-step playtest column was never filled in and is not worth reconstructing.
Steps 1-14 in PLAN.md are all live in the released game.

## 1.1 — needs playtesting with real people

This is the only open item that matters, and none of it can be checked alone:

- [ ] **Co-op balance.** Wave quotas, zombie counts and prices are all still
      the numbers a solo run was tuned against. Four players on a map built for
      one is the obvious thing to be wrong.
- [ ] **Revive timings.** `bleedOutTime` 30s, `reviveTime` 4s, `crawlSpeed`
      0.35 — all guesses against BO2, none of them felt in a real fight yet.
- [ ] Voice: whether nearby-only is fun or just annoying, and whether the
      `proximityRange` of 420px is the right distance
- [ ] Whether a wide monitor showing more of the room is an advantage worth
      caring about in co-op
- [ ] Drop-in join mid-wave: does landing next to the group feel right, or
      should a joiner wait for the wave to end?

## Playtest notes log

(append dated impressions here — these drive TUNE values)
