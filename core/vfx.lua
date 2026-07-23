-- In-world visual effects: blood splatter on hits, muzzle sparks.
-- One instance per World. Particle systems live in world space and use
-- burst emits (moveTo + emit) so a single system serves every event.

local Assets = require('core.assets')

local Vfx = {}
Vfx.__index = Vfx

local function softDot(size, power)
    local canvas = love.graphics.newCanvas(size, size)
    love.graphics.setCanvas(canvas)
    local c = size / 2
    for r = c, 1, -1 do
        love.graphics.setColor(1, 1, 1, ((1 - r / c) ^ power) * 0.25)
        love.graphics.circle('fill', c, c, r)
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    return canvas
end

function Vfx.new()
    local self = setmetatable({}, Vfx)
    local dot = softDot(8, 1.2)

    self.blood = love.graphics.newParticleSystem(dot, 600)
    self.blood:setParticleLifetime(0.25, 0.7)
    self.blood:setSpread(1.1)
    self.blood:setSpeed(30, 150)
    self.blood:setLinearDamping(2, 4)
    self.blood:setSizes(0.9, 0.7, 0.3)
    self.blood:setSizeVariation(1)
    self.blood:setColors(
        0.75, 0.05, 0.05, 1,
        0.55, 0.03, 0.03, 0.9,
        0.30, 0.01, 0.01, 0
    )

    self.sparks = love.graphics.newParticleSystem(dot, 200)
    self.sparks:setParticleLifetime(0.05, 0.16)
    self.sparks:setSpread(0.7)
    self.sparks:setSpeed(120, 320)
    self.sparks:setSizes(0.6, 0.2)
    self.sparks:setColors(
        1, 0.95, 0.6, 1,
        1, 0.6, 0.2, 0
    )

    -- movement dust: the muzzle-flash sprite frames at constant low alpha
    -- (no fade — each puff plays the 3 frames and pops out)
    self.dust = love.graphics.newParticleSystem(Assets.spritesheet, 300)
    self.dust:setQuads(unpack(Assets.quads.muzzle))
    local _, _, qw, qh = Assets.quads.muzzle[1]:getViewport()
    self.dust:setOffset(qw / 2, qh / 2)
    self.dust:setParticleLifetime(0.3, 0.5)
    self.dust:setSpread(math.pi * 2) -- puffs drift in a random direction
    self.dust:setSpeed(6, 22)
    self.dust:setLinearDamping(1, 3)
    self.dust:setRotation(0, math.pi * 2)
    self.dust:setSizeVariation(0.4)
    self.dust:setEmissionArea('uniform', 10, 5) -- around the feet, front included
    local da = TUNE.fx.dustOpacity
    self.dust:setColors(1, 1, 1, da) -- one stop = constant alpha, no fade

    self.boom = love.graphics.newParticleSystem(dot, 300)
    self.boom:setParticleLifetime(0.15, 0.5)
    self.boom:setSpread(math.pi * 2)
    self.boom:setSpeed(60, 260)
    self.boom:setLinearDamping(3, 6)
    self.boom:setSizes(1.6, 1.0, 0.3)
    self.boom:setSizeVariation(1)
    self.boom:setColors(
        1, 0.95, 0.7, 1,
        1, 0.55, 0.15, 0.9,
        0.35, 0.3, 0.28, 0
    )

    return self
end

-- angle = incoming bullet angle; blood sprays forward from the hit
function Vfx:bloodSplatter(x, y, angle)
    self.blood:moveTo(x, y)
    self.blood:setDirection(angle)
    self.blood:emit(TUNE.fx.bloodParticles)
end

function Vfx:muzzleSparks(x, y, angle)
    self.sparks:moveTo(x, y)
    self.sparks:setDirection(angle)
    self.sparks:emit(6)
end

function Vfx:explosion(x, y)
    self.boom:moveTo(x, y)
    self.boom:emit(60)
end

-- Puffs around the mover's feet, drifting off in random directions
function Vfx:footDust(x, y)
    self.dust:moveTo(x, y)
    self.dust:emit(TUNE.fx.dustCount)
end

function Vfx:update(dt)
    self.blood:update(dt)
    self.sparks:update(dt)
    self.boom:update(dt)
    self.dust:update(dt)
end

-- Ground-level effects, drawn before entities so they stay under them
function Vfx:drawUnder()
    love.graphics.draw(self.dust)
    love.graphics.setColor(1, 1, 1)
end

-- Drawn in world space, after entities
function Vfx:draw()
    love.graphics.draw(self.blood)
    love.graphics.setBlendMode('add')
    love.graphics.draw(self.sparks)
    love.graphics.draw(self.boom)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1)
end

return Vfx
