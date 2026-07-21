-- ALL gameplay numbers live here. Edit with any text editor.
-- In game: press U to reload this file and restart the run with new values.

return {
    player = {
        maxHealth = 100,
        baseSpeed = 90, -- fallback when held item has no walkSpeed
        startMoney = 0,
        fallTime = 0.5,       -- secs of falling anim before hole respawn
        holeInvulnTime = 2,   -- secs of invincibility after hole respawn
        blinkInterval = 0.1,  -- sprite blink rate while invincible
    },

    movement = {
        accelTime = 0.45,   -- secs to reach max speed
        decelTime = 0.10,   -- secs to stop from max speed
        collisionInset = 4, -- px shaved off each AABB side vs tiles (32px body fits 32px gaps)
    },

    tiles = {
        size = 32,
        spikeDps = 20,        -- damage per second standing on spikes
        waterSpeedMult = 0.65,
        mudAccelMult = 0.25,  -- accel AND decel multiplied by this on mud
        holeDamage = 50,      -- player falls in a hole
    },

    crate = { pushDelay = 0.5, size = 32, health = 100, pushSpeedMult = 0.5,
              pushGrace = 0.15 }, -- secs of lost contact before a push resets
    door  = { price = 250, interactPad = 4 },

    guns = {
        usp    = { damage = 20, clip = 15, walkSpeed = 120, bulletDelay = 0.15, reloadTime = 2,   bulletLife = 0.5, killReward = 20 },
        ak47   = { damage = 40, clip = 30, walkSpeed = 90,  bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7, killReward = 10 },
        m4a1   = { damage = 35, clip = 25, walkSpeed = 90,  bulletDelay = 0.1,  reloadTime = 2.5, bulletLife = 0.7, killReward = 10 },
        lupara = { damage = 10, clip = 7,  walkSpeed = 100, bulletDelay = 0.5,  reloadTime = 1,   bulletLife = 0.7,
                   pellets = 14, spread = 0.20, killReward = 10 }, -- damage is per pellet
    },

    knife   = { damage = 60,  walkSpeed = 130, killReward = 50 },
    grenade = { damage = 120, walkSpeed = 120, killReward = 10 },

    bullet = { speed = 360 },

    audio = {
        masterDefault = 1,  -- 0..1, used until the player touches the options
        sfxDefault = 1,
        musicDefault = 1,
        poolSize = 6, -- max simultaneous plays of the same sound
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
        repathTime = 0.4,     -- secs between A* recalculations, per zombie

        slow   = { speed = 30, lifeMult = 2,   size = 48 },
        fast   = { speed = 60, lifeMult = 1,   size = 32 },
        runner = { speed = 90, lifeMult = 0.5, size = 21 },
    },

    waves = {
        quotaBase = 3,          -- zombies in wave w = this + w*(w+1)/2 -> 4, 6, 9, 13, 18, 24...

        lifeBase = 30,          -- wave-1 zombie life, before the type multiplier
        lifePerWave = 20,       -- +this per wave while wave <= lifeLinearUntil
        lifeLinearUntil = 9,    -- linear growth up to this wave (= 190)...
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
