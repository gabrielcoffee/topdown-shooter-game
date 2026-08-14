local Color = require('core.color')

local Entity = {}
Entity.__index = Entity

-- monotonic serial, used only as a stable tiebreaker for the y-sort draw order
-- so entities sharing a sortY don't flicker back and forth between frames
local nextSerial = 0

-- Network identity, separate from sortSerial: the host stamps it, snapshots
-- address entities by it, and clients overwrite theirs from the packet. Wraps
-- inside uint16 because that is how it goes on the wire.
local nextNetId = 0
local function newNetId()
    nextNetId = (nextNetId % 65535) + 1
    return nextNetId
end

function Entity:new(x, y, width, height)
    nextSerial = nextSerial + 1
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
        netId = newNetId(),
        sortSerial = nextSerial,
        fillStyle = 'line' -- placeholder circle: 'line' (empty) or 'fill'
    }

    setmetatable(obj, Entity)
    return obj
end

-- Depth anchor for the world's y-sorted draw pass: entities with a smaller
-- sortY draw first (behind). Default is the sprite's bottom edge (the "feet"),
-- so something lower on screen renders in front. Props that should be walked
-- behind past a certain line (crates) override this with that line's Y.
function Entity:sortY()
    return self.y + self.height
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
function Entity:accelToward(dt, dirX, dirY, world, airborne)
    local tile = world.map:typeAt(self:getCenter())
    local maxSpeed = self.maxSpeed or 0
    if tile == 'water' and not airborne then
        maxSpeed = maxSpeed * TUNE.tiles.waterSpeedMult
    end
    local mult = (tile == 'mud' and not airborne) and TUNE.tiles.mudAccelMult or 1

    local function approach(v, target)
        local time = (target ~= 0) and TUNE.movement.accelTime or TUNE.movement.decelTime
        local rate = maxSpeed / time * mult
        if v < target then return math.min(v + rate * dt, target) end
        return math.max(v - rate * dt, target)
    end

    self.vx = approach(self.vx, dirX * maxSpeed)
    self.vy = approach(self.vy, dirY * maxSpeed)
end

-- Collision AABB. Default: the sprite box inset a few px so 32px bodies fit
-- 32px gaps. An entity can override with an explicit box (colOX/colOY/colW/colH,
-- offsets from its sprite top-left) when its collider isn't the whole sprite.
local function collisionBox(self)
    if self.colW then
        return self.x + self.colOX, self.y + self.colOY, self.colW, self.colH
    end
    local inset = TUNE.movement.collisionInset
    return self.x + inset, self.y + inset,
           self.width - inset * 2, self.height - inset * 2
end

-- Snap out of solid tiles and obstacle entities along one axis
function Entity:_resolveAxis(world, axis, dt)
    local ts = world.map.tileSize
    local bx, by, bw, bh = collisionBox(self)
    -- how far the collision box sits inside the sprite box; snap-outs below add
    -- it back so the sprite origin lands right. For a custom box (player's 16x16)
    -- this is colOX/colOY, not the default inset — using inset drifts the snap.
    local offX, offY = bx - self.x, by - self.y

    -- Eject direction out of a blocker spanning [lo,hi]: out the NEAREST face,
    -- velocity sign only as tie-break. Velocity alone is wrong for a body left
    -- overlapping by a multi-obstacle wedge (two crates against a wall): it
    -- either skipped the snap entirely (v == 0, overlap persisted) or snapped
    -- out the FAR face — the teleport-through-doors bug.
    local function ejectDir(lo, hi, p0, p1, v)
        local penLo = p1 - lo   -- depth past the low face (eject = -1)
        local penHi = hi - p0   -- depth past the high face (eject = +1)
        if penLo < penHi then return -1
        elseif penHi < penLo then return 1
        else return (v < 0) and 1 or -1 end
    end

    -- solid tiles (loop cols/rows the box overlaps, 0-based)
    local c0, c1 = math.floor(bx / ts), math.floor((bx + bw - 0.001) / ts)
    local r0, r1 = math.floor(by / ts), math.floor((by + bh - 0.001) / ts)
    for row = r0, r1 do
        for col = c0, c1 do
            if world.map:isSolidAt(col * ts, row * ts) then
                if axis == 'x' then
                    if ejectDir(col * ts, (col + 1) * ts, bx, bx + bw, self.vx) < 0 then
                        self.x = col * ts - bw - offX
                    else
                        self.x = (col + 1) * ts - offX
                    end
                    self.vx = 0
                else
                    if ejectDir(row * ts, (row + 1) * ts, by, by + bh, self.vy) < 0 then
                        self.y = row * ts - bh - offY
                    else
                        self.y = (row + 1) * ts - offY
                    end
                    self.vy = 0
                end
                bx, by = collisionBox(self)
            end
        end
    end

    -- obstacle entities (crates, doors)
    for _, e in ipairs(world.entities) do
        -- expand the face we move toward by 0.5px so flush contact
        -- (player riding a pushed crate) still counts as touching
        local ex0, ex1 = e.x, e.x + e.width
        local ey0, ey1 = e.y, e.y + e.height
        if axis == 'x' then
            if self.vx > 0 then ex0 = ex0 - 0.5 elseif self.vx < 0 then ex1 = ex1 + 0.5 end
        else
            if self.vy > 0 then ey0 = ey0 - 0.5 elseif self.vy < 0 then ey1 = ey1 + 0.5 end
        end

        if e.isObstacle and e ~= self and not e.toRemove
            and bx < ex1 and bx + bw > ex0
            and by < ey1 and by + bh > ey0 then

            -- Corner shave: sliver contact on the PERPENDICULAR axis (catching
            -- a crate/door corner by a few px) neither blocks nor pushes — the
            -- mover eases sideways off the corner instead, a couple px per
            -- frame. Kills the crate-seam bug: a 2px clip on the crate above
            -- the one being pushed used to steal the push, restart its ramp
            -- and shove the player off line.
            local ov, shaveDir
            if axis == 'x' then
                ov = math.min(by + bh, e.y + e.height) - math.max(by, e.y)
                shaveDir = (by + bh/2 < e.y + e.height/2) and -1 or 1
            else
                ov = math.min(bx + bw, e.x + e.width) - math.max(bx, e.x)
                shaveDir = (bx + bw/2 < e.x + e.width/2) and -1 or 1
            end
            if ov <= TUNE.movement.cornerTolerance then
                local step = shaveDir * math.min(ov, 2)
                local sx, sy = bx, by
                if axis == 'x' then sy = by + step else sx = bx + step end
                -- shaved box must not enter a wall; blocked = no shave, and the
                -- sliver simply doesn't collide this frame (max 6px, invisible
                -- under the sprite inset)
                if not (world.map:isSolidAt(sx, sy)
                    or world.map:isSolidAt(sx + bw - 0.001, sy)
                    or world.map:isSolidAt(sx, sy + bh - 0.001)
                    or world.map:isSolidAt(sx + bw - 0.001, sy + bh - 0.001)) then
                    if axis == 'x' then self.y = self.y + step
                    else self.x = self.x + step end
                    bx, by = collisionBox(self)
                end
            else

            local eject
            if axis == 'x' then
                eject = ejectDir(e.x, e.x + e.width, bx, bx + bw, self.vx)
            else
                eject = ejectDir(e.y, e.y + e.height, by, by + bh, self.vy)
            end
            local sign = -eject -- the crate gives way AWAY from the mover

            -- player pushes crates positionally: the crate moves right now
            -- (speed-capped, clipped by its own collisions), then we clamp
            -- against its new face. keepSpeed while it gives way, so the
            -- player's accel isn't reset every frame of the push.
            -- A pushed crate can itself push the next crate while it still
            -- has chain budget (rows up to crate.maxChain move as one).
            local keepSpeed = false
            if e.pushBy and (self.isPlayer or (self.pushBudget or 0) > 0) then
                local pen
                if axis == 'x' then
                    pen = (sign > 0) and (bx + bw - e.x) or (e.x + e.width - bx)
                else
                    pen = (sign > 0) and (by + bh - e.y) or (e.y + e.height - by)
                end
                keepSpeed = e:pushBy(axis, sign, math.max(0, pen), dt, world, self.maxSpeed, self)
            end

            if axis == 'x' then
                if eject < 0 then self.x = e.x - bw - offX
                else self.x = e.x + e.width - offX end
                if not keepSpeed then self.vx = 0 end
            else
                if eject < 0 then self.y = e.y - bh - offY
                else self.y = e.y + e.height - offY end
                if not keepSpeed then self.vy = 0 end
            end
            bx, by = collisionBox(self)
            end
        end
    end
end

-- Positional correction (separation pushes, knockbacks): move by (dx,dy) but
-- clip against solids/obstacles exactly like normal movement, so no push can
-- ever leave this entity inside a wall. If a wall blocks the correction the
-- entity simply absorbs less of it. Gameplay velocity is preserved — the
-- vx/vy writes are only direction hints for _resolveAxis' face snapping.
function Entity:nudge(world, dx, dy)
    local svx, svy = self.vx, self.vy
    if dx ~= 0 then
        self.x = self.x + dx
        self.vx = dx
        self:_resolveAxis(world, 'x', 0)
    end
    if dy ~= 0 then
        self.y = self.y + dy
        self.vy = dy
        self:_resolveAxis(world, 'y', 0)
    end
    self.vx, self.vy = svx, svy
    self.x = math.max(0, math.min(self.x, world.mapW - self.width))
    self.y = math.max(0, math.min(self.y, world.mapH - self.height))
end

-- Axis-separated movement: walls block, box slides along them
function Entity:moveAndCollide(dt, world)
    self.x = self.x + self.vx * dt
    self:_resolveAxis(world, 'x', dt)

    self.y = self.y + self.vy * dt
    self:_resolveAxis(world, 'y', dt)

    -- safety net: never leave the map
    self.x = math.max(0, math.min(self.x, world.mapW - self.width))
    self.y = math.max(0, math.min(self.y, world.mapH - self.height))
end

-- Per-tile effects, keyed off the entity center
function Entity:applyTileEffects(dt, world)
    local tile = world.map:typeAt(self:getCenter())

    if tile == 'spikes' then
        if not (self.invulnTimer and self.invulnTimer > 0) and not self.godMode then
            self.health = self.health - TUNE.tiles.spikeDps * dt
        end
    elseif tile == 'ground' or tile == 'torch' then
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

-- Debug overlay (H key): draws the colliders actually used.
-- Obstacles (crates, doors, wall buys, chests) collide as their full AABB —
-- movement, bullets and A* all use the box, never a circle.
-- Everything else: the combat circle (bullets/knife/shoving), plus the
-- wall-collision box when the entity has a custom one (yellow).
function Entity:drawHitbox()
    local c = self.hitboxColor or {0, 1, 0}
    love.graphics.setLineWidth(1)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    if self.isObstacle then
        love.graphics.rectangle('line', self.x, self.y, self.width, self.height)
    else
        local cx, cy = self:getCenter()
        love.graphics.circle('line', cx, cy, self.radius)
        if self.colW then
            love.graphics.setColor(1, 1, 0, 0.8)
            love.graphics.rectangle('line',
                self.x + self.colOX, self.y + self.colOY, self.colW, self.colH)
        end
    end
    love.graphics.setColor(Color.white())
end

function Entity:drawHud()
    
end

return Entity