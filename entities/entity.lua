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
        color = Color.blue,
        type = 'default',
        toRemove = false,
        flash = false
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
    love.graphics.circle('line', math.floor(cx), math.floor(cy), self.radius)
    love.graphics.setColor(Color.white())

    self.flash = false
end

-- Debug overlay (H key): collision circle on top of any sprite
function Entity:drawHitbox()
    love.graphics.setColor(0, 1, 0, 0.8)
    local cx, cy = self:getCenter()
    love.graphics.circle('line', cx, cy, self.radius)
    love.graphics.setColor(Color.white())
end

function Entity:drawHud()
    
end

return Entity