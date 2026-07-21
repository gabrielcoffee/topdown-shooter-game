local Assets = require('core.assets')

local HandItem = {}
HandItem.__index = HandItem

local offsetX = 16
local offsetY = 16

function HandItem:newKnife()
    local obj = {
        name = 'M9 Bayonet',
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.knife[1],
        static = true,
        walkSpeed = TUNE.knife.walkSpeed,
        damage = TUNE.knife.damage, -- used when melee lands (step 8)
        killReward = TUNE.knife.killReward
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:newGrenade(type)
    local obj = {
        name = 'M67 Frag',
        x = 0, y = 0,
        ox = 4, oy = 15,
        angle = 0,
        sprite = Assets.quads.grenade[1],
        static = true,
        type = type or 'he',
        walkSpeed = TUNE.grenade.walkSpeed,
        damage = TUNE.grenade.damage, -- full damage anywhere inside blast radius (step 9)
        killReward = TUNE.grenade.killReward
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

function HandItem:drawHud()
    love.graphics.print(self.name, 20, 20)
end

return HandItem