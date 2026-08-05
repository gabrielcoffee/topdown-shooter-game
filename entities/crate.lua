local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')

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

-- Another pushable crate sitting flush ahead in the push direction?
function Crate:crateAhead(world, axis, sign)
    local x0, y0 = self.x, self.y
    local x1, y1 = self.x + self.width, self.y + self.height
    if axis == 'x' then
        if sign > 0 then x1 = x1 + 1 else x0 = x0 - 1 end
    else
        if sign > 0 then y1 = y1 + 1 else y0 = y0 - 1 end
    end
    for _, e in ipairs(world.entities) do
        if e.pushBy and e ~= self and not e.toRemove
            and e.x < x1 and e.x + e.width > x0
            and e.y < y1 and e.y + e.height > y0 then
            return true
        end
    end
    return false
end

-- Positional push, called from the player's collision resolution: the crate
-- has no velocity of its own, it moves by the player's penetration right here
-- (speed-capped, then clipped by its own walls/obstacles). Returns whether it
-- gave way, so the pusher knows to keep his speed against this face.
-- Speed cap ramps: starts at a crawl the moment contact lands and works up to
-- full WALK speed over pushRampTime (heavy-box feel). Sprinting doesn't push
-- faster — a crate never outruns walk speed.
-- Chains: a pushed crate hands the crate ahead its budget minus one, so the
-- player moves rows up to crate.maxChain long — at chainSpeedMult of walk
-- speed — and a longer row blocks like a wall.
function Crate:pushBy(axis, sign, penetration, dt, world, pusherSpeed, pusher)
    self.pushedNow = true

    local C = TUNE.crate
    local k = math.min(1, self.pushTimer / C.pushRampTime)
    local speed = TUNE.player.baseSpeed * (C.pushStartFrac + (1 - C.pushStartFrac) * k)
    if pusher and pusher.isPlayer and self:crateAhead(world, axis, sign) then
        speed = speed * (C.chainSpeedMult or 1)
    end
    local cap = speed * dt
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
    -- budget for crates THIS crate runs into during its own resolve
    self.pushBudget = (pusher and pusher.isPlayer)
        and ((C.maxChain or 1) - 1)
        or math.max(0, ((pusher and pusher.pushBudget) or 1) - 1)
    self:_resolveAxis(world, axis, dt)
    self.pushBudget = nil
    self.vx, self.vy = 0, 0

    -- safety net: never leave the map (normally moveAndCollide's job)
    self.x = math.max(0, math.min(self.x, world.mapW - self.width))
    self.y = math.max(0, math.min(self.y, world.mapH - self.height))

    local after = (axis == 'x') and self.x or self.y
    return math.abs(after - before) > 0.0001
end

function Crate:update(dt, world)
    -- pushTimer counts continuous contact (any face) and drives the push
    -- speed ramp; the grace window keeps it alive through 1-frame contact
    -- gaps so the ramp doesn't restart
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

    -- pushed over a hole: falls in and plugs it (tile becomes ground);
    -- the plug is a map edit, so it's recorded for the run save
    local cx, cy = self:getCenter()
    if world.map:typeAt(cx, cy) == 'hole' then
        local ts = world.map.tileSize
        local col, row = math.floor(cx / ts) + 1, math.floor(cy / ts) + 1
        world.map:setTile(col, row, world.map.groundFillId)
        table.insert(world.pluggedTiles, { col = col, row = row })
        world:removeEntity(self)
    end
end

function Crate:draw()
    local dx = math.floor(self.x)
    local dy = math.floor(self.y)

    love.graphics.setColor(Color.white())
    love.graphics.draw(Assets.spritesheet, Assets.quads.crate[1], dx, dy)

    -- hit flash: additive pass brightens the crate toward white
    if self.flash then
        love.graphics.setBlendMode('add')
        love.graphics.draw(Assets.spritesheet, Assets.quads.crate[1], dx, dy)
        love.graphics.setBlendMode('alpha')
    end
    self.flash = false
end

return Crate
