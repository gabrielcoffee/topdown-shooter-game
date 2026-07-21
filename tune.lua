-- ALL gameplay numbers live here. Edit with any text editor.
-- In game: press U to reload this file and restart the run with new values.

return {
    player = {
        maxHealth = 100,
        baseSpeed = 90, -- fallback when held item has no walkSpeed
        startMoney = 0,
    },

    movement = {
        accelTime = 0.15,   -- secs to reach max speed
        decelTime = 0.10,   -- secs to stop from max speed
        collisionInset = 4, -- px shaved off each AABB side vs tiles (32px body fits 32px gaps)
    },

    tiles = {
        size = 32,
        spikeDps = 20,        -- damage per second standing on spikes
        waterSpeedMult = 0.75,
        mudAccelMult = 0.25,  -- accel AND decel multiplied by this on mud
        holeDamage = 50,      -- player falls in a hole
    },

    crate = { pushDelay = 0.5, size = 32 },
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

    zombies = {
        contactDamage = 10,   -- all types
        contactCooldown = 1.0, -- secs between hits, per zombie
        baseLifePerWave = 20, -- life = this * wave * type multiplier

        slow   = { speed = 30, lifeMult = 2,   size = 48 },
        fast   = { speed = 60, lifeMult = 1,   size = 32 },
        runner = { speed = 90, lifeMult = 0.5, size = 21 },
    },
}
