local Entity = require('entities.entity')
local Color = require('core.color')

local Door = {}
Door.__index = Door
setmetatable(Door, Entity)

-- w/h come from the LDtk instance (the entity is resizable in the editor),
-- so one door can stretch across the 2-tile wall between rooms and read as
-- a door from both sides. Defaults to one tile.
function Door:new(x, y, price, id, w, h)
    local obj = Entity:new(x, y, w or TUNE.tiles.size, h or TUNE.tiles.size)
    obj.type = 'door'
    obj.isObstacle = true
    obj.price = price or TUNE.door.price
    obj.id = id -- spawn points can gate on this door being opened
    setmetatable(obj, Door)
    return obj
end

function Door:draw()
    love.graphics.setColor(0.75, 0.6, 0.15)
    love.graphics.rectangle('fill', math.floor(self.x), math.floor(self.y), self.width, self.height)
    love.graphics.setColor(0.4, 0.32, 0.05)
    love.graphics.rectangle('line', math.floor(self.x), math.floor(self.y), self.width, self.height)

    -- price above the door
    local txt = '$'..self.price
    love.graphics.setFont(smallFont)
    love.graphics.setColor(Color.black())
    love.graphics.print(txt, self.x + self.width/2 - smallFont:getWidth(txt)/2, self.y - smallFont:getHeight())
    love.graphics.setFont(font)
    love.graphics.setColor(Color.white())
end

return Door
