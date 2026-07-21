-- Menu background atmosphere: floating embers + drifting fog layers.
-- Textures are generated at load (soft radial gradients) — no image assets.

local Particles = {}

local embers
local fogTex
local fogs = {}

-- Soft radial gradient circle on a canvas; power shapes the falloff.
-- coreR (optional) stamps a hot bright center so sparks read + bloom.
local function softCircle(size, power, coreR)
    local canvas = love.graphics.newCanvas(size, size)
    love.graphics.setCanvas(canvas)
    local c = size / 2
    for r = c, 1, -1 do
        local a = (1 - r / c) ^ power
        love.graphics.setColor(1, 1, 1, a * 0.16)
        love.graphics.circle('fill', c, c, r)
    end
    if coreR then
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.circle('fill', c, c, coreR)
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    return canvas
end

function Particles.load()
    -- embers: small hot dots rising from the bottom of the screen
    local emberTex = softCircle(16, 1.6, 2.5)
    embers = love.graphics.newParticleSystem(emberTex, 400)
    embers:setPosition(SCREENWIDTH / 2, SCREENHEIGHT + 24)
    embers:setEmissionArea('uniform', SCREENWIDTH / 2, 12)
    embers:setParticleLifetime(5, 10)
    embers:setEmissionRate(TUNE.fx.emberRate)
    embers:setDirection(-math.pi / 2)
    embers:setSpread(0.5)
    embers:setSpeed(18, 70)
    embers:setLinearAcceleration(-10, -22, 10, -6)
    embers:setSizes(1.4, 1.0, 0.45)
    embers:setSizeVariation(1)
    embers:setColors(
        1.0, 0.65, 0.20, 0.0,
        1.0, 0.55, 0.16, 1.0,
        0.95, 0.28, 0.08, 0.8,
        0.35, 0.05, 0.02, 0.0
    )
    -- prewarm in small steps (one big dt integrates in a single step and
    -- throws every particle off screen)
    for _ = 1, 150 do embers:update(1 / 15) end

    -- fog: wide soft blobs sliding across the lower screen
    fogTex = softCircle(256, 2.2)
    fogs = {}
    local defs = {
        { y = SCREENHEIGHT * 0.80, sx = 7.0, sy = 2.6, speed = 14, alpha = 1.0, shade = 0.30 },
        { y = SCREENHEIGHT * 0.62, sx = 5.5, sy = 2.0, speed = -9, alpha = 0.7, shade = 0.22 },
        { y = SCREENHEIGHT * 0.90, sx = 8.5, sy = 3.0, speed = 21, alpha = 1.2, shade = 0.16 },
    }
    for i, d in ipairs(defs) do
        d.x = (i - 1) * SCREENWIDTH * 0.6
        table.insert(fogs, d)
    end
end

function Particles.update(dt)
    embers:setEmissionRate(TUNE.fx.emberRate)
    embers:update(dt)

    for _, f in ipairs(fogs) do
        f.x = f.x + f.speed * dt
        if f.speed > 0 and f.x > SCREENWIDTH + 256 * f.sx / 2 then
            f.x = -256 * f.sx / 2
        elseif f.speed < 0 and f.x < -256 * f.sx / 2 then
            f.x = SCREENWIDTH + 256 * f.sx / 2
        end
    end
end

function Particles.emberCount()
    return embers and embers:getCount() or 0
end

-- Behind the title/menu text
function Particles.drawFog()
    for _, f in ipairs(fogs) do
        love.graphics.setColor(f.shade, f.shade, f.shade + 0.02, TUNE.fx.fogAlpha * f.alpha)
        love.graphics.draw(fogTex, f.x, f.y, 0, f.sx, f.sy, 128, 128)
    end
    love.graphics.setColor(1, 1, 1)
end

-- In front of everything (embers float past the text)
function Particles.drawEmbers()
    love.graphics.setBlendMode('add')
    love.graphics.draw(embers)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1)
end

return Particles
