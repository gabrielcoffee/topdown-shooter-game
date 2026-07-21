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
        isThrowable = true,
        walkSpeed = TUNE.grenade.walkSpeed,
        damage = TUNE.grenade.damage,
        killReward = TUNE.grenade.killReward
    }

    setmetatable(obj, HandItem)
    return obj
end

function HandItem:newHealthPack()
    local obj = {
        name = 'MED KIT',
        x = 0, y = 0,
        ox = 8, oy = 8,
        angle = 0,
        static = true,
        isHealthPack = true,
        walkSpeed = TUNE.healthpack.walkSpeed,
    }

    setmetatable(obj, HandItem)
    return obj
end

-- No spritesheet quad for the med kit: primitive white box + red cross.
-- Shared by the in-hand draw and the hotbar icon.
function HandItem.drawMedkitIcon(x, y, size)
    local s = size
    love.graphics.setColor(0.92, 0.92, 0.92)
    love.graphics.rectangle('fill', x, y, s, s, 2, 2)
    love.graphics.setColor(0.8, 0.1, 0.1)
    love.graphics.rectangle('fill', x + s*0.4,  y + s*0.15, s*0.2, s*0.7)
    love.graphics.rectangle('fill', x + s*0.15, y + s*0.4,  s*0.7, s*0.2)
    love.graphics.setColor(1, 1, 1)
end

function HandItem:update(dt, px, py, mx, my)
    self.x = px + offsetX
    self.y = py + offsetY

    local dx, dy = mx-self.x, my-self.y
    self.angle = math.atan2(dy, dx)
end

function HandItem:draw(facingLeft)
    if self.isHealthPack then
        HandItem.drawMedkitIcon(math.floor(self.x) - 6, math.floor(self.y) - 6, 12)
        return
    end

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