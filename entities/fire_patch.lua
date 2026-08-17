-- Ground fire left by a molotov. Spreads from the impact point to
-- molotov.blastRadius over spreadTime, burns for burnTime, and once per
-- tickInterval damages every zombie and crate inside the current radius —
-- with line of sight from the center, so fire never burns through solid
-- walls. The player burns on their own faster clock (playerTickInterval /
-- playerTickDamage) and ignores contact invuln (zone denial: standing in
-- fire keeps hurting). Visuals: a scatter of animated fire.gif sprites over the
-- burn area (each pops in when the spread reaches it) plus a flickering point
-- light; ember particles / scorch / glow exist behind tune values, all 0 = off.

local Entity = require('entities.entity')
local Audio = require('core.audio')
local Gif = require('core.gif')

local GOLDEN = 2.39996323 -- rad; golden-angle spiral = even disc coverage

local FirePatch = {}
FirePatch.__index = FirePatch
setmetatable(FirePatch, Entity)

function FirePatch:new(x, y, owner)
    local obj = Entity:new(x - 4, y - 4, 8, 8) -- tiny body centered on impact
    obj.type = 'fire_patch'
    obj.owner = owner -- the molotov thrower, paid for burn kills
    obj.age = 0
    -- first tick once the fire has fully spread, then every tickInterval
    obj.tickTimer = TUNE.molotov.spreadTime
    obj.playerTickTimer = TUNE.molotov.spreadTime
    obj.light = nil -- created on first update (needs world)
    setmetatable(obj, FirePatch)
    return obj
end

-- Scatter the flame sprites over the burn disc. Needs the world for the wall
-- checks, so this runs on the first update rather than in :new.
function FirePatch:spawnFlames(world)
    local M = TUNE.molotov
    local F = M.flame
    local cx, cy = self:getCenter()
    self.gif = Gif.load('assets/images/world/fire.gif')
    self.flames = {}

    for i = 1, F.count do
        -- sqrt spacing keeps the density even instead of clumping at the center
        local frac = (i - 0.5) / F.count
        local dist = M.blastRadius * math.sqrt(frac) * (0.85 + love.math.random() * 0.3)
        local ang = i * GOLDEN + love.math.random() * 0.4
        local dx, dy = math.cos(ang) * dist, math.sin(ang) * dist
        local fx, fy = cx + dx, cy + dy
        -- fire doesn't burn inside walls or around corners
        if not world.map:isSolidAt(fx, fy) and not world.map:wallBetween(cx, cy, fx, fy) then
            local jitter = 1 + (love.math.random() * 2 - 1) * F.scaleJitter
            table.insert(self.flames, {
                dx = dx, dy = dy,
                -- outer flames a bit smaller: reads as the fire thinning out
                scale = F.scale * (1 - F.scaleFalloff * (dist / M.blastRadius)) * jitter,
                appearAt = M.spreadTime * (dist / M.blastRadius),
                frameOffset = love.math.random(0, self.gif.frames - 1),
                speed = 0.92 + love.math.random() * 0.16, -- slight desync of the loops
                flip = love.math.random() < 0.5 and -1 or 1,
                phase = love.math.random() * math.pi * 2,
            })
        end
    end
    -- lower flames drawn last so they overlap the ones behind them
    table.sort(self.flames, function(a, b) return a.dy < b.dy end)
end

-- Ground decal: sort from the top of the burn area so zombies/player walking
-- through the fire draw in front of the flames instead of being covered.
function FirePatch:sortY()
    return self.y + self.height - TUNE.molotov.blastRadius
end

function FirePatch:currentRadius()
    local M = TUNE.molotov
    return M.blastRadius * math.min(1, self.age / M.spreadTime)
end

-- /recording footage mode stretches the burn (reads the world global, same
-- as the chest's fire-sale check)
function FirePatch:burnTime()
    if world and world.recordingMode then return TUNE.recording.burnTime end
    return TUNE.molotov.burnTime
end

-- 1 while burning, easing to 0 over the last fadeTime secs
function FirePatch:dying()
    local left = self:burnTime() - self.age
    return math.min(1, math.max(0, left / TUNE.molotov.flame.fadeTime))
end

-- Client: the fire is a light, a sound and some sprites. Everything it looks
-- like derives from `age`, which the snapshot keeps in step, so all this has
-- to do is run the same envelope without any of the burn damage.
function FirePatch:updateRemote(dt, world)
    local M = TUNE.molotov
    self.age = self.age + dt

    if not self.light then
        local cx, cy = self:getCenter()
        self.light = world.lighting:addPoint(cx, cy, 1, 0.55, 0.2,
            M.blastRadius * 2.2)
        self:spawnFlames(world)
        self.sound = Audio.loopAt('fire_loop', cx, cy, 0)
    end

    local up = math.min(1, self.age / M.spreadTime)
    local dying = self:dying()
    if self.sound then Audio.setLoopGain(self.sound, M.fireGain * up * dying) end
    if self.light then
        self.light.baseRange = M.blastRadius * 2.2 * up * dying
    end
    if M.flame.emberFactor > 0 then
        local cx, cy = self:getCenter()
        world.vfx:fireBurst(cx, cy, self:currentRadius(), M.flame.emberFactor)
    end
end

function FirePatch:update(dt, world)
    local M = TUNE.molotov
    self.age = self.age + dt

    if not self.light then
        local cx, cy = self:getCenter()
        self.light = world.lighting:addPoint(cx, cy, 1, 0.55, 0.2,
            M.blastRadius * 2.2)
        self:spawnFlames(world)
        -- burn loop: rises with the spread, dies out with the flames
        self.sound = Audio.loopAt('fire_loop', cx, cy, 0)
    end

    -- spread-in / burn-out envelope, shared by the sound, the light and the
    -- flame sprites so nothing outlives the others
    local up = math.min(1, self.age / M.spreadTime)
    local dying = self:dying()

    if self.sound then
        Audio.setLoopGain(self.sound, M.fireGain * up * dying)
    end
    -- the point light grows and dies with the flames (Lighting flickers around
    -- baseRange every frame, so writing it here is all it takes)
    if self.light then
        self.light.baseRange = M.blastRadius * 2.2 * up * dying
    end

    local radius = self:currentRadius()
    local cx, cy = self:getCenter()

    -- embers on top of the flame sprites (emberFactor 0 = sprites only;
    -- fireBurst emits at least 1 particle per frame, so it must be skipped)
    if M.flame.emberFactor > 0 then
        world.vfx:fireBurst(cx, cy, radius, M.flame.emberFactor)
    end

    self.tickTimer = self.tickTimer - dt
    if self.tickTimer <= 0 then
        self.tickTimer = self.tickTimer + M.tickInterval
        local econ = { hitReward = M.hitReward, killBonus = M.killBonus }
        for _, e in ipairs(world.entities) do
            if not e.toRemove then
                local ex, ey = e:getCenter()
                local d = math.sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2)
                if d <= radius and not world.map:wallBetween(cx, cy, ex, ey) then
                    if e.type == 'enemy' and e.health > 0 then
                        -- footage mode: every zombie dies in exactly N ticks
                        local dmg = M.tickDamage
                        if world.recordingMode and e.maxHealth then
                            dmg = e.maxHealth / TUNE.recording.molotovTicksToKill
                        end
                        e:takeDamage(dmg, world, econ, self.owner)
                        world.vfx:bloodSplatter(ex, ey, math.atan2(ey - cy, ex - cx))
                    elseif e.type == 'crate' then
                        e:hit(M.tickDamage, world, econ, self.owner)
                    end
                end
            end
        end
    end

    -- player burn: own faster clock, same reach + wall rules as the main tick
    self.playerTickTimer = self.playerTickTimer - dt
    if self.playerTickTimer <= 0 then
        self.playerTickTimer = self.playerTickTimer + M.playerTickInterval
        for _, p in ipairs(world.players) do
            if p and not p.toRemove and not p.falling and not p.godMode
                and p.health > 0 then
                local px, py = p:getCenter()
                local d = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
                if d <= radius and not world.map:wallBetween(cx, cy, px, py) then
                    p.health = p.health - M.playerTickDamage
                    p.flashTimer = TUNE.player.hitFlashTime
                end
            end
        end
    end

    if self.age >= self:burnTime() then
        if self.light then world.lighting:removePoint(self.light) end
        Audio.stopLoop(self.sound)
        self.sound = nil
        world:removeEntity(self)
    end
end

function FirePatch:draw()
    if not self.flames then return end
    local M, F = TUNE.molotov, TUNE.molotov.flame
    local cx, cy = self:getCenter()
    local g = self.gif
    local ox, oy = g.width / 2, g.height - 2 -- flames sit on the ground

    -- whole patch dies over the last fadeTime secs: the flames SHRINK away at
    -- full opacity (fading their alpha instead left ghost flames lit by a
    -- light that was still at full range)
    local dying = self:dying()

    -- burnt ground + heat glow so the scattered flames read as one burning area
    local radius = self:currentRadius()
    love.graphics.setColor(0.05, 0.02, 0.02, F.scorchAlpha * dying)
    love.graphics.circle('fill', cx, cy, radius)
    love.graphics.setBlendMode('add')
    love.graphics.setColor(0.6, 0.22, 0.06, F.glowAlpha * dying)
    love.graphics.circle('fill', cx, cy, radius * 0.9)
    love.graphics.setBlendMode('alpha')

    for _, f in ipairs(self.flames) do
        local t = self.age - f.appearAt
        if t > 0 then
            local pop = math.min(1, t / F.popTime)
            pop = pop * pop * (3 - 2 * pop) -- smoothstep grow-in
            -- same size for every flame while burning; only the die-off scales
            local s = f.scale * pop * dying
            local bob = math.sin(self.age * F.bobSpeed + f.phase) * F.bobAmp
            local frame = math.floor(t * F.fps * f.speed + f.frameOffset) % g.frames + 1
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(g.image, g.quads[frame],
                math.floor(cx + f.dx), math.floor(cy + f.dy + bob),
                0, s * f.flip, s, ox, oy)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return FirePatch
