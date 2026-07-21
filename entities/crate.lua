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
    obj.maxSpeed = 0
    obj.pushTimer = 0
    setmetatable(obj, Crate)
    return obj
end

-- Called by the player's collision resolution while pushing against us
function Crate:notifyPush(axis, sign, speed)
    local dir = {
        x = axis == 'x' and sign or 0,
        y = axis == 'y' and sign or 0,
    }

    -- push direction changed: start the 0.5s over
    if not self.lastDir or self.lastDir.x ~= dir.x or self.lastDir.y ~= dir.y then
        self.pushTimer = 0
    end

    self.lastDir = dir
    self.pushDir = dir
    self.maxSpeed = speed * TUNE.crate.pushSpeedMult
end

function Crate:update(dt, world)
    local dirX, dirY = 0, 0

    if self.pushDir then
        self.pushTimer = self.pushTimer + dt
        if self.pushTimer >= TUNE.crate.pushDelay then
            dirX, dirY = self.pushDir.x, self.pushDir.y
        end
    else
        -- no push this frame: continuity broken
        self.pushTimer = 0
        self.lastDir = nil
    end

    -- sliding this frame? pushers keep their speed against this face
    self.activeDir = (dirX ~= 0 or dirY ~= 0) and { x = dirX, y = dirY } or nil

    self:accelToward(dt, dirX, dirY, world)
    self:moveAndCollide(dt, world)

    -- pushed over a hole: falls in and plugs it (tile becomes ground)
    local cx, cy = self:getCenter()
    if world.map:typeAt(cx, cy) == 'hole' then
        local ts = world.map.tileSize
        world.map:setTile(math.floor(cx / ts) + 1, math.floor(cy / ts) + 1,
                          world.map.groundFillId)
        world:removeEntity(self)
    end

    -- must be re-notified every frame the push holds
    self.pushDir = nil
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
