-- A live grenade flying toward the aim point (already clamped to
-- grenade.maxRange by the thrower). It arcs OVER walls — nothing stops the
-- flight. Fuse runs from the throw, so it can blow mid-air or on the ground.
-- Flat damage inside the blast radius (no falloff), same kill-reward flow
-- as bullets.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Audio = require('core.audio')

local ThrownGrenade = {}
ThrownGrenade.__index = ThrownGrenade
setmetatable(ThrownGrenade, Entity)

function ThrownGrenade:new(x, y, targetX, targetY)
    local obj = Entity:new(x, y, 8, 8)
    obj.type = 'thrown_grenade'

    obj.startX, obj.startY = x, y
    obj.dist = math.max(1, math.sqrt((targetX-x)^2 + (targetY-y)^2))
    obj.dx = (targetX - x) / obj.dist
    obj.dy = (targetY - y) / obj.dist
    obj.travelled = 0
    obj.landed = false

    obj.age = 0
    obj.sprite = Assets.quads.grenade[1]

    setmetatable(obj, ThrownGrenade)
    return obj
end

function ThrownGrenade:update(dt, world)
    self.age = self.age + dt

    if not self.landed then
        -- flies over walls: the throw arc clears everything on the way
        local step = TUNE.grenade.throwSpeed * dt
        self.x = self.x + self.dx * step
        self.y = self.y + self.dy * step
        self.travelled = self.travelled + step
        if self.travelled >= self.dist then self.landed = true end
    end

    if self.age >= TUNE.grenade.fuse then
        self:explode(world)
    end
end

function ThrownGrenade:explode(world)
    local G = TUNE.grenade
    local radius = G.blastRadius
    local damage = G.damage
    local econ = { hitReward = G.hitReward, killBonus = G.killBonus }

    for _, e in ipairs(world.entities) do
        if not e.toRemove then
            local ex, ey = e:getCenter()
            local d = math.sqrt((ex - self.x)^2 + (ey - self.y)^2)
            -- blast needs line of sight from where it landed: the throw arcs
            -- over walls by design, but the explosion doesn't blow through them
            if d <= radius and not world.map:wallBetween(self.x, self.y, ex, ey) then
                if e.type == 'enemy' and e.health > 0 then
                    e:takeDamage(damage, world, econ)
                    world.vfx:bloodSplatter(ex, ey, math.atan2(ey - self.y, ex - self.x))
                elseif e.type == 'crate' then
                    e.health = e.health - damage
                    e.flash = true
                    if e.health <= 0 then world:removeEntity(e) end
                end
            end
        end
    end

    world.lighting:flash(self.x, self.y, 1, 0.75, 0.4, radius * 4, 0.15)
    world.vfx:explosion(self.x, self.y)
    Audio.playAt('grenade_blast', self.x, self.y)
    world:removeEntity(self)
end

function ThrownGrenade:draw()
    -- fake arc: parabolic hop over the flight, spinning as it flies
    local progress = math.min(1, self.travelled / self.dist)
    local arc = math.sin(progress * math.pi) * math.min(24, self.dist * 0.2)

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y - arc),
        self.age * 10, 0.6, 0.6, 16, 16
    )
end

return ThrownGrenade
