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

    -- blood: the shared puff sprite (muzzle frames 2+3 — frame 1 reads too
    -- big) in dark wine tints near the ground-decal palette. A particle
    -- system's color ramp repaints LIVE particles, so the tint variations
    -- live in a small pool of clones and each burst picks one at random.
    self.bloods = {}
    do
        local q2, q3 = Assets.quads.muzzle[2], Assets.quads.muzzle[3]
        local _, _, qw, qh = q2:getViewport()
        for _ = 1, 4 do
            local sys = love.graphics.newParticleSystem(Assets.spritesheet, 300)
            sys:setQuads(q2, q3)
            sys:setOffset(qw / 2, qh / 2)
            sys:setParticleLifetime(0.22, 0.45)
            sys:setSpread(0.9)
            sys:setSpeed(40, 170)
            sys:setLinearDamping(3, 6)
            sys:setRotation(0, math.pi * 2)
            sys:setSizeVariation(0.5)
            -- decal splats sit around (0.34..0.52, 0.04, 0.04); lean b up = wine
            local r = 0.34 + love.math.random() * 0.18
            local g = 0.03 + love.math.random() * 0.03
            local b = 0.05 + love.math.random() * 0.05
            sys:setColors(
                r, g, b, 1,
                r * 0.7, g * 0.7, b * 0.8, 0.9,
                r * 0.4, g * 0.5, b * 0.6, 0
            )
            table.insert(self.bloods, sys)
        end
    end

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
    self.dust = love.graphics.newParticleSystem(Assets.spritesheet, 600)
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

    -- med kit heal: the walk-dust puffs re-tinted soft pink, blooming around
    -- the player and drifting UP until their 3-frame puff plays out
    self.heal = self.dust:clone()
    self.heal:setParticleLifetime(0.4, 0.75)
    self.heal:setDirection(-math.pi / 2)
    self.heal:setSpread(0.55)
    self.heal:setSpeed(18, 42)
    self.heal:setLinearDamping(0, 0)
    self.heal:setLinearAcceleration(0, -45, 0, -20) -- keeps floating upward
    self.heal:setEmissionArea('uniform', 12, 10)    -- all around the body
    self.heal:setColors(1, 0.72, 0.82, TUNE.fx.healOpacity or 0.45)

    -- molotov ground fire: placeholder red/orange licks rising off the burn
    -- area; FirePatch bursts this every frame sized to its current radius
    self.fire = love.graphics.newParticleSystem(dot, 900)
    self.fire:setParticleLifetime(0.25, 0.6)
    self.fire:setDirection(-math.pi / 2) -- flames rise
    self.fire:setSpread(0.5)
    self.fire:setSpeed(15, 45)
    self.fire:setLinearAcceleration(0, -30, 0, -60)
    self.fire:setSizes(1.2, 0.8, 0.2)
    self.fire:setSizeVariation(1)
    self.fire:setColors(
        1, 0.9, 0.4, 1,
        1, 0.4, 0.1, 0.85,
        0.5, 0.1, 0.05, 0
    )

    -- door-open burst: wood chips in the door's gold/brown palette, scattered
    -- over the whole slab the moment it unlocks
    self.wood = love.graphics.newParticleSystem(dot, 200)
    self.wood:setParticleLifetime(0.3, 0.8)
    self.wood:setSpread(math.pi * 2)
    self.wood:setSpeed(30, 130)
    self.wood:setLinearDamping(2.5, 5)
    self.wood:setSizes(1.3, 0.8, 0.3)
    self.wood:setSizeVariation(1)
    self.wood:setColors(
        0.85, 0.70, 0.25, 1,
        0.60, 0.45, 0.12, 0.9,
        0.35, 0.27, 0.08, 0
    )

    -- stone chips knocked off walls by bullets
    self.chips = love.graphics.newParticleSystem(dot, 200)
    self.chips:setParticleLifetime(0.15, 0.4)
    self.chips:setSpread(1.2)
    self.chips:setSpeed(40, 150)
    self.chips:setLinearDamping(4, 8)
    self.chips:setSizes(0.8, 0.5, 0.2)
    self.chips:setSizeVariation(1)
    self.chips:setColors(
        0.62, 0.60, 0.56, 0.9,
        0.45, 0.44, 0.42, 0.7,
        0.3, 0.3, 0.3, 0
    )

    -- spawn-telegraph haze: dust clones tinted per zombie type, made lazily
    self.clouds = {}

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

-- angle = incoming bullet/swing angle; wine puffs spray forward from the
-- hit (knives and bullets alike). Random clone = random tint per burst.
function Vfx:bloodSplatter(x, y, angle)
    local sys = self.bloods[love.math.random(#self.bloods)]
    sys:moveTo(x, y)
    sys:setDirection(angle)
    sys:emit(TUNE.fx.bloodParticles)
end

-- Zombie spawn telegraph: ground haze in the incoming zombie's colors,
-- puffing over a patch the size of its body, every frame for the telegraph
-- second. A particle system's color ramp repaints LIVE particles, so each
-- tint gets its own lazy clone of the dust system instead of a shared one.
function Vfx:spawnCloud(x, y, half, color)
    local sys = self.clouds[color]
    if not sys then
        sys = self.dust:clone()
        sys:setColors(color[1], color[2], color[3], TUNE.fx.spawnCloudOpacity)
        self.clouds[color] = sys
    end
    sys:moveTo(x, y)
    sys:setEmissionArea('uniform', half, half)
    sys:emit(TUNE.fx.spawnCloudRate)
end

-- Bullet met a wall: a spark pinch bouncing back off the surface + a few
-- gray stone chips knocked out where it struck
function Vfx:wallHit(x, y, angle)
    self.sparks:moveTo(x, y)
    self.sparks:setDirection(angle + math.pi) -- ricochet back the way it came
    self.sparks:emit(4)
    self.chips:moveTo(x, y)
    self.chips:setDirection(angle + math.pi)
    self.chips:emit(5)
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

-- One frame's worth of flames over a burning circle (molotov fire patch)
-- mult scales the emission down when flame sprites carry most of the visual
function Vfx:fireBurst(x, y, radius, mult)
    self.fire:moveTo(x, y)
    self.fire:setEmissionArea('uniform', radius, radius)
    self.fire:emit(math.max(1, math.ceil(radius / 8 * (mult or 1))))
end

-- Puffs around the mover's feet, drifting off in random directions
function Vfx:footDust(x, y, count)
    self.dust:moveTo(x, y)
    self.dust:emit(count or TUNE.fx.dustCount)
end

-- Med kit used: pink dust blooms around the player and rises away
function Vfx:healBurst(x, y)
    self.heal:moveTo(x, y)
    self.heal:emit(TUNE.fx.healCount or 16)
end

-- Door unlocked: wood chips + a dust cloud over the full door rectangle
-- (hw/hh = half extents) and a brief gold spark pop where the lock gave way
function Vfx:doorBurst(cx, cy, hw, hh)
    self.wood:moveTo(cx, cy)
    self.wood:setEmissionArea('uniform', hw, hh)
    self.wood:emit(math.ceil(hw + hh))

    -- dust shares the footstep system; restore its feet-sized area after
    self.dust:moveTo(cx, cy)
    self.dust:setEmissionArea('uniform', hw, hh)
    self.dust:emit(math.ceil((hw + hh) / 2))
    self.dust:setEmissionArea('uniform', 10, 5)

    -- lock pop: sparks fly out in every direction (they're directional for
    -- muzzle flashes, so sweep the full circle in a few emits)
    for i = 0, 5 do
        self.sparks:moveTo(cx, cy)
        self.sparks:setDirection(i * math.pi / 3)
        self.sparks:emit(3)
    end
end

function Vfx:update(dt)
    for _, sys in ipairs(self.bloods) do sys:update(dt) end
    self.sparks:update(dt)
    self.chips:update(dt)
    self.boom:update(dt)
    self.dust:update(dt)
    self.heal:update(dt)
    self.fire:update(dt)
    self.wood:update(dt)
    for _, sys in pairs(self.clouds) do sys:update(dt) end
end

-- Ground-level effects, drawn before entities so they stay under them
function Vfx:drawUnder()
    love.graphics.draw(self.dust)
    for _, sys in pairs(self.clouds) do love.graphics.draw(sys) end
    love.graphics.setColor(1, 1, 1)
end

-- Drawn in world space, after entities
function Vfx:draw()
    love.graphics.draw(self.heal) -- rises over the player, so above entities
    for _, sys in ipairs(self.bloods) do love.graphics.draw(sys) end
    love.graphics.draw(self.wood)
    love.graphics.draw(self.chips)
    love.graphics.setBlendMode('add')
    love.graphics.draw(self.sparks)
    love.graphics.draw(self.boom)
    love.graphics.draw(self.fire)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1)
end

return Vfx
