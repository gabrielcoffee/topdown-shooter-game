local Color = require('core.color')

local Entity = {}
Entity.__index = Entity

function Entity:new(x, y, width, height)
    local obj = {
        x = x or 0,
        y = y or 0,
        width = width or 16,
        height = height or 16,
        radius = (width or 16) / 2,
        vx = 0,
        vy = 0,
        color = Color.blue,
        type = 'default',
        toRemove = false,
        flash = false,
        fillStyle = 'line' -- placeholder circle: 'line' (empty) or 'fill'
    }

    setmetatable(obj, Entity)
    return obj
end

-- to check if an entity has a parent class (metatable index)
function Entity:isClass(class)
    local mt = getmetatable(self)
    while mt do
        if mt == class then
            return true
        end
        mt = getmetatable(mt)
    end
    return false
end

function Entity:update(dt, world)

end

-- Accelerate velocity toward dir * maxSpeed. Water lowers max speed,
-- mud cuts acceleration AND deceleration.
function Entity:accelToward(dt, dirX, dirY, world)
    local tile = world.map:typeAt(self:getCenter())
    local maxSpeed = self.maxSpeed or 0
    if tile == 'water' then maxSpeed = maxSpeed * TUNE.tiles.waterSpeedMult end
    local mult = (tile == 'mud') and TUNE.tiles.mudAccelMult or 1

    local function approach(v, target)
        local time = (target ~= 0) and TUNE.movement.accelTime or TUNE.movement.decelTime
        local rate = maxSpeed / time * mult
        if v < target then return math.min(v + rate * dt, target) end
        return math.max(v - rate * dt, target)
    end

    self.vx = approach(self.vx, dirX * maxSpeed)
    self.vy = approach(self.vy, dirY * maxSpeed)
end

-- Collision AABB is the sprite box inset a few px so 32px bodies fit 32px gaps
local function collisionBox(self)
    local inset = TUNE.movement.collisionInset
    return self.x + inset, self.y + inset,
           self.width - inset * 2, self.height - inset * 2
end

-- Snap out of solid tiles and obstacle entities along one axis
local function resolveAxis(self, world, axis)
    local inset = TUNE.movement.collisionInset
    local ts = world.map.tileSize
    local bx, by, bw, bh = collisionBox(self)

    -- solid tiles (loop cols/rows the box overlaps, 0-based)
    local c0, c1 = math.floor(bx / ts), math.floor((bx + bw - 0.001) / ts)
    local r0, r1 = math.floor(by / ts), math.floor((by + bh - 0.001) / ts)
    for row = r0, r1 do
        for col = c0, c1 do
            if world.map:isSolidAt(col * ts, row * ts) then
                if axis == 'x' then
                    if self.vx > 0 then self.x = col * ts - bw - inset
                    elseif self.vx < 0 then self.x = (col + 1) * ts - inset end
                    self.vx = 0
                else
                    if self.vy > 0 then self.y = row * ts - bh - inset
                    elseif self.vy < 0 then self.y = (row + 1) * ts - inset end
                    self.vy = 0
                end
                bx, by = collisionBox(self)
            end
        end
    end

    -- obstacle entities (crates, doors)
    for _, e in ipairs(world.entities) do
        if e.isObstacle and e ~= self and not e.toRemove
            and bx < e.x + e.width and bx + bw > e.x
            and by < e.y + e.height and by + bh > e.y then

            local sign = (axis == 'x') and (self.vx > 0 and 1 or -1)
                                        or (self.vy > 0 and 1 or -1)

            -- pushing player notifies crates; sliding crates don't kill his speed
            local keepSpeed = false
            if e.notifyPush then
                if self.isPlayer then
                    e:notifyPush(axis, sign, self.maxSpeed)
                end
                keepSpeed = e.activeDir ~= nil
                    and ((axis == 'x' and e.activeDir.x == sign)
                      or (axis == 'y' and e.activeDir.y == sign))
            end

            if axis == 'x' then
                if self.vx > 0 then self.x = e.x - bw - inset
                elseif self.vx < 0 then self.x = e.x + e.width - inset end
                if not keepSpeed then self.vx = 0 end
            else
                if self.vy > 0 then self.y = e.y - bh - inset
                elseif self.vy < 0 then self.y = e.y + e.height - inset end
                if not keepSpeed then self.vy = 0 end
            end
            bx, by = collisionBox(self)
        end
    end
end

-- Axis-separated movement: walls block, box slides along them
function Entity:moveAndCollide(dt, world)
    self.x = self.x + self.vx * dt
    resolveAxis(self, world, 'x')

    self.y = self.y + self.vy * dt
    resolveAxis(self, world, 'y')

    -- safety net: never leave the map
    self.x = math.max(0, math.min(self.x, world.mapW - self.width))
    self.y = math.max(0, math.min(self.y, world.mapH - self.height))
end

-- Per-tile effects, keyed off the entity center
function Entity:applyTileEffects(dt, world)
    local tile = world.map:typeAt(self:getCenter())

    if tile == 'spikes' then
        self.health = self.health - TUNE.tiles.spikeDps * dt
    elseif tile == 'ground' then
        self.lastGroundX, self.lastGroundY = self.x, self.y
    elseif tile == 'hole' then
        self:onFellInHole(world)
    end
end

-- Default: falling in a hole kills (zombies). Player overrides.
function Entity:onFellInHole(world)
    self.toRemove = true
end

function Entity:getCenter()
    return self.x + self.width/2, self.y + self.height/2
end

-- Circle hitbox: colliding when center distance < sum of radii
function Entity:collidesWith(e1)
    local ax, ay = self:getCenter()
    local bx, by = e1:getCenter()
    local dx, dy = ax - bx, ay - by
    local r = self.radius + e1.radius
    return dx*dx + dy*dy < r*r
end

-- AABB kept for future rectangular colliders (walls etc.)
function Entity:collidesWithBox(e1)
    return e1.x + e1.width > self.x and e1.y + e1.height > self.y
        and e1.x < self.x + self.width and e1.y < self.y + self.height
end

function Entity:draw()
    love.graphics.setColor(self.color())

    if self.flash then
        love.graphics.setColor(Color.white())
    end

    local cx, cy = self:getCenter()
    love.graphics.circle(self.fillStyle, math.floor(cx), math.floor(cy), self.radius)
    love.graphics.setColor(Color.white())

    self.flash = false
end

-- Debug overlay (H key): collision circle on top of any sprite
function Entity:drawHitbox()
    local c = self.hitboxColor or {0, 1, 0}
    love.graphics.setLineWidth(1)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    local cx, cy = self:getCenter()
    love.graphics.circle('line', cx, cy, self.radius)
    love.graphics.setColor(Color.white())
end

function Entity:drawHud()
    
end

return Entity