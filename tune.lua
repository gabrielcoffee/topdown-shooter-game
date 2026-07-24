-- ALL gameplay numbers live here. Edit with any text editor.
-- In game: press U to reload this file and restart the run with new values.

return {
    player = {
        maxHealth = 100,
        baseSpeed = 130, -- walk speed, whatever is held
        runSpeedMult = 1.5,   -- shift held + moving: SPRINT speed (can't aim/shoot while running)
        runAnimMult = 1.5,    -- run animation plays this much faster than the walk cycle
        startMoney = 0,
        fallTime = 0.5,       -- secs of falling anim before hole respawn
        holeInvulnTime = 2,   -- secs of invincibility after hole respawn
        blinkInterval = 0.1,  -- sprite blink rate while invincible
        bodyRadius = 8,       -- circle vs zombies (16px hitbox, lower half of the 32px sprite)
        colSize = 16,         -- AABB collision box (tiles/obstacles), 16x16
        colOffsetX = 8,       -- px inset from sprite left  (centered in x)
        colOffsetY = 16,      -- px inset from sprite top   (box sits in the lower half)
        -- head circle (inert for now; reserved for future co-op headshots)
        headRadius = 5,
        headOffsetX = 16,     -- head center, px from sprite left (centered)
        headOffsetY = 8,      -- head center, px from sprite top  (upper area)
        hitFlashTime = 0.12,  -- secs the sprite flashes white when hit
    },

    movement = {
        accelTime = 0.22,   -- secs to reach max speed (snappier start)
        decelTime = 0.20,   -- secs to stop from max speed (small glide)
        collisionInset = 4, -- px shaved off each AABB side vs tiles (32px body fits 32px gaps)
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
    },

    crate = { pushDelay = 0.5, size = 32, health = 100, pushSpeedMult = 0.5,
              pushGrace = 0.15 }, -- secs of lost contact before a push resets
    door  = { price = 250, interactPad = 4 },

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
        usp    = { damage = 20, clip = 15, bulletDelay = 0.15, reloadTime = 2,   bulletLife = 0.5, killReward = 20, maxHits = 2,
                   baseSpread = 0.008, moveSpread = 0.120, recoilPerShot = 0.030, recoilMax = 0.15, recoilDelay = 0.30, recoilRecover = 0.40 },
        ak47   = { damage = 40, clip = 30, bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7, killReward = 10, maxHits = 3,
                   baseSpread = 0.012, moveSpread = 0.220, recoilPerShot = 0.035, recoilMax = 0.30, recoilDelay = 0.25, recoilRecover = 0.45 },
        m4a1   = { damage = 35, clip = 25, bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7, killReward = 10, maxHits = 3,
                   baseSpread = 0.010, moveSpread = 0.200, recoilPerShot = 0.030, recoilMax = 0.26, recoilDelay = 0.25, recoilRecover = 0.45 },
        -- reloadTime = secs PER SHELL; reloadOpenTime = break-open sound before first shell
        -- spread here is the fixed pellet cone; aim spread shifts the whole cone
        -- pump-action: bulletDelay is the rack gate between shots; pumpDelay =
        -- beat into that window where the rack SFX+shell-eject+pose fires,
        -- pumpAnimTime = how long the pump pose is shown
        sawedoff = { damage = 10, clip = 7, bulletDelay = 0.5, reloadTime = 0.5, bulletLife = 0.7,
                     reloadOpenTime = 0.4, reserve = 32,
                     pumpDelay = 0.12, pumpAnimTime = 0.22,
                     pellets = 14, spread = 0.20, killReward = 10, maxHits = 2, -- damage is per pellet
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

    knife   = { damage = 60,  killReward = 50,
                range = 44,          -- arc reach from player center, px
                arcDeg = 110,        -- swing arc width, degrees (aiming matters)
                cooldown = 0.5,      -- secs between swings
                swingTime = 0.14,    -- visual sweep duration
                lungeSpeed = 150,    -- forward impulse on swing, px/s
                knockback = 240,     -- shove on hit zombies, px/s
                knockbackDecay = 8,  -- higher = shove stops sooner
                hitstop = 0.04,      -- secs the world freezes on connect
                hitstopKill = 0.09 },-- bigger freeze when the swing kills
    grenade = { damage = 120, killReward = 10,
                throwSpeed = 240,  -- px/sec toward the aim point
                fuse = 1.2,        -- secs from throw to blast
                blastRadius = 80,  -- world px; flat damage inside
                maxRange = 240,    -- max throw distance from the player, world px
                maxCarry = 3,
                -- targeting preview: dotted throw arc + dotted blast circle
                aimDotSpacing = 10,  -- px between dots on both guides
                aimDotSize = 1.5,    -- dot radius, world px
                aimAlpha = 0.35,     -- guide opacity
                aimFlowSpeed = 60,   -- px/s the arc dots march toward the landing point
                aimSpinSpeed = 0.5 },-- rad/s the blast circle spins

    healthpack = { healAmount = 50 },

    chest = {
        cost = 150,           -- ~10 kills
        spinTime = 2.0,       -- secs of sprite cycling after paying
        spinCycleTime = 0.08, -- secs per sprite during the spin
        takeWindow = 5.0,     -- secs to press E and take a rolled gun
        openTime = 0.25,      -- secs for the lid open (and close) animation
        interactPad = 4,
        -- loot odds; invalid categories (grenades full, medkit held) are
        -- dropped and the rest renormalized. Rolling an owned gun = ammo refill.
        weights = { ak47 = 15, m4a1 = 15, sawedoff = 10, grenade = 30, healthpack = 30 },
    },

    hotbar = { slotSize = 56, gap = 8, bottomMargin = 16 },

    dev = { enabled = true }, -- master switch for the chat console (T / ` / Enter)
    chat = {
        showTime = 8,   -- secs a line stays on screen before fading (chat closed)
        fadeTime = 1,   -- secs of the fade-out at the end of showTime
        maxVisible = 8, -- most lines drawn at once
        maxLog = 50,    -- lines kept in memory (scrollback + sent history)
    },
    droppedGun = { interactPad = 4,   -- px around a dropped gun where E picks it up
                   dropOffset = 40 }, -- px in front of the player where drops land

    bullet = { speed = 540 },

    -- spent shell casings: faked-3D hop (ground x/y + height z), spin, settle
    -- near the player, then blink out. Purely decorative.
    shell = {
        ejectSpeed = 70,       -- sideways ground drift px/s (off the barrel side)
        ejectSpeedJitter = 40, -- +/- random on ejectSpeed
        dirSpread = 0.6,       -- rad: random tilt around the sideways eject dir (~+/-34deg)
        ejectUp = 215,         -- initial upward hop velocity px/s (higher = pops higher)
        ejectUpJitter = 65,    -- +/- random on ejectUp
        gravity = 340,         -- px/s^2 pulling the hop down
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

        -- footsteps
        stepInterval = 0.32,  -- secs between steps at full run (scales with speed)
        stepMaxStretch = 1.6, -- slowest cadence = interval * this (walking slowly)
        stepGain = 0.45,
        pitchJitter = 0.12,  -- ± random pitch on steps/hits/stingers

        -- pause muffle (GTA-style)
        muffleHighgain = 0.12, -- how much treble survives the pause lowpass
        muffleDuck = 0.5,      -- ambience volume multiplier while paused

        -- ambience: looping bed + sparse positional one-shots
        bedGain = 0.7,
        stingerMin = 15, stingerMax = 40, -- secs between stingers
        stingerGain = 0.55,
    },

    menu = {
        pulseSpeed = 6,   -- selector chevron pulse (radians/sec)
        itemSpacing = 52, -- px between menu rows
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

        -- menu animation
        titleSlamTime = 0.55, -- secs for the title to slam down
        itemStagger = 0.07,   -- delay between each menu item sliding in
        itemInTime = 0.25,    -- per-item slide-in time
        fadeTime = 0.35,      -- state-to-state fade to black

        -- menu background
        emberRate = 22,  -- embers per second
        fogAlpha = 0.5,  -- overall fog layer opacity

        -- gameplay
        bloodParticles = 18, -- per bullet hit

        -- movement dust (muzzle-flash sprite, faded, drifts randomly)
        dustInterval = 0.12, -- secs between puffs while moving
        dustCount = 2,       -- particles per puff at full sprint
        dustWalkMult = 0.5,  -- walking emits this fraction of dustCount
        dustOpacity = 0.2,   -- constant alpha, no fade
    },

    lighting = {
        ambient = 0.40,       -- world brightness with no lights (0 = pitch black)
        playerRange = 230,    -- player light radius, world px
        playerBright = 0.40,  -- player light intensity (1 = blinding white)
        muzzleRange = 210,    -- muzzle flash light radius
        muzzleBright = 0.65,  -- muzzle flash intensity
        muzzleTime = 0.06,    -- muzzle flash duration, secs

        torchRange = 190,       -- torch tile light radius, world px
        torchBright = 0.6,      -- torch light intensity
        torchFlickerSpeed = 7,  -- flicker rate (noise samples/sec)
        torchFlickerDepth = 0.3, -- how much the flicker moves the range (0-1)
    },

    zombies = {
        contactDamage = 25,   -- all types
        contactCooldown = 1.0, -- secs between hits, per zombie
        attackRange = 6,      -- px beyond touching circles where a hit lands
        growlMin = 6, growlMax = 16, -- secs between random growls, per zombie
        repathTime = 0.4,     -- secs between A* recalculations, per zombie
        waypointRadius = 13,  -- px from a path waypoint that counts as reached
        stuckRepath = 0.35,   -- secs of no progress before forcing an instant repath
        colliderCap = 28,     -- max wall-collision box (px) so big bodies fit 1-tile gaps

        slow   = { speed = 30, lifeMult = 1,   size = 48 },
        fast   = { speed = 60, lifeMult = 0.5,   size = 32 },
        runner = { speed = 90, lifeMult = 0.25, size = 21 },
    },

    waves = {
        quotaBase = 3,          -- zombies in wave w = this + w*(w+1)/2 -> 4, 6, 9, 13, 18, 24...

        lifeBase = 20,          -- wave-1 zombie life, before the type multiplier
        lifePerWave = 20,       -- +this per wave while wave <= lifeLinearUntil
        lifeLinearUntil = 7,    -- linear growth up to this wave (= 140)...
        lifeGrowth = 1.1,       -- ...then x this per wave afterwards

        spawnDelayStart = 2,    -- secs between spawns on wave 1
        spawnDelayDecay = 0.9,  -- delay multiplied by this each wave
        spawnDelayFloor = 0.3,  -- delay never drops below this

        startIntermission = 5,  -- secs of "WAVE N" banner before spawning starts
        endIntermission = 5,    -- secs of "WAVE COMPLETE" before the next wave

        -- spawn mix: last entry whose fromWave <= wave applies
        weights = {
            { fromWave = 1, slow = 70, fast = 30, runner = 0 },
            { fromWave = 4, slow = 40, fast = 45, runner = 15 },
            { fromWave = 8, slow = 20, fast = 45, runner = 35 },
        },
    },
}
