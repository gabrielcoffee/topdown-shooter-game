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

    obj.damage = TUNE.zombies.contactDamage
    obj.attackCooldown = TUNE.zombies.contactCooldown
    obj.attackTimer = obj.attackCooldown

    setmetatable(obj, Enemy)
    return obj
end

-- All numbers come from tune.lua. Life = baseLifePerWave * wave * type mult.
local function newTyped(x, y, wave, t, color)
    local obj = Enemy:new(x, y, t.size, t.size)
    obj.speed = t.speed
    obj.health = TUNE.zombies.baseLifePerWave * (wave or 1) * t.lifeMult
    obj.color = color
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