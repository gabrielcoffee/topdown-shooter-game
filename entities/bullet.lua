local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Animation = require('core.animation')

local Bullet = {}
Bullet.__index = Bullet
setmetatable(Bullet, Entity)


function Bullet:new(x, y, angle, damage, muzzleOffset, lifetime)
    local obj = Entity:new(x, y, 2, 4)

    obj.color = Color.white
    obj.speed = TUNE.bullet.speed
    obj.angle = angle
    obj.sprite = Assets.quads.bullet[1]
    obj.damage = damage
    obj.lifetime = lifetime
    obj.timer = 0
    obj.ox = 0
    obj.oy = 1
    obj.dx = math.cos(angle)
    obj.dy = math.sin(angle)

    obj.x = obj.x + (obj.dx * muzzleOffset)
    obj.y = obj.y + (obj.dy * muzzleOffset)

    obj.animMuzzle = Animation:new(Assets.quads.muzzle, 1, 3, 0.017)
    
    setmetatable(obj, Bullet)
    return obj
end

function Bullet:update(dt, world)
 
    if self.timer ~= 0 then
        self.x = self.x + ((self.dx * self.speed) * dt)
        self.y = self.y + ((self.dy * self.speed) * dt)
    end

    self.timer = self.timer + dt

    if self.timer >= self.lifetime then
        world:removeEntity(self)
    end

    self.animMuzzle:update(dt)

    local enemyCollided =  world:getEntityCollision(self, 'enemy')
    if enemyCollided ~= nil then
        world:removeEntity(self)
        enemyCollided.health = enemyCollided.health - self.damage
        enemyCollided.flash = true
    end
end

function Bullet:draw()
    love.graphics.setColor(Color.white())

    if self.timer < 0.07 then

        self.animMuzzle:draw(
            self.x, self.y,
            self.angle,
            1, 1,
            self.ox, self.oy+5
        )
    end

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y),
        self.angle,
        1, 1,
        self.ox, self.oy
    )

    love.graphics.setColor(Color.white())
end

return Bullet