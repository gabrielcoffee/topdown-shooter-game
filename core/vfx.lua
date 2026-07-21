-- In-world visual effects: blood splatter on hits, muzzle sparks.
-- One instance per World. Particle systems live in world space and use
-- burst emits (moveTo + emit) so a single system serves every event.

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

function Vfx:update(dt)
    self.blood:update(dt)
    self.sparks:update(dt)
end

-- Drawn in world space, after entities
function Vfx:draw()
    love.graphics.draw(self.blood)
    love.graphics.setBlendMode('add')
    love.graphics.draw(self.sparks)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1)
end

return Vfx
