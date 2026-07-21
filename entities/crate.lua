local Entity = require('entities.entity')
local Color = require('core.color')

local Crate = {}
Crate.__index = Crate
setmetatable(Crate, Entity)

function Crate:new(x, y)
    local obj = Entity:new(x, y, TUNE.crate.size, TUNE.crate.size)
    obj.type = 'crate'
    obj.isObstacle = true
    obj.health = TUNE.crate.health
    obj.pushTimer = 0
    obj.graceTimer = 0
    setmetatable(obj, Crate)
    return obj
end

-- Positional push, called from the player's collision resolution: the crate
-- has no velocity of its own, it moves by the player's penetration right here
-- (speed-capped, then clipped by its own walls/obstacles). Returns whether it
-- gave way, so the pusher knows to keep his speed against this face.
function Crate:pushBy(axis, sign, penetration, dt, world, pusherSpeed)
    self.pushedNow = true
    if self.pushTimer < TUNE.crate.pushDelay then return false end

    local cap = pusherSpeed * TUNE.crate.pushSpeedMult * dt
    if world.map:typeAt(self:getCenter()) == 'water' then
        cap = cap * TUNE.tiles.waterSpeedMult
    end
    local amount = math.min(penetration, cap)
    if amount <= 0 then return false end

    local before = (axis == 'x') and self.x or self.y
    if axis == 'x' then
        self.x = self.x + sign * amount
        self.vx = sign -- direction hint so _resolveAxis snaps the right way
    else
        self.y = self.y + sign * amount
        self.vy = sign
    end
    self:_resolveAxis(world, axis, dt)
    self.vx, self.vy = 0, 0

    -- safety net: never leave the map (normally moveAndCollide's job)
    self.x = math.max(0, math.min(self.x, world.mapW - self.width))
    self.y = math.max(0, math.min(self.y, world.mapH - self.height))

    local after = (axis == 'x') and self.x or self.y
    return math.abs(after - before) > 0.0001
end

function Crate:update(dt, world)
    -- pushTimer counts continuous contact (any face); the grace window keeps
    -- it alive through 1-frame contact gaps so the delay doesn't restart
    if self.pushedNow then
        self.pushTimer = self.pushTimer + dt
        self.graceTimer = 0
    else
        self.graceTimer = self.graceTimer + dt
        if self.graceTimer > TUNE.crate.pushGrace then
            self.pushTimer = 0
        end
    end
    self.pushedNow = false

    -- pushed over a hole: falls in and plugs it (tile becomes ground)
    local cx, cy = self:getCenter()
    if world.map:typeAt(cx, cy) == 'hole' then
        local ts = world.map.tileSize
        world.map:setTile(math.floor(cx / ts) + 1, math.floor(cy / ts) + 1,
                          world.map.groundFillId)
        world:removeEntity(self)
    end
end

function Crate:draw()
    if self.flash then
        love.graphics.setColor(Color.white())
    else
        love.graphics.setColor(0.55, 0.38, 0.18)
    end
    love.graphics.rectangle('fill', math.floor(self.x), math.floor(self.y), self.width, self.height)
    love.graphics.setColor(0.35, 0.23, 0.10)
    love.graphics.rectangle('line', math.floor(self.x), math.floor(self.y), self.width, self.height)
    self.flash = false

    -- crate health, same style as zombies
    local hp = math.ceil(self.health)
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.35, 0.23, 0.10)
    love.graphics.print(hp, self.x + self.width/2 - smallFont:getWidth(hp)/2, self.y - smallFont:getHeight())
    love.graphics.setFont(font)
    love.graphics.setColor(Color.white())
end

return Crate
