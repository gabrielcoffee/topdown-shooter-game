-- A spent shell casing kicked out of a gun. Purely decorative: it hops out
-- sideways, spins, falls under faked gravity (a height `z` drawn as a y-offset),
-- bounces once or twice, settles near the player, then blinks out and vanishes.
-- One class covers every gun's casing -- the caller passes the sprite quad.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Audio = require('core.audio')

local ShellCasing = {}
ShellCasing.__index = ShellCasing
setmetatable(ShellCasing, Entity)

-- x,y = ground spawn (the gun pivot, already near the player); angle = aim dir,
-- casing ejects perpendicular to it; quad = one of Assets.quads.shell_*.
-- dirX = screen-horizontal eject direction (-1 = left, +1 = right); the gun
-- passes "backwards" relative to which way the player faces (not the aim angle).
function ShellCasing:new(x, y, dirX, quad, dropSfx)
    local obj = Entity:new(x, y, 8, 8)
    obj.type = 'shell_casing'
    obj.dropSfx = dropSfx -- list of casing-hit sounds; one picked at random on landing

    local S = TUNE.shell
    -- fly backwards (screen left/right) off the player, tilted a random
    -- dirSpread around that direction, and hop high in z (the visible "up")
    local speed = S.ejectSpeed + love.math.random() * S.ejectSpeedJitter
    local tilt = (love.math.random() * 2 - 1) * S.dirSpread
    obj.vx = dirX * speed * math.cos(tilt)
    obj.vy = speed * math.sin(tilt)
    obj.z = 0
    obj.vz = S.ejectUp + love.math.random() * S.ejectUpJitter

    obj.angle = love.math.random() * math.pi * 2
    obj.spin = (S.spinMin + love.math.random() * (S.spinMax - S.spinMin))
             * (love.math.random() < 0.5 and -1 or 1)

    obj.age = 0
    obj.settled = false
    obj.landed = false
    obj.sprite = quad

    setmetatable(obj, ShellCasing)
    return obj
end

function ShellCasing:update(dt, world)
    local S = TUNE.shell
    self.age = self.age + dt
    if self.age >= S.lifetime then
        self.toRemove = true
        return
    end

    if self.settled then return end

    -- vertical hop under gravity
    self.vz = self.vz - S.gravity * dt
    self.z = self.z + self.vz * dt

    -- ground drift + spin, both decaying by friction
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    local decay = math.max(0, 1 - S.friction * dt)
    self.vx = self.vx * decay
    self.vy = self.vy * decay
    self.angle = self.angle + self.spin * dt
    self.spin = self.spin * decay

    -- hit the floor: bounce, lose energy, clack once on first contact
    if self.z <= 0 and self.vz < 0 then
        self.z = 0
        if not self.landed then
            self.landed = true
            if self.dropSfx then
                Audio.playAt(self.dropSfx[love.math.random(#self.dropSfx)],
                    self.x, self.y, 0.5, TUNE.audio.pitchJitter, world)
            end
        end
        self.vz = -self.vz * S.bounce
        self.vx = self.vx * 0.6
        self.vy = self.vy * 0.6
        self.spin = self.spin * 0.5

        local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
        if self.vz < 25 and speed < S.settleSpeed then
            self.settled = true
            self.vz, self.vx, self.vy, self.spin = 0, 0, 0, 0
        end
    end
end

function ShellCasing:draw()
    local S = TUNE.shell
    -- blink out over the final blinkTime, reusing the player invuln pattern
    local remaining = S.lifetime - self.age
    if remaining < S.blinkTime
        and math.floor(remaining / S.blinkInterval) % 2 == 0 then
        return
    end

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y - self.z),
        self.angle, S.scale, S.scale, 4, 4
    )
end

return ShellCasing
