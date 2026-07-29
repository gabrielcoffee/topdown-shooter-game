local Assets = require('core.assets')
local Audio = require('core.audio')

local HandItem = {}
HandItem.__index = HandItem

local offsetX = 16
local offsetY = 16

function HandItem:newKnife()
    local obj = {
        name = 'M9 Bayonet',
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.held_knife[1],
        icon = Assets.quads.knife[1],
        static = true,
        isKnife = true,
        damage = TUNE.knife.damage,
        econ = { hitReward = TUNE.knife.hitReward,
                 killBonus = TUNE.knife.killBonus },

        cdTimer = 0,    -- secs until the next swing is allowed
        swingTimer = 0, -- secs left of the visual sweep
        aimAngle = 0,   -- locked at swing start
        swingDir = 1,   -- sweep side alternates each swing
    }

    setmetatable(obj, HandItem)
    return obj
end

-- Signed smallest difference between two angles
local function angleDiff(a, b)
    return (a - b + math.pi) % (2 * math.pi) - math.pi
end

-- Swing toward aimAngle: instant arc hit check on every enemy in reach,
-- knockback + blood + hitstop on connect. Returns true if the swing started
-- (cooldown gate), whether or not it hit anything.
function HandItem:swing(aimAngle, player, world)
    if self.cdTimer > 0 then return false end
    local K = TUNE.knife
    self.cdTimer = K.cooldown
    self.swingTimer = K.swingTime
    self.aimAngle = aimAngle
    self.swingDir = -self.swingDir

    local pcx, pcy = player:getCenter()
    local hit, killed = false, false
    Audio.playAt('knife_swing', pcx, pcy, 0.8, TUNE.audio.pitchJitter, world)

    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and e.health > 0 then
            local ecx, ecy = e:getCenter()
            local dx, dy = ecx - pcx, ecy - pcy
            local dist = math.sqrt(dx*dx + dy*dy)

            -- reach + arc + line of sight: range (44) beats a tile (32), so
            -- without the wall test the knife stabbed through thin walls
            if dist - e.radius <= K.range
                and math.abs(angleDiff(math.atan2(dy, dx), aimAngle)) <= math.rad(K.arcDeg) / 2
                and not world.map:wallBetween(pcx, pcy, ecx, ecy) then

                local nx, ny = 1, 0
                if dist > 0 then nx, ny = dx/dist, dy/dist end

                local dead = e:takeDamage(self.damage, world, self.econ)
                e.kbx = nx * K.knockback
                e.kby = ny * K.knockback
                world.vfx:bloodSplatter(ecx - nx * e.radius, ecy - ny * e.radius, math.atan2(dy, dx))

                hit = true
                killed = killed or dead
            end
        elseif e.type == 'crate' and not e.toRemove then
            -- crates take knife damage too (same reach/arc/wall rules;
            -- half the crate's 32px box stands in for a radius)
            local ecx, ecy = e:getCenter()
            local dx, dy = ecx - pcx, ecy - pcy
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist - e.width / 2 <= K.range
                and math.abs(angleDiff(math.atan2(dy, dx), aimAngle)) <= math.rad(K.arcDeg) / 2
                and not world.map:wallBetween(pcx, pcy, ecx, ecy) then

                e.health = e.health - self.damage
                e.flash = true
                if e.health <= 0 then world:removeEntity(e) end
                hit = true
            end
        end
    end

    if hit then
        world.hitstop = killed and K.hitstopKill or K.hitstop
        Audio.playAt('knife_hit', pcx, pcy, 1, TUNE.audio.pitchJitter, world)
    end
    return true
end

-- Slot-4 throwable. kind 'he' (default) or 'molotov'.
function HandItem:newGrenade(kind)
    kind = kind or 'he'
    local molotov = kind == 'molotov'
    local obj = {
        name = molotov and 'Molotov' or 'M67 Frag',
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads[molotov and 'held_molotov' or 'held_grenade'][1],
        icon = Assets.quads[molotov and 'molotov' or 'grenade'][1],
        static = true,
        throwKind = kind,
        isThrowable = true,
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:newHealthPack()
    local obj = {
        name = 'MED KIT',
        x = 0, y = 0,
        ox = 4, oy = 16,    -- held out from the hand like the pistol (no aim rotation)
        angle = 0,
        sprite = Assets.quads.held_medkit[1],
        icon = Assets.quads.medkit[1],
        static = true,
        isHealthPack = true,
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:update(dt, px, py, mx, my)
    self.x = px + offsetX
    self.y = py + offsetY

    local dx, dy = mx-self.x, my-self.y
    self.angle = math.atan2(dy, dx)

    if self.isKnife then
        self.cdTimer = math.max(0, self.cdTimer - dt)
        if self.swingTimer > 0 then
            self.swingTimer = math.max(0, self.swingTimer - dt)
            -- sweep across the arc, alternating side each swing
            local t = 1 - self.swingTimer / TUNE.knife.swingTime
            local halfArc = math.rad(TUNE.knife.arcDeg) / 2
            self.angle = self.aimAngle + self.swingDir * halfArc * (2*t - 1)
        end
    end
end

function HandItem:draw(facingLeft)
    if self.isHealthPack then
        -- medkit doesn't aim: fixed upright, mirror horizontally on facing
        love.graphics.draw(
            Assets.spritesheet, self.sprite,
            math.floor(self.x), math.floor(self.y),
            0, facingLeft and -1 or 1, 1, self.ox, self.oy
        )
        return
    end

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y),
        self.angle, 1, facingLeft and -1 or 1, self.ox, self.oy
    )
    love.graphics.setColor(1, 1, 1)
end

function HandItem:drawHud()
    love.graphics.print(self.name, 20, SCREENHEIGHT - 40)
end

return HandItem