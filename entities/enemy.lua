local Entity = require('entities.entity')
local Color = require('core.color')

local Enemy = {}
Enemy.__index = Enemy
setmetatable(Enemy, Entity)

function Enemy:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.health = 200
    obj.color = Color.red
    obj.speed = 20
    obj.type = 'enemy'

    obj.damage = 10 -- TUNE
    obj.attackCooldown = 1.0 -- TUNE: secs between contact hits
    obj.attackTimer = obj.attackCooldown

    setmetatable(obj, Enemy)
    return obj
end

-- TUNE: all stats below (speed / life multiplier / damage / size)
-- Life: base = 20 * wave, then slow x2 / fast x1 / runner x0.5
local function baseLife(wave)
    return 20 * (wave or 1) -- TUNE: +20 per wave
end

function Enemy:newSlow(x, y, wave)
    local obj = Enemy:new(x, y, 48, 48) -- 1.5x base size
    obj.speed = 30
    obj.health = baseLife(wave) * 2
    obj.damage = 10
    obj.color = Color.red
    return obj
end

function Enemy:newFast(x, y, wave)
    local obj = Enemy:new(x, y, 32, 32) -- base size
    obj.speed = 60
    obj.health = baseLife(wave)
    obj.damage = 10
    obj.color = Color.magenta
    return obj
end

function Enemy:newRunner(x, y, wave)
    local obj = Enemy:new(x, y, 21, 21) -- 1.5x smaller
    obj.speed = 90
    obj.health = baseLife(wave) * 0.5
    obj.damage = 15
    obj.color = Color.yellow
    return obj
end

function Enemy:followPlayer(dt, world)
    local ex, ey = self.x, self.y
    local px, py = world.player.x, world.player.y

    local dx, dy = px - ex, py - ey         -- calcula comprimento dos outros lados
    local length = math.sqrt(dx*dx + dy*dy) -- calcula comprimento hipotenusa // distancia entre player e inimigo
    local nx, ny = dx / length, dy / length -- normalização da distancia no x e y

    self.x = self.x + (nx * self.speed * dt)
    self.y = self.y + (ny * self.speed * dt)
end

function Enemy:update(dt, world)
    self:followPlayer(dt, world)

    -- Contact damage on the player
    self.attackTimer = self.attackTimer + dt
    if self.attackTimer >= self.attackCooldown and self:collidesWith(world.player) then
        world.player.health = world.player.health - self.damage
        self.attackTimer = 0
    end

    if self.health < 1 then
        self.toRemove = true
    end
end

function Enemy:draw()
    Entity.draw(self)

    -- Shows the enemy health
    local fontWidth = smallFont:getWidth(self.health)
    local fontHeight = smallFont:getHeight()

    love.graphics.setFont(smallFont)
    love.graphics.setColor(Color.red())
    love.graphics.print(self.health, self.x + self.width/2 - fontWidth/2, self.y - fontHeight)
    love.graphics.setColor(Color.white())
    love.graphics.setFont(font)
end

return Enemy