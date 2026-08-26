-- ALL gameplay numbers live here. Edit with any text editor.
-- In game: press U to reload this file and restart the run with new values.

return {
    player = {
        maxHealth = 100,
        baseSpeed = 130, -- walk speed, whatever is held
        runSpeedMult = 1.5,   -- shift held + moving: SPRINT speed (can't aim/shoot while running)
        runAnimMult = 1.5,    -- run animation plays this much faster than the walk cycle
        startMoney = 0,
        maxMoney = 9999,      -- hard cap on cash (kills, /money, everything)
        fallTime = 0.5,       -- secs of falling anim before hole respawn
        holeInvulnTime = 2,   -- secs of invincibility after hole respawn
        blinkInterval = 0.1,  -- sprite blink rate while invincible
        bodyRadius = 8,       -- circle vs zombies (16px hitbox, lower half of the 32px sprite)
        colSize = 16,         -- AABB collision box (tiles/obstacles), 16x16
        colOffsetX = 8,       -- px inset from sprite left  (centered in x)
        colOffsetY = 16,      -- px inset from sprite top   (box sits in the lower half)
        hitFlashTime = 0.12,  -- secs the sprite flashes white when hit
        contactInvulnTime = 0.8, -- secs of invulnerability (sprite blinks) after a zombie contact hit
        hurtCueCooldown = 0.5,   -- secs between hurt grunt + red vignette cues
        lowHealthThreshold = 25, -- at or below: sounds duck + heartbeat loop
        switchDelay = 0.3,    -- secs after a weapon swap before it can act (blocks quick-switch)
        knifeSwapDelay = 0.15, -- shorter lockout for the Q quick-knife (and Q back to the last item)
    },

    movement = {
        accelTime = 0.22,   -- secs to reach max speed (snappier start)
        decelTime = 0.20,   -- secs to stop from max speed (small glide)
        collisionInset = 4, -- px shaved off each AABB side vs tiles (32px body fits 32px gaps)
        cornerTolerance = 6, -- px: catching a crate/door corner by this little slides you off it instead of blocking/pushing
        -- movement inaccuracy window, as fractions of baseSpeed (CS: 34%..95%):
        -- below floor = perfectly accurate, above ceil = full moveSpread
        spreadSpeedFloor = 0.34,
        spreadSpeedCeil = 0.95,
    },

    tiles = {
        size = 32,
        spikeDps = 20,        -- damage per second standing on spikes
        waterSpeedMult = 0.65,
        mudAccelMult = 0.25,  -- accel AND decel multiplied by this on mud
        holeDamage = 50,      -- player falls in a hole
    },

    rooms = {
        -- Celeste-style room switch: world freezes, camera pans to the new room
        enterFraction = 0.8,   -- how much of the player's hitbox must be inside the next room
        transitionTime = 0.55, -- secs of frozen camera pan between rooms
        nudgePx = 20,          -- px the player drifts into the new room during the pan
        -- CO-OP ONLY: the world can't freeze (one player in a doorway would
        -- stop the game for everyone), so the pan runs alongside the sim and
        -- is shortened to stay out of the way. Solo is untouched by this.
        coopTimeMult = 0.5,    -- x transitionTime when more than one player is in the run
    },

    crate = { size = 32, health = 100,
              moneyFactor = 0,      -- $ per weapon hit = weapon's zombie hitReward x this (0 = crates pay nothing)
              pushRampTime = 1.2,   -- secs of continuous pushing until the crate reaches full walk speed
              pushStartFrac = 0.12, -- fraction of walk speed the push starts at (crawls, no dead delay)
              pushGrace = 0.15,     -- secs of lost contact before the ramp resets
              maxChain = 2,         -- crates the player can shove as one row (3+ = wall)
              chainSpeedMult = 0.5 }, -- row-of-2 push speed vs walk speed (player crawls with it)
    door  = { price = 250, interactPad = 12,
              -- floating lock icon on the player's side of the door
              lockGap = 8,        -- px between the door face and the icon
              lockFadeFar = 200,  -- px: icon fully invisible at this distance
              lockFadeNear = 110 }, -- px: fully opaque from here in

    guns = {
        -- aim model (all angles in radians):
        --   baseSpread    = inaccuracy standing still
        --   moveSpread    = extra inaccuracy at full run (0 below 34% speed,
        --                   ramps linearly to full at 95% — see movement block)
        --   recoilPerShot = spread added by each shot (stacks — spray = wild)...
        --   recoilMax     = ...capped here
        --   recoilDelay   = secs after the last shot before recovery starts
        --   recoilRecover = recoil lost per second once recovering
        --   maxHits       = zombies one bullet can damage before it stops (pierces maxHits-1)
        --   hitReward     = $ per damaging hit, killBonus = $ extra on the kill
        --   reloadAnimTime = secs the reload gif takes (matched to the reload
        --                    sound; gif then holds its last frame until
        --                    reloadTime ends). Omit = gif stretched to reloadTime.
        --   drawTime      = secs after select/pickup before the gun can fire
        --                   (CS deploys ~1s flat; CoD raises 0.25-0.6s — arcade
        --                   pace, so we sit near CoD: pistol fast, shotgun slow)
        --   lowAmmoClicks = the last N shots of the clip also play the hammer
        --                   click under the shot (omit = off)
        usp    = { damage = 20, clip = 15, bulletDelay = 0.15, reloadTime = 1.4, reloadAnimTime = 1.25, bulletLife = 0.5,
                   drawTime = 0.3, lowAmmoClicks = 2,
                   hitReward = 8, killBonus = 15, maxHits = 3,
                   baseSpread = 0.008, moveSpread = 0.120, recoilPerShot = 0.030, recoilMax = 0.15, recoilDelay = 0.30, recoilRecover = 0.40 },
        ak47   = { damage = 40, clip = 30, bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7,
                   drawTime = 0.5, lowAmmoClicks = 4,
                   hitReward = 4, killBonus = 10, maxHits = 4,
                   baseSpread = 0.012, moveSpread = 0.220, recoilPerShot = 0.035, recoilMax = 0.30, recoilDelay = 0.25, recoilRecover = 0.45 },
        m4a1   = { damage = 35, clip = 25, bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7,
                   drawTime = 0.45, lowAmmoClicks = 4,
                   hitReward = 5, killBonus = 10, maxHits = 4,
                   baseSpread = 0.010, moveSpread = 0.200, recoilPerShot = 0.030, recoilMax = 0.26, recoilDelay = 0.25, recoilRecover = 0.45 },
        -- reloadTime = secs PER SHELL; reloadOpenTime = silent break-open beat before first shell
        -- spread here is the fixed pellet cone; aim spread shifts the whole cone
        -- pump-action: bulletDelay is the rack gate between shots; pumpDelay =
        -- beat into that window where the rack SFX+shell-eject+pose fires,
        -- pumpAnimTime = how long the pump pose is shown
        shotgun = { damage = 10, clip = 7, bulletDelay = 0.7, reloadTime = 0.5, bulletLife = 0.7,
                     drawTime = 0.6,
                     reloadOpenTime = 0.4, reserve = 32,
                     pumpDelay = 0.12, pumpAnimTime = 0.22,
                     pellets = 14, spread = 0.20, maxHits = 3, -- damage is per pellet
                     hitReward = 1, killBonus = 10, -- hitReward is per PELLET hit
                     baseSpread = 0.025, moveSpread = 0.180, recoilPerShot = 0.080, recoilMax = 0.16, recoilDelay = 0.40, recoilRecover = 0.40 },
    },

    crosshair = {
        gapMin = 2,       -- px from center to a chip's inner edge at zero spread (chips 4px apart)
        chipLen = 3,      -- chip long side, px
        chipThick = 2,    -- chip short side, px
        spreadToPx = 120, -- gap px added per radian of current spread
        openSpeed = 18,   -- how fast the gap chases its target (higher = snappier)
        itemMoveGap = 8,  -- max extra gap while moving with grenade/medkit
        knifeAlpha = 0.4, -- crosshair opacity with the knife out (gap stays closed)
        ghostAlpha = 0.25, -- opacity of the bullet-reach marker when the mouse is past it
    },

    -- per-shot gun kick (draw-only, doesn't touch where bullets go)
    gunKick = {
        dist = 2,           -- px the gun slides straight back per shot
        posTime = 0.085,    -- ~5 frames: slide-back eases back over this
        angle = 7,          -- deg the muzzle snaps up per shot (instant up)
        angTime = 0.14,     -- muzzle-rise eases back over this (slower than slide, still fast)
        reloadUpAngle = 30, -- deg: center of the reload pose, above horizontal
        reloadBandDeg = 10, -- deg up AND down from center the aim can swing while reloading
        reloadSettleTime = 0.16, -- secs to ease from the reload pose back to aim when reload ends
    },

    -- sprint gun pose: gun points straight ahead (screen-horizontal), tucked
    -- a few px back toward the player, bobbing 1px with the run; the crosshair
    -- stays visible but faded. On sprint end the gun swings to the real aim.
    run = {
        crossAlpha = 0.4,   -- crosshair opacity while sprinting (gap stays closed)
        backPx = 5,         -- px the gun tucks back toward the player
        bobHz = 7,          -- 1px up-down bounces per second
        settleTime = 0.085, -- secs to swing from run pose to real aim (~5 frames)
    },

    knife   = { damage = 40,  hitReward = 22, killBonus = 22,
                -- knife pays most per hit: risk close = get paid
                range = 44,          -- arc reach from player center, px
                arcDeg = 110,        -- swing arc width, degrees (aiming matters)
                cooldown = 0.5,      -- secs between swings
                swingTime = 0.14,    -- visual sweep duration
                lungeSpeed = 150,    -- forward impulse on swing, px/s
                knockback = 240,     -- shove on hit zombies, px/s
                knockbackDecay = 8,  -- higher = shove stops sooner
                hitstop = 0.04,      -- secs the world freezes on connect
                hitstopKill = 0.09 },-- bigger freeze when the swing kills
    grenade = { damage = 120, hitReward = 10, killBonus = 20,
                throwSpeed = 240,  -- px/sec toward the aim point
                fuse = 1.2,        -- secs from throw to blast
                blastRadius = 80,  -- world px; flat damage inside
                maxRange = 240,    -- max throw distance from the player, world px
                -- targeting preview: dotted throw arc + dotted blast circle
                aimDotSpacing = 10,  -- px between dots on both guides
                aimDotSize = 1.5,    -- dot radius, world px
                aimAlpha = 0.35,     -- guide opacity
                aimFlowSpeed = 60,   -- px/s the arc dots march toward the landing point
                aimSpinSpeed = 0.5 },-- rad/s the blast circle spins

    -- thrown bottle, breaks on landing; fire spreads from there to blastRadius
    -- and burns for burnTime, ticking tickDamage per second per zombie inside
    -- (line of sight checked — fire never burns through solid walls)
    molotov = { tickDamage = 60, tickInterval = 1, burnTime = 5, -- 60/s x 5 = 300 total
                playerTickDamage = 10,   -- friendly fire: player standing in it takes this per player tick
                playerTickInterval = 0.5, -- player burn ticks on its own faster clock
                blastRadius = 80,  -- same area as the grenade
                maxRange = 160, throwSpeed = 240, -- shorter throw than the grenade (240)
                spreadTime = 0.6,  -- secs the fire takes to grow from the impact to full radius
                hitReward = 4, killBonus = 10, -- hitReward per burn tick
                breakGain = 0.9,   -- bottle shatter + ignite volume on impact
                fireGain = 0.85,   -- looping burn sound volume at the patch
                -- ground-fire sprites (assets/images/world/fire.gif): flames scattered over the
                -- burn area, each popping in as the fire spreads out to it
                flame = { count = 60,        -- flame sprites over the whole radius
                          fps = 18,          -- gif playback speed per flame
                          scale = 1.6,       -- sprite scale (same for every flame)
                          scaleFalloff = 0,  -- how much smaller the outer flames are (0-1)
                          scaleJitter = 0,   -- +/- random size variation
                          popTime = 0.15,    -- secs a flame takes to grow in
                          fadeTime = 1.2,    -- secs of shrink/fade at the end of burnTime
                          bobAmp = 1.5, bobSpeed = 7, -- idle up/down sway (px, rad/s)
                          -- sprites-only look: scorch/glow circles and ember
                          -- particles all off (raise any of them to bring it back)
                          scorchAlpha = 0,   -- darkened burnt ground under the fire
                          glowAlpha = 0,     -- additive orange glow over the burn area
                          emberFactor = 0 } }, -- particle embers on top of the sprites

    -- slot 4 is ONE pool: grenades + molotovs together can't pass maxCarry,
    -- and one kind alone can't pass perKindMax (4 total, never 4 of one)
    throwables = { maxCarry = 4,
                   perKindMax = 3,
                   useDelay = 1 }, -- secs between throws (a full pool can't be dumped at once)

    healthpack = { healAmount = 50, maxCarry = 3, -- slot 5 stacks maxCarry kits
                   useTime = 2.5 }, -- secs the patch-up takes (bar over the hotbar;
                                    -- swapping the kit away cancels, running is fine)

    -- CO-OP ONLY (world:isMultiplayer()). Solo still dies outright at 0 HP --
    -- that is the game that shipped and it stays balanced the way it was.
    -- Drop to 0 in co-op and you go down instead: crawling, bleeding, red
    -- rim closing in, until a teammate holds E long enough or the clock runs
    -- out. Bleed all the way out and you sit the rest of the wave out, then
    -- come back at the next one with the starting loadout (BO2's rule) --
    -- without that, one player dying out of reach just ends the run.
    revive = { bleedOutTime = 30,  -- secs on the floor before you die for real
               bleedTick = 1,      -- secs between blood drip + labored breath
               reviveTime = 4,     -- secs a teammate must hold E, uninterrupted
               range = 48,         -- px around the downed body where E works
               crawlSpeed = 0.35,  -- multiple of walk speed while downed
               reviveHealth = 100, -- HP you come back with (BO2 revives to full)
               respawnKeepsMoney = true, -- bleeding out costs the wave, not the wallet
               vignetteMin = 0.35, -- red rim the moment you go down
               vignetteMax = 0.92 }, -- ...and at the last second before you die

    -- CoD-style wall buys (GunWall entities placed in LDtk; gun + optional price)
    wallbuy = { interactPad = 4,
                ammoFactor = 0.6, -- ammo refill price = gun price x this
                prices = { usp = 150, ak47 = 950, m4a1 = 800, shotgun = 1200 } },

    -- power-up drops: fast (runner) zombies may spawn glowing with one and
    -- drop it on death; walk over the drop to grab it
    powerups = {
        carrierChance = 0.15, -- chance a fast zombie spawns carrying one
        maxPerWave = 2,       -- carrier cap per wave
        weights = { nuke = 20, maxammo = 25, instakill = 20, freeze = 15,
                    doublepoints = 20, firesale = 15, carpenter = 10 },
        lifetime = 20,        -- secs the drop stays on the ground
        blinkTime = 3, blinkInterval = 0.15,
        -- top-left buff readout: timer text blinks through the last seconds
        hudBlinkTime = 3, hudBlinkInterval = 0.25,
        pickupPad = 6,        -- px around the drop where walking over grabs it
        nukeMoney = 400,      -- flat cash for a nuke (both modes)
        instakillTime = 30,   -- secs every weapon one-shots
        freezeTime = 20,      -- secs zombies can't move or attack
        doublePointsTime = 20, doubleMult = 2,
        fireSaleCost = 50,    -- mystery box price while fire sale runs
        fireSaleTime = 20,    -- secs the sale lasts
        carpenterMoney = 200, -- flat cash when carpenter rebuilds the crates
        carrierPulseSpeed = 6, -- glow ring pulse, rad/s
    },

    start = { -- run start (Play / New Game / retry)
        sound = 'shotgun_pump', -- cue when the controls splash is dismissed (any name core/audio knows)
        soundGain = 1,
        fadeTime = 2,           -- secs the image + audio fade in; wave banner waits for it
    },

    controlsScreen = { -- controls splash between the menu and the run
        minShowTime = 0.35, -- secs before any-key skip arms (so the menu click can't blow past it)
    },

    chest = {
        cost = 300,           -- the gamble; wall buys are the reliable option
        spinTime = 5.0,       -- secs of sprite cycling after paying
        -- roulette pacing: secs per sprite ramps start -> end over the spin
        -- (fast blur at first, ticking to a stop); the last sprite shown is
        -- always the actual reward
        spinCycleStart = 0.04,
        spinCycleEnd = 0.5,
        spinSlowdown = 2.5,   -- ramp shape (higher = stays fast longer, brakes harder)
        spinRise = 32,        -- px below the final height the cycling sprite starts at
        -- warm player-colored glow on the cycling/offered item
        spinGlow = 0.5,       -- item glow as a fraction of the player light
        spinGlowRange = 115,  -- item glow radius, world px
        takeWindow = 8.0,     -- secs to press E and take a rolled gun
        openTime = 0.25,      -- secs for the lid open (and close) animation
        interactPad = 32,     -- px around the 64x32 box where E buys/takes
        -- loot odds — two-stage roll, resolved at pay time:
        --   1) GUN GATE: gunChance base odds of a gun, +gunChancePerItem for
        --      every grenade/molotov/med kit held when paying (full pockets =
        --      box leans guns). If nothing else can drop (all pools full) the
        --      roll is a gun for sure. Rolling an owned gun = ammo refill.
        --   2) CONSUMABLES: the rest draws from a shuffled card bag (bagCards
        --      = card counts). Cards that can't help right now (pool full)
        --      are skipped, not spent. After bagResetAfter draws the bag is
        --      rebuilt + reshuffled — smooths streaks, can't be card-counted.
        gunChance = 0.15,         -- base gun odds (15%)
        gunChancePerItem = 0.025, -- +2.5% per grenade/molotov/med kit held
        gunWeights = { ak47 = 2, m4a1 = 2, shotgun = 1 }, -- split inside the gun odds (6/6/3% at base)
        bagCards = { grenade = 5, molotov = 4, healthpack = 6 }, -- 15 cards
        bagResetAfter = 5,        -- draws before the bag resets
    },

    hotbar = { slotSize = 56, gap = 8, bottomMargin = 16 },

    -- floating "+$n" above the money readout; each earn shows separately,
    -- a new one replaces the previous (amounts never add up). The red "-hp"
    -- popup left of the HP readout shares popupTime/popupRise, but stacks
    -- (per-frame spike/fire damage adds into the live popup).
    -- reloadBar* : the bar that fills right of the ammo count while reloading
    -- medkitBar* : the patch-up progress bar centered above the hotbar
    hud = { popupTime = 1.0, popupRise = 18,
            reloadBarW = 70, reloadBarH = 8, reloadBarGap = 14,
            medkitBarW = 90, medkitBarH = 10, medkitBarGap = 14,
            -- world-space, over a downed body (bleed clock + revive hold)
            reviveBarW = 44, reviveBarGap = 8,
            -- co-op name tags, world-space over a teammate's head. Long names
            -- are cut rather than shrunk: the tag has to stay the same size
            -- as every other world label or it stops reading as one.
            nameTagGap = 6, nameTagChars = 10,
            nameTagNear = 220,      -- px: full brightness inside this
            nameTagFar = 620,       -- px: faded to nameTagMinAlpha by here
            nameTagMinAlpha = 0.35 },

    dev = { enabled = true,     -- master switch for the chat console (T)
            flySpeedMult = 2 }, -- god-mode fly (shift held): speed vs base walk

    -- LAN co-op. Desktop only: a browser tab cannot open UDP sockets, so the
    -- web build has no ENet at all (see core/web.lua).
    net = {
        maxPlayers = 4,
        gamePort = 23471,      -- ENet host port (clients connect here)
        beaconPort = 23470,    -- UDP broadcast the server browser listens on
        beaconInterval = 1,    -- secs between a host's beacons
        beaconTimeout = 3,     -- secs before a silent host drops off the list

        -- LAN round-trip is ~1ms against a 16.7ms frame, so everything runs at
        -- full rate: no interpolation, no client prediction, no rewind buffers.
        -- Budget at 4 players + 40 zombies is ~48 KB/s per client.
        inputRate = 60,        -- Hz a client sends its input struct (18 bytes)
        snapshotRate = 60,     -- Hz the host broadcasts world state
        timeout = 5,           -- secs of silence before a peer is dropped
        connectTimeout = 8,    -- secs to give up on joining a host

        -- Remote bodies (other players, every zombie) are drawn from
        -- snapshots rather than simulated. Writing each snapshot straight
        -- onto x/y makes them jump once per packet, which reads as stutter
        -- the moment packets stop arriving on a perfect beat. So a snapshot
        -- moves a TARGET instead: the target keeps coasting on the velocity
        -- that came with it, and the body eases toward the target every
        -- frame. Free on a LAN, and the difference between smooth and
        -- unwatchable over anything with jitter.
        smoothTime = 0.055,     -- secs to close ~63% of the gap to the target
        selfSmoothTime = 0.02,  -- our own body: shorter, own lag is felt
        snapDist = 96,          -- px of error that means "teleported", not "late"
        extrapolate = 0.2,      -- secs a target coasts with no new snapshot

        -- voice: raw PCM, no codec (a LAN has bandwidth to burn and Opus would
        -- be a native dependency for no gain). 25ms chunks stay under MTU.
        voice = {
            sampleRate = 16000, -- Hz; 8000 sounds like a phone, 16000 is clear
            bitDepth = 16,
            chunkMs = 25,       -- 400 samples = 800 bytes per packet
            maxQueued = 6,      -- chunks buffered per speaker before dropping
            proximityRange = 420, -- px falloff when the host picks proximity voice
        },
    },

    -- /recording (hidden chat command, not in /help or suggestions): clean
    -- footage mode — molotov fire kills any zombie in exactly ticksToKill
    -- burn ticks, burns for burnTime secs, HUD + chat overlay hidden.
    -- Toggle: run /recording again. Flags the run as cheated.
    recording = { molotovTicksToKill = 5, burnTime = 10 },
    chat = {
        showTime = 8,   -- secs a line stays on screen before fading (chat closed)
        fadeTime = 1,   -- secs of the fade-out at the end of showTime
        maxVisible = 8, -- most lines drawn at once
        maxLog = 50,    -- lines kept in memory (scrollback + sent history)
        maxSpawn = 30,  -- cap on /spawn <type> <count>
    },
    droppedGun = { interactPad = 4,    -- px around a dropped gun where E picks it up
                   dropOffset = 40,    -- px in front of the player where drops land
                   lifetime = 8,       -- secs a gun stays on the ground before vanishing
                   blinkTime = 2,      -- secs of blinking at the end of that life
                   blinkInterval = 0.15, -- secs per blink on/off step
                   bounceUp = 160,       -- px/s upward hop when a gun hits the ground
                   bounceGravity = 700,  -- px/s^2 pulling the hop back down
                   bounceRestitution = 0.45, -- fraction of speed kept per rebound
                   bounceMinSpeed = 40 },    -- rebounds slower than this settle flat

    bullet = { speed = 540,
               -- first frame only: the hit check also probes this many px
               -- BEHIND the spawn point (zombies only, never walls), so a
               -- zombie inside the barrel length still catches a point-blank
               -- shot. Covers the gap for usp/shotgun/ak tips; the m4's 44px
               -- tip can still whiff on a point-blank fast zombie.
               tailLen = 18 },

    -- spent shell casings: faked-3D hop (ground x/y + height z), spin, settle
    -- near the player, then blink out. Purely decorative.
    shell = {
        ejectSpeed = 95,       -- sideways ground drift px/s (off the barrel side)
        ejectSpeedJitter = 40, -- +/- random on ejectSpeed
        dirSpread = 0.6,       -- rad: random tilt around the sideways eject dir (~+/-34deg)
        ejectUp = 70,          -- initial upward hop velocity px/s (higher = pops higher)
        ejectUpJitter = 25,    -- +/- random on ejectUp
        gravity = 500,         -- px/s^2 pulling the hop down
        bounce = 0.4,          -- vertical velocity kept per ground bounce
        friction = 5,          -- ground drift decay (higher = stops sooner)
        spinMin = 8, spinMax = 22, -- random spin rad/s while airborne
        settleSpeed = 12,      -- once ground drift drops below this, it rests
        blinkInterval = 0.1,   -- visibility toggle rate during the blink-out
        blinkTime = 1.0,       -- secs of blinking before it vanishes
        lifetime = 4.5,        -- total secs from spawn (~2 flight/bounce + rest + 1 blink)
        scale = 1,             -- draw scale of the 8x8 sprite
    },

    audio = {
        masterDefault = 1,  -- 0..1, used until the player touches the options
        sfxDefault = 1,
        musicDefault = 1,
        poolSize = 8, -- max simultaneous plays of the same sound (then oldest is stolen)
        maxVoices = 64, -- hard ceiling on sounds playing at once, all pools combined
                        -- (then the one closest to finishing is stolen)

        -- positional ("surround") audio; world px -> OpenAL units
        pxPerUnit = 100,     -- smaller = stronger pan + faster falloff
        listenerHeight = 2,  -- listener lifted off the plane; higher = softer pan
        refDist = 1.5,       -- full volume within this many units
        maxDist = 14,        -- silent past this

        -- echo grows with nearby walls (reverb follows the map around you)
        reverbRadius = 6,          -- tiles sampled around the listener
        reverbUpdateInterval = 0.25,
        reverbSmooth = 3,          -- higher = adapts faster
        reverbDecayMin = 0.5,      -- open field decay, secs
        reverbDecayMax = 2.6,      -- boxed-in decay
        reverbGainMin = 0.04,      -- reverb loudness open...
        reverbGainMax = 0.4,       -- ...vs surrounded by walls
        occlusionHighgain = 0.3,   -- muffle strength when a wall blocks the sound

        gunPickGain = 0.8, -- pick/raise handling volume (select, pickup, post-reload)
        dryFireGain = 0.7, -- empty-clip hammer click volume
        lowAmmoClickGain = 0.55, -- same click layered under the last shots of a clip
        motherFuckerChance = 0.001, -- 0.1%: odds a damage hit plays the easter-egg line instead

        -- footsteps
        stepInterval = 0.32,  -- secs between steps at full run (scales with speed)
        stepMaxStretch = 1.6, -- slowest cadence = interval * this (walking slowly)
        stepGain = 0.45,
        pitchJitter = 0.12,  -- ± random pitch on steps/hits/stingers

        -- pause muffle (GTA-style)
        muffleHighgain = 0.12, -- how much treble survives the pause lowpass
        muffleDuck = 0.2,      -- ambience volume multiplier while paused
        muffleFadeSpeed = 4,   -- how fast the duck fades in/out (higher = quicker)

        -- critical health (player.lowHealthThreshold): everything ducks,
        -- the heartbeat loop plays at full volume
        lowHealthDuck = 0.3,
        heartbeatGain = 2.2,

        -- ambience: looping bed + sparse positional one-shots
        bedGain = 0.7,
        stingerMin = 15, stingerMax = 40, -- secs between stingers
        stingerGain = 0.55,

        -- menu music (No Birds): never stops, only fades with game state
        menuMusicGain = 0.7,
        musicFadeInTime = 5,  -- secs 0 -> full on pause / back to menu
        musicFadeOutTime = 1, -- secs full -> 0 when the run (re)starts
    },

    menu = {
        musicCreditTime = 3,  -- secs the "MUSIC: ..." line shows per menu visit
        musicCreditFade = 0.5, -- fade-out inside that window (gone at exactly 3s)
        pulseSpeed = 6,   -- selector chevron pulse (radians/sec)
        itemSpacing = 52, -- px between menu rows
        chevronGap = 18,  -- px between the > < selectors and the item text
        colOffset = 310,  -- px a column center sits from screen center (col items only)
        fadeInTime = 1,   -- secs the menu items/hint NES-fade in (intro card uses splash.fadeIn)

        -- eerie title glitch: now and then one letter tears for a moment
        glitchGapMin = 2.5,  -- secs between bursts (random in [min, max])
        glitchGapMax = 7,
        glitchTime = 0.16,   -- secs one burst lasts
        glitchAmp = 5,       -- px of letter jitter during a burst
        glitchSwapChance = 0.35, -- chance the letter shows a wrong glyph
    },

    splash = { -- intro sequence (skippable: card -> typing -> menu)
        fadeSteps = 4,      -- NES palette tiers every intro fade snaps through
        fadeIn = 1.5,       -- secs the COFFEEBREAK card fades in
        holdName = 2,       -- secs before presents: appears
        presentsIn = 0.5,   -- secs presents: takes to fade in
        holdPresents = 1.5, -- secs the full card stays after that
        fadeOut = 1,        -- secs the card fades back to black
        typeInterval = 0.12, -- secs per typed title letter
        typeHold = 0.7,     -- beat after typing before the menu arrives
        typeGain = 0.45,    -- volume of the per-letter typewriter click
        titleGlide = 0.9,   -- secs the typed title glides up into place
    },

    fx = {
        -- post-processing (menus get the full CRT chain, gameplay a subtle one)
        crtDistortion = 1.06,   -- barrel distortion (1 = flat screen)
        scanlineOpacity = 0.35,
        chromaRadius = 2.2,     -- chromatic aberration, px
        glowStrength = 4,       -- bloom blur strength
        glowMinLuma = 0.6,      -- only pixels brighter than this bloom (menus)
        vignetteOpacity = 0.55,
        grainOpacity = 0.25,
        damageVignetteTime = 0.45,   -- secs the red hit vignette takes to fade
        damageVignetteOpacity = 0.6, -- red rim strength at the moment of the hit
        lowHealthVignetteOpacity = 0.5, -- constant red rim while at critical health

        -- menu animation
        titleSlamTime = 0.55, -- secs for the title to slam down
        itemStagger = 0.07,   -- delay between each menu item sliding in
        itemInTime = 0.25,    -- per-item slide-in time
        fadeTime = 0.35,      -- state-to-state fade to black

        -- menu background
        emberRate = 22,  -- embers per second
        fogAlpha = 0.5,  -- overall fog layer opacity
        bannerEmberFade = 0.6, -- secs the menu embers fade in/out around the WAVE N banner

        -- gameplay
        bloodParticles = 7,     -- wine puffs per hit (bullet AND knife) — sprite puffs, not droplets

        -- permanent blood splats on the floor (core/decals)
        decalHitChance = 0.75,  -- chance per damaging hit (bullet/knife/nade/fire)
        decalDeathChance = 0.8, -- chance on the kill
        decalMax = 1500,        -- splats kept; oldest overwritten past this

        -- zombie spawn telegraph haze (colors live on each zombie type)
        spawnCloudRate = 2,      -- particles per frame while telegraphing
        spawnCloudOpacity = 0.35,

        -- movement dust (muzzle-flash sprite, faded, drifts randomly)
        dustInterval = 0.12, -- secs between puffs while moving
        dustCount = 2,       -- particles per puff at full sprint
        dustWalkMult = 0.5,  -- walking emits this fraction of dustCount
        dustOpacity = 0.2,   -- constant alpha, no fade

        -- med kit heal: pink dust puffs around the player, floating up
        healCount = 16,      -- particles per heal
        healOpacity = 0.45,  -- their constant alpha
    },

    render = {
        cullMargin = 128, -- px beyond the camera edge still drawn (covers sprite
                          -- overhang: tall zombies, chest roulette icon, torches)
    },

    -- Scenery scattered over the ground (core/decor). Placement is derived from
    -- the tile coords, so the same numbers always grow the same field.
    props = {
        bushChance = 0.025, -- chance per ground tile for a big 32x32 bush
        smallChance = 0.1,  -- chance per ground tile for a 16x16 prop (no bush there)
        rockShare = 0.4,    -- fraction of small props that are rocks (rest = grass)
        torchPulse = 0.25,  -- how much the torch sprite brightens with its flame
        walkPush = 6,       -- px the tips are shoved aside by whoever walks through
        walkReach = 26,     -- px around a walker where props get pushed

        -- wind: constant low sway + gusts sweeping the map in +x, all scaled
        -- by a slow "weather" wave — calm spells, then the wind picks up
        wind = {
            amp = 7,          -- px the tip drifts in the constant sway
            speed = 2,        -- sway rate
            gustAmp = 13,     -- extra px at the peak of a gust
            gustSpeed = 0.5,  -- gusts per second
            gustWave = 0.004, -- how tight the gust wave is (lower = wider front)
            stiffness = 1.2,  -- bend curve (higher = only the tip really moves)
            lullSpeed = 0.35, -- how fast calm/windy spells cycle (noise samples/sec)
            lullFloor = 0.4,  -- wind strength left in a full lull (0-1)
            lullBias = 1.6,   -- higher = calm more of the time, windy bursts sharper
        },
    },

    lighting = {
        -- world brightness with no lights (0 = pitch black). Player-facing:
        -- the options menu BRIGHTNESS slider picks within [min, max] in
        -- fixed steps; ambient is only the default for fresh settings.
        ambient = 0.25,
        brightnessMin = 0.10,  -- slider floor ("DARK")
        brightnessMax = 0.40,  -- slider ceiling ("BRIGHT")
        brightnessStep = 0.03, -- slider snap grid: 10 steps of 10% (default = 50%)
        playerRange = 230,    -- player light radius, world px
        playerBright = 0.40,  -- player light intensity (1 = blinding white)
        shadowBlur = 2,       -- shadow edge softness, blur px (0 = hard pixel edges)
        maxLights = nil,      -- cap on simultaneous lights (nil = no cap)
        shadowScale = 1,      -- resolution the light passes render at (1 = full
                              -- canvas, 0.5 = quarter the pixels). Lights cost a
                              -- full-buffer pass each, so this is THE lighting
                              -- performance dial. Below ~0.5 shadow edges go soft.
        occluderCornerCut = 8, -- px chamfered off wall shadow corners (matches the soft wall sprites)
        muzzleRange = 210,    -- muzzle flash light radius
        muzzleBright = 0.65,  -- muzzle flash intensity
        muzzleTime = 0.06,    -- muzzle flash duration, secs

        torchRange = 190,       -- torch tile light radius, world px
        torchBright = 0.6,      -- torch light intensity
        torchFlickerSpeed = 7,  -- flicker rate (noise samples/sec)
        torchFlickerDepth = 0.1, -- how much the flicker moves the range (0-1)
    },

    zombies = {
        contactDamage = 25,   -- fallback when a type has no damage of its own
        contactCooldown = 1.0, -- secs between hits, per zombie
        attackRange = 6,      -- px beyond touching circles where a hit lands
        growlMin = 9, growlMax = 22, -- secs between random growls, per zombie (kept sparse)
        hitFlashTime = 0.08,  -- secs a hit zombie stays white
        repathTime = 0.4,     -- secs between A* recalculations, per zombie
        waypointRadius = 13,  -- px from a path waypoint that counts as reached
        stuckRepath = 0.35,   -- secs of no progress before forcing an instant repath
        colliderCap = 28,     -- max wall-collision box (px) so big bodies fit 1-tile gaps
        crateDamage = 20,     -- damage per hit when a crate-breaker smashes a crate
        lostDespawnTime = 3,  -- secs a zombie's center can sit outside every room
                              -- before it silently despawns (void between rooms:
                              -- invisible but audible, can strand the wave)

        -- breaksCrates: last resort only — when A* finds no route around the
        -- crates, this type paths straight through them and smashes the way
        -- open. Any walkable detour exists = it walks it and never chews.
        -- losShortcut: clear straight line to the player = walk it directly
        -- (no A*, no grid corners); blocked line falls back to normal A*
        -- damage = contact hit on the player (slow hits hardest, fast lightest)
        -- hitPad = extra px on the combat circle radius (bullets/knife land
        -- easier point-blank); wall-collision box and sprite untouched
        -- slow uses assets/images/zombies/slow_zombie.gif (54x60, 4 frames): the normal
        -- sprite scaled 1.5x and recolored red, centered on the 48px circle
        -- cloudColor = spawn-telegraph haze tint, sampled from each type's sprite
        -- lifeCap = ceiling on the FINAL life (after lifeMult) — each type caps
        slow   = { speed = 30, lifeMult = 1,    lifeCap = 250, size = 48, damage = 25, hitPad = 5, losShortcut = true, breaksCrates = true,
                   cloudColor = { 0.61, 0.34, 0.28 },
                   animTime = 1.4 }, -- secs per walk loop (half the normal's pace)
        -- normal uses assets/images/zombies/normal_zombie.gif (36x40, 4 frames): sprite is
        -- centered on the 32px collision circle on both axes. Plain repeating
        -- loop (1-2-3-4-1...).
        normal = { speed = 60, lifeMult = 0.5,  lifeCap = 200, size = 32, damage = 20, hitPad = 3, breaksCrates = true,
                   cloudColor = { 0.36, 0.61, 0.47 },
                   animTime = 0.7 }, -- secs for one full walk-cycle loop
        -- fast uses assets/images/zombies/fast_zombie.gif (16x24): size = the body circle,
        -- which is the BOTTOM 16px of the sprite; the top 8px overhang above it
        fast   = { speed = 90, lifeMult = 0.25, lifeCap = 150, size = 16, damage = 20, hitPad = 2, breaksCrates = true,
                   cloudColor = { 0.68, 0.72, 0.2 },
                   animTime = 0.45 }, -- secs for one full run-cycle loop
    },

    waves = {
        quotaBase = 4,          -- zombies in wave w = (this + w*(w+1)/2) * quotaMult
        quotaMult = 1.5,        -- horde size scale -> 8, 11, 15, 21, 29, 38...

        -- chance a spawn comes from a room right next door instead of the
        -- player's own room. Only rooms already visited AND reachable right
        -- now count (a locked door between them = not next door).
        adjacentRoomChance = 0.25,

        -- surprise spawns: this fraction of spawns pops in a ring right
        -- around the player (random walkable tile, same room) instead of a
        -- spawn marker — the telegraph haze still gives the 1s warning
        nearPlayerChance = 0.05,
        nearMinDist = 96,   -- ring inner radius, world px (3 tiles)
        nearMaxDist = 192,  -- ring outer radius, world px (6 tiles)

        telegraphTime = 1, -- secs of colored spawn haze before the zombie appears

        lifeBase = 20,          -- wave-1 zombie life, before the type multiplier
        lifePerWave = 20,       -- +this per wave while wave <= lifeLinearUntil
        lifeLinearUntil = 9,    -- linear growth up to this wave (= 180)...
        lifeGrowth = 1.1,       -- ...then x this per wave afterwards
        -- final life is still clamped per type: see zombies.<type>.lifeCap

        spawnDelayStart = 1.6,  -- secs between spawns on wave 1
        spawnDelayDecay = 0.9,  -- delay multiplied by this each wave
        spawnDelayFloor = 0.24, -- delay never drops below this
        maxAlive = 60,          -- most zombies alive at once; the rest of the
                                -- quota waits for free slots, keeps huge waves
                                -- from tanking the framerate

        startIntermission = 5,  -- secs of "WAVE N" banner before spawning starts
        endIntermission = 5,    -- secs of "WAVE COMPLETE" before the next wave

        -- spawn mix: last entry whose fromWave <= wave applies
        weights = {
            { fromWave = 1, slow = 70, normal = 30, fast = 0 },
            { fromWave = 3, slow = 40, normal = 45, fast = 15 },
            { fromWave = 6, slow = 20, normal = 45, fast = 35 },
        },

        -- every Nth wave is a NIGHTMARE wave: mix flipped to runners, every
        -- zombie faster. Banner goes purple.
        nightmare = {
            every = 5,       -- waves 5, 10, 15...
            -- same zombie count and speed as a normal wave: nightmares only
            -- spawn faster and shift the type mix
            spawnDelayMult = 0.55, -- spawn delay x this (~2x spawn rate)
            weights = { slow = 10, normal = 40, fast = 50 },
            nearPlayerChance = 0.15, -- surprise-spawn roll during nightmares
            bonusMoney = 500,        -- cash for clearing one (shown on the end banner)
        },
    },

    -- ================================ WEB =================================
    -- Only read by the browser build (core/web.lua folds these over the
    -- values above at boot). Same shape as the real tables -- anything not
    -- listed here keeps its desktop value. Editing a number in here changes
    -- ONLY the browser build.
    web = {
        lighting = {
            -- soft shadow edges cost an extra full-buffer pass per frame, on
            -- top of the per-light stencil work. WebGL cannot afford them.
            shadowBlur = 0,
            -- and the light passes themselves run at half resolution
            shadowScale = 0.5,
            -- Nearest N lights only. This used to be 2 and was the only thing
            -- holding the framerate up; since occluders stopped being stamped
            -- into the stencil as one texture each (lib/light_world/body.lua)
            -- the browser sits at a locked 60 with 4. Uncapped still dips to
            -- 53 in a torch-heavy room, so the cap stays -- it just costs
            -- nothing visible now.
            maxLights = 4,
        },
        audio = {
            -- OpenAL-wasm has a far tighter voice budget than desktop OpenAL,
            -- and every source is fully decoded in RAM (no streaming without
            -- threads). Smaller pools, hard global ceiling.
            poolSize = 4,
            maxVoices = 24,
        },
        -- the dev console needs Tab, Ctrl+C/V and clipboard access, none of
        -- which behave in a browser tab
        dev = { enabled = false },
        -- run autosave interval, secs. Closing a tab never fires love.quit,
        -- so the browser build cannot rely on save-on-exit.
        autosaveInterval = 30,
    },
}
