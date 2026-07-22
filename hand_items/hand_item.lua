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
        sprite = Assets.quads.knife[1],
        static = true,
        isKnife = true,
        walkSpeed = TUNE.knife.walkSpeed,
        damage = TUNE.knife.damage,
        killReward = TUNE.knife.killReward,

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

    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and e.health > 0 then
            local ecx, ecy = e:getCenter()
            local dx, dy = ecx - pcx, ecy - pcy
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist - e.radius <= K.range
                and math.abs(angleDiff(math.atan2(dy, dx), aimAngle)) <= math.rad(K.arcDeg) / 2 then

                local nx, ny = 1, 0
                if dist > 0 then nx, ny = dx/dist, dy/dist end

                e.health = e.health - self.damage
                e.flash = true
                e.kbx = nx * K.knockback
                e.kby = ny * K.knockback
                world.vfx:bloodSplatter(ecx - nx * e.radius, ecy - ny * e.radius, math.atan2(dy, dx))

                hit = true
                if e.health <= 0 then
                    player.money = player.money + self.killReward
                    killed = true
                end
            end
        end
    end

    if hit then
        world.hitstop = killed and K.hitstopKill or K.hitstop
        -- placeholder stab sfx until a real knife sound is added
        Audio.play(love.math.random() < 0.5 and 'bullet_hit1' or 'bullet_hit2')
    end
    return true
end

function HandItem:newGrenade(type)
    local obj = {
        name = 'M67 Frag',
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.grenade[1],
        static = true,
        type = type or 'he',
        isThrowable = true,
        walkSpeed = TUNE.grenade.walkSpeed,
        damage = TUNE.grenade.damage,
        killReward = TUNE.grenade.killReward
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:newHealthPack()
    local obj = {
        name = 'MED KIT',
        x = 0, y = 0,
        ox = 8, oy = 8,
        angle = 0,
        static = true,
        isHealthPack = true,
        walkSpeed = TUNE.healthpack.walkSpeed,
    }

    setmetatable(obj, HandItem)
    return obj
end

-- No spritesheet quad for the med kit: primitive white box + red cross.
-- Shared by the in-hand draw and the hotbar icon.
function HandItem.drawMedkitIcon(x, y, size)
    local s = size
    love.graphics.setColor(0.92, 0.92, 0.92)
    love.graphics.rectangle('fill', x, y, s, s, 2, 2)
    love.graphics.setColor(0.8, 0.1, 0.1)
    love.graphics.rectangle('fill', x + s*0.4,  y + s*0.15, s*0.2, s*0.7)
    love.graphics.rectangle('fill', x + s*0.15, y + s*0.4,  s*0.7, s*0.2)
    love.graphics.setColor(1, 1, 1)
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
        HandItem.drawMedkitIcon(math.floor(self.x) - 6, math.floor(self.y) - 6, 12)
        return
    end

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y),
        self.angle, 1, facingLeft and -1 or 1, self.ox, self.oy
    )
end

function HandItem:drawHud()
    love.graphics.print(self.name, 20, 20)
end

return HandItem