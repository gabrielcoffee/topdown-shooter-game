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

## Zombie sounds (empty slot)
Gabriel records these. Drop mono files into `assets/sounds/zombies/` named:
`zombie_growl1.wav, zombie_growl2.wav, ... zombie_attack1.wav, ... zombie_death1.wav, ...`
They auto-register at boot; the game already calls them (silent until files exist).
