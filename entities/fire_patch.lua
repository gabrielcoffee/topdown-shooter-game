-- Ground fire left by a molotov. Spreads from the impact point to
-- molotov.blastRadius over spreadTime, burns for burnTime, and once per
-- tickInterval damages every zombie, crate AND the player inside the current
-- radius — with line of sight from the center, so fire never burns through
-- solid walls. Player burns ignore contact invuln (zone denial: standing in
-- fire keeps hurting). Visuals are per-frame particle bursts (Vfx.fire) + a
-- flickering point light; the entity itself draws nothing.

local Entity = require('entities.entity')

local FirePatch = {}
FirePatch.__index = FirePatch
setmetatable(FirePatch, Entity)

function FirePatch:new(x, y)
    local obj = Entity:new(x - 4, y - 4, 8, 8) -- tiny body centered on impact
    obj.type = 'fire_patch'
    obj.age = 0
    -- first tick once the fire has fully spread, then every tickInterval
    obj.tickTimer = TUNE.molotov.spreadTime
    obj.light = nil -- created on first update (needs world)
    setmetatable(obj, FirePatch)
    return obj
end

function FirePatch:currentRadius()
    local M = TUNE.molotov
    return M.blastRadius * math.min(1, self.age / M.spreadTime)
end

function FirePatch:update(dt, world)
    local M = TUNE.molotov
    self.age = self.age + dt

    if not self.light then
        local cx, cy = self:getCenter()
        self.light = world.lighting:addPoint(cx, cy, 1, 0.55, 0.2,
            M.blastRadius * 2.2)
    end

    local radius = self:currentRadius()
    local cx, cy = self:getCenter()

    -- flames: continuous burst emission over the burning area
    world.vfx:fireBurst(cx, cy, radius)

    self.tickTimer = self.tickTimer - dt
    if self.tickTimer <= 0 then
        self.tickTimer = self.tickTimer + M.tickInterval
        local econ = { hitReward = M.hitReward, killReward = M.killReward,
                       killBonus = M.killBonus }
        for _, e in ipairs(world.entities) do
            if not e.toRemove then
                local ex, ey = e:getCenter()
                local d = math.sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2)
                if d <= radius and not world.map:wallBetween(cx, cy, ex, ey) then
                    if e.type == 'enemy' and e.health > 0 then
                        e:takeDamage(M.tickDamage, world, econ)
                        world.vfx:bloodSplatter(ex, ey, math.atan2(ey - cy, ex - cx))
                    elseif e.type == 'crate' then
                        e.health = e.health - M.tickDamage
                        e.flash = true
                        if e.health <= 0 then world:removeEntity(e) end
                    elseif e.isPlayer and not e.falling and not e.godMode then
                        e.health = e.health - M.playerTickDamage
                        e.flashTimer = TUNE.player.hitFlashTime
                    end
                end
            end
        end
    end

    if self.age >= M.burnTime then
        if self.light then world.lighting:removePoint(self.light) end
        world:removeEntity(self)
    end
end

function FirePatch:draw()
    -- particles + light carry the visual; no placeholder body
end

return FirePatch
