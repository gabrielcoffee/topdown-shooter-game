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

    setmetatable(obj, Enemy)
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

    if self.health < 1 then
        self.toRemove = true
    end
end

function Enemy:draw()
    Entity.draw(self)

    -- Shows the enemy health
    local fontWidth = font:getWidth(self.health)
    local fontHeight = font:getHeight()

    love.graphics.setColor(Color.red())
    love.graphics.print(self.health, self.x + self.width/2 - fontWidth/2, self.y - fontHeight)
    love.graphics.setColor(Color.white())
end

return Enemy