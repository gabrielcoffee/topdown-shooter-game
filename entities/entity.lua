local Color = require('core.color')

local Entity = {}
Entity.__index = Entity

function Entity:new(x, y, width, height)
    local obj = {
        x = x or 0,
        y = y or 0,
        width = width or 16,
        height = height or 16,
        color = Color.blue,
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

function Entity:collidesWith(e1)

end

function Entity:draw()
    love.graphics.setColor(self.color())
    love.graphics.rectangle('fill', math.floor(self.x), math.floor(self.y), self.width, self.height)
    love.graphics.setColor(Color.white())
end

return Entity