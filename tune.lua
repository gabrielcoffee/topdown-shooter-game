-- ALL gameplay numbers live here. Edit with any text editor.
-- In game: press U to reload this file and restart the run with new values.

return {
    player = {
        maxHealth = 100,
        baseSpeed = 90, -- fallback when held item has no walkSpeed
    },

    guns = {
        usp    = { damage = 20, clip = 15, walkSpeed = 120, bulletDelay = 0.15, reloadTime = 2,   bulletLife = 0.5 },
        ak47   = { damage = 40, clip = 30, walkSpeed = 90,  bulletDelay = 0.1,  reloadTime = 2.7, bulletLife = 0.7 },
        m4a1   = { damage = 35, clip = 25, walkSpeed = 90,  bulletDelay = 0.1,  reloadTime = 2.7, bulletLife = 0.7 },
        lupara = { damage = 10, clip = 7,  walkSpeed = 100, bulletDelay = 0.5,  reloadTime = 1,   bulletLife = 0.7,
                   pellets = 14, spread = 0.15 }, -- damage is per pellet
    },

    knife   = { damage = 60,  walkSpeed = 130 },
    grenade = { damage = 120, walkSpeed = 120 },

    bullet = { speed = 360 },

    zombies = {
        contactDamage = 10,   -- all types
        contactCooldown = 1.0, -- secs between hits, per zombie
        baseLifePerWave = 20, -- life = this * wave * type multiplier

        slow   = { speed = 30, lifeMult = 2,   size = 48 },
        fast   = { speed = 60, lifeMult = 1,   size = 32 },
        runner = { speed = 90, lifeMult = 0.5, size = 21 },
    },
}
