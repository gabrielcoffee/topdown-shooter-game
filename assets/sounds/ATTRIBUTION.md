# Sound attribution

All files converted to mono WAV (positional) or stereo OGG (ambient beds), renamed.

## CC0 (public domain, no attribution required — listed for provenance)
- **Gun shots** (usp/ak47/m4a1/shotgun_shot*): "The Free Firearm Sound Library" — https://opengameart.org/content/the-free-firearm-sound-library (1911, AK-47, AR-15, Mossberg recordings, trimmed)
- **Gun reloads** (usp_reload, ak47_reload, m4a1_reload*): "Gun reload sounds" by SpringySpringo — https://opengameart.org/content/gun-reload-sounds (*m4a1 = pitched variant)
- **Footsteps sand/stone**: "Fantozzi's Footsteps (Grass/Sand & Stone)" — https://opengameart.org/content/fantozzis-footsteps-grasssand-stone
- **Footsteps grass/dirt**: "[kdd] Different steps on wood, stone, leaves, gravel and mud" — https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud (leaves→grass, gravel+mud→dirt)
- **Knife swings**: "Swishes Sound Pack" — https://opengameart.org/content/swishes-sound-pack
- **Cave ambience** (cave_bed + cave_st*): "Loopable Dungeon Ambience" by JaggedStone — https://opengameart.org/content/loopable-dungeon-ambience

## CC-BY 4.0 (attribution required)
- **Forest + desert ambience** (forest_bed, desert_bed + stingers): "Nature Ambient Pack Vol 1" by **JC Sounds** — https://opengameart.org/content/jc-sounds-nature-ambient-pack-vol-1 ("Forest Day", "Desert Wind"). Credit "JC Sounds" in the game credits.

## OGA-BY 3.0 (attribution required)
- **Flesh hits + knife hits** (flesh_hit1-3, knife_hit1-2): "Fleshy Fight Sounds" by **Will Leamon** — https://opengameart.org/content/fleshy-fight-sounds. Credit "Additional Sound FX by Will Leamon".

## Pre-existing (kept from earlier dev, converted)
- shotgun_shot, shotgun_reload, shell1-3, bullet_hit1-2, grenade_blast — original mp3 sources in repo history.

## More CC0
- **gun_draw** (weapon deploy click): "equipment clicks III" — https://opengameart.org/content/equipment-clicks-iii (bolt-action cock slice)
- **grenade_draw**: "Gun reload, lock or click sound" — https://opengameart.org/content/gun-reload-lock-or-click-sound
- **m4a1_shot**: suppressed shot synthesized from the CC0 AR-15 recording (Free Firearm Sound Library) — lowpass + tight envelope + click layer. Replace with a real suppressed recording anytime by overwriting `weapons/m4a1_shot.wav`.
- **shotgun_pump** (pump-action rack): derived from the CC0 `gun_draw` ("equipment clicks III") — pitched down + doubled into a two-stroke "cha-chunk". Replace with a real shotgun pump recording anytime by overwriting `weapons/shotgun_pump.wav`.
- **rifle_shell / pistol_shell** (ak/m4 + usp casing-hit): derived from the CC0 brass-drop `shell1-3` — pitched to casing size (pistol brighter, rifle mid). Replace with real recordings anytime by overwriting `weapons/rifle_shell.wav` / `weapons/pistol_shell.wav`.

## Zombie sounds (empty slot)
Gabriel records these. Drop mono files into `assets/sounds/zombies/` named:
`zombie_growl1.wav, zombie_growl2.wav, ... zombie_attack1.wav, ... zombie_death1.wav, ...`
They auto-register at boot; the game already calls them (silent until files exist).

## Player hurt + heartbeat (added 2026-07-28)
- **hurt1-3** (player pain grunts): sliced from "grunts of male death and pain" by thebardofblasphemy (CC0) — https://opengameart.org/content/grunts-male-death-and-pain
- **heartbeat** (low-health loop): "Heartbeat sounds" by bart (CC0), fast loop variant — https://opengameart.org/content/heartbeat-sounds

## Molotov fire (added 2026-07-29)
- **fire_loop** (looping burn under every fire patch): "Fireplace Sound loop" by PagDev (CC0) — https://opengameart.org/content/fireplace-sound-loop. Mono 7.5s seamless loop (highpassed, +15dB, 0.5s crossfade seam).
- **molotov_break** (bottle shatter + ignite): glass break from "75 CC0 breaking / falling / hit sfx" by rubberduck (CC0) — https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx, layered with a lowpassed slice of the PagDev fire loop as the ignite whoosh.

## Grenade handling + med kit (added 2026-07-29)
No Counter-Strike audio is shipped — Valve's `pinpull.wav` is copyrighted and can't
go in the repo. These are CS-*style* sounds built from scratch / from CC0 sources:
- **grenade_pull** (deploy: pin pull): synthesized — inharmonic metal partials for the
  ring tick and the spoon clack, filtered-noise scrape for the pin sliding out. Voiced
  after the CS pinpull's three-beat shape (tick - scrape - clack). Overwrite the file
  with a real recording anytime.
- **grenade_throw** (release whoosh): the CC0 swish (`knife_swing1`, "Swishes Sound Pack")
  slowed 1.35x + lowpassed for a heavier arm, layered with a synthesized low air sweep
  and a cloth-grip transient.
- **medkit_heal** (heal confirm): `paper00` (repo CC0 rustle) resampled twice into a
  bandage wrap, plus a soft detuned D5 -> G5 confirm chime and a quiet breath swell.
