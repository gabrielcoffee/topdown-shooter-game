local Assets = require('core.assets')

local HandItem = {}
HandItem.__index = HandItem

local offsetX = 16
local offsetY = 16

function HandItem:newKnife()
    local obj = {
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.knife[1],
        static = true
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:newGrenade(type)
    local obj = {
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.grenade[1],
        static = true,
        type = type or 'he',
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:update(dt, px, py, mx, my)
    self.x = px + offsetX
    self.y = py + offsetY

    local dx, dy = mx-self.x, my-self.y
    self.angle = math.atan2(dy, dx)
end

function HandItem:draw(facingLeft)
    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y),
        self.angle, 1, facingLeft and -1 or 1, self.ox, self.oy
    )
end

return HandItem