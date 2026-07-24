local Entity = require('entities.entity')
local Color = require('core.color')
local Path = require('core.path')
local Audio = require('core.audio')

local Enemy = {}
Enemy.__index = Enemy
setmetatable(Enemy, Entity)

function Enemy:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.health = 200
    obj.color = Color.red
    obj.speed = 20
    obj.type = 'enemy'
    obj.fillStyle = 'fill' -- enemies draw as full circles

    obj.damage = TUNE.zombies.contactDamage
    obj.attackCooldown = TUNE.zombies.contactCooldown
    obj.attackTimer = obj.attackCooldown

    -- A* state; random start staggers the horde's repath frames
    obj.path = nil
    obj.pathIndex = 1
    obj.repathTimer = love.math.random() * TUNE.zombies.repathTime
    obj.stuckTimer = 0

    -- knife shove, decays fast (separate from vx/vy so accel can't fight it)
    obj.kbx, obj.kby = 0, 0

    -- random growls; silent until zombie recordings exist in assets/sounds/zombies
    obj.growlTimer = TUNE.zombies.growlMin
        + love.math.random() * (TUNE.zombies.growlMax - TUNE.zombies.growlMin)

    setmetatable(obj, Enemy)
    return obj
end

-- Life grows linearly until lifeLinearUntil, compounds after, then type mult
local function waveLife(wave)
    local w = TUNE.waves
    local capped = math.min(wave, w.lifeLinearUntil)
    local life = w.lifeBase + w.lifePerWave * (capped - 1)
    if wave > w.lifeLinearUntil then
        life = life * w.lifeGrowth ^ (wave - w.lifeLinearUntil)
    end
    return life
end

-- All numbers come from tune.lua
local function newTyped(x, y, wave, t, color)
    local obj = Enemy:new(x, y, t.size, t.size)
    obj.speed = t.speed
    obj.health = waveLife(wave or 1) * t.lifeMult
    obj.color = color

    -- wall-collision box capped so big sprites (slow, 48px) still fit 1-tile
    -- gaps and can reach wall-adjacent waypoints; combat circle stays size/2
    local box = math.min(t.size - TUNE.movement.collisionInset * 2,
                         TUNE.zombies.colliderCap)
    obj.colW, obj.colH = box, box
    obj.colOX, obj.colOY = (t.size - box) / 2, (t.size - box) / 2
    return obj
end

function Enemy:newSlow(x, y, wave)
    return newTyped(x, y, wave, TUNE.zombies.slow, Color.red)
end

function Enemy:newFast(x, y, wave)
    return newTyped(x, y, wave, TUNE.zombies.fast, Color.magenta)
end

function Enemy:newRunner(x, y, wave)
    return newTyped(x, y, wave, TUNE.zombies.runner, Color.yellow)
end

-- Normalized direction toward a world point
local function dirTo(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    local length = math.sqrt(dx*dx + dy*dy)
    if length == 0 then return 0, 0, 0 end
    return dx / length, dy / length, length
end

function Enemy:followPlayer(dt, world)
    local ts = world.map.tileSize
    local cx, cy = self:getCenter()
    local pcx, pcy = world.player:getCenter()

    local myCol, myRow = math.floor(cx / ts) + 1, math.floor(cy / ts) + 1
    local pCol, pRow = math.floor(pcx / ts) + 1, math.floor(pcy / ts) + 1

    -- A*: recompute every repathTime; walls = solid tiles + closed doors
    self.repathTimer = self.repathTimer - dt
    if self.repathTimer <= 0 then
        self.repathTimer = TUNE.zombies.repathTime
        self.path = Path.find(world.map, world:blockedTiles(), myCol, myRow, pCol, pRow)
        self.pathIndex = 1
    end

    local nx, ny = 0, 0
    local nearPlayer = math.abs(myCol - pCol) <= 1 and math.abs(myRow - pRow) <= 1

    if nearPlayer or not self.path or self.pathIndex > #self.path then
        -- same/adjacent tile, or no route found: head straight at the player
        nx, ny = dirTo(cx, cy, pcx, pcy)
    else
        -- walk waypoint tile centers; a wall-pinned body can sit a few px off
        -- a wall-adjacent tile center, so the reach radius must absorb that
        local wp = self.path[self.pathIndex]
        local wx, wy = (wp.col - 0.5) * ts, (wp.row - 0.5) * ts
        local dist
        nx, ny, dist = dirTo(cx, cy, wx, wy)
        if dist < TUNE.zombies.waypointRadius then
            self.pathIndex = self.pathIndex + 1
        end
    end

    self.maxSpeed = self.speed
    self:accelToward(dt, nx, ny, world)

    -- knockback rides on top of normal velocity for the move, then comes off
    -- again so accel keeps working from the real speed
    local decay = math.exp(-TUNE.knife.knockbackDecay * dt)
    self.kbx, self.kby = self.kbx * decay, self.kby * decay
    self.vx, self.vy = self.vx + self.kbx, self.vy + self.kby
    self:moveAndCollide(dt, world)
    self.vx, self.vy = self.vx - self.kbx, self.vy - self.kby

    -- stuck watchdog: wants to move but the world isn't letting it (crate
    -- shoved onto a stale path, wall pin) -> stop waiting out repathTimer
    local mx, my = self.x - cx + self.width/2, self.y - cy + self.height/2
    if (nx ~= 0 or ny ~= 0)
        and mx*mx + my*my < (self.speed * dt * 0.25)^2 then
        self.stuckTimer = self.stuckTimer + dt
        if self.stuckTimer >= TUNE.zombies.stuckRepath then
            self.repathTimer = 0
            self.stuckTimer = 0
        end
    else
        self.stuckTimer = 0
    end
end

function Enemy:update(dt, world)
    self:followPlayer(dt, world)

    -- spikes hurt, water/mud slow, holes kill
    self:applyTileEffects(dt, world)

    -- Contact damage on the player (not while falling/invincible).
    -- Separation keeps the circles just apart, so plain overlap would never
    -- trigger: attackRange pads the reach a few px past touching.
    local px, py = world.player:getCenter()
    local cx, cy = self:getCenter()
    local ddx, ddy = px - cx, py - cy
    local reach = self.radius + world.player.radius + TUNE.zombies.attackRange

    self.attackTimer = self.attackTimer + dt
    if self.attackTimer >= self.attackCooldown and ddx*ddx + ddy*ddy < reach*reach
        and not world.player.falling and world.player.invulnTimer <= 0
        and not world.player.godMode then
        world.player.health = world.player.health - self.damage
        world.player.flashTimer = TUNE.player.hitFlashTime
        self.attackTimer = 0
        Audio.playAt('zombie_attack', cx, cy, 1, TUNE.audio.pitchJitter, world)
    end

    -- occasional growl (positional — you hear which side it comes from)
    self.growlTimer = self.growlTimer - dt
    if self.growlTimer <= 0 then
        self.growlTimer = TUNE.zombies.growlMin
            + love.math.random() * (TUNE.zombies.growlMax - TUNE.zombies.growlMin)
        Audio.playAt('zombie_growl', cx, cy, 1, TUNE.audio.pitchJitter, world)
    end

    if self.health < 1 then
        self.toRemove = true
        local dx, dy = self:getCenter()
        Audio.playAt('zombie_death', dx, dy, 1, TUNE.audio.pitchJitter, world)
    end
end

function Enemy:draw()
    Entity.draw(self)

    -- Shows the enemy health
    local hp = math.ceil(self.health)
    local fontWidth = smallFont:getWidth(hp)
    local fontHeight = smallFont:getHeight()

    love.graphics.setFont(smallFont)
    love.graphics.setColor(Color.red())
    love.graphics.print(hp, self.x + self.width/2 - fontWidth/2, self.y - fontHeight)
    love.graphics.setColor(Color.white())
    love.graphics.setFont(font)
end

return Enemy