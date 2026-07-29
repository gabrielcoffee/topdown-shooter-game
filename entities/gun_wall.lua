-- CoD-style wall buy: a solid wall tile with the gun ghosted on it. E buys
-- the gun; if the player already carries it, E buys an ammo refill instead
-- (price * wallbuy.ammoFactor). Placed in LDtk as a GunWall entity with a
-- `gun` field (usp|ak47|m4a1|shotgun) and an optional `price` override.

local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')
local Gun = require('hand_items.gun')
local DroppedGun = require('entities.dropped_gun')
local Audio = require('core.audio')

local GunWall = {}
GunWall.__index = GunWall
setmetatable(GunWall, Entity)

function GunWall:new(x, y, gunId, price)
    local obj = Entity:new(x, y, TUNE.tiles.size, TUNE.tiles.size)
    obj.type = 'gunwall'
    obj.isObstacle = true -- blocks bullets, bodies, A* and zombie LOS
    obj.gunId = gunId
    obj.price = price or TUNE.wallbuy.prices[gunId] or 500
    obj.ammoPrice = math.ceil(obj.price * TUNE.wallbuy.ammoFactor)
    setmetatable(obj, GunWall)
    return obj
end

-- The matching gun the player already carries (slots 1-2), if any
function GunWall:ownedGun(player)
    for i = 1, 2 do
        local g = player.items[i]
        if g and g.id == self.gunId then return g end
    end
end

function GunWall:interact(player, world)
    local owned = self:ownedGun(player)
    if owned then
        if owned:ammoFull() then return end -- never charge for nothing
        if player:trySpend(self.ammoPrice) then
            owned:refill()
            Audio.play('gun_draw', 0.7)
        end
    elseif player:trySpend(self.price) then
        -- bought guns are paid for: a replaced gun drops instead of vanishing
        local old = player:giveGun(Gun.newById(self.gunId))
        if old then DroppedGun.dropNear(world, old, player) end
    end
end

function GunWall:draw()
    local x, y = math.floor(self.x), math.floor(self.y)

    local art = Assets.wallArt[self.gunId]
    if art then
        -- Gabriel's neon sign art: wider than the tile, centered on it
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(art, x + (self.width - art:getWidth()) / 2, y)
    else
        -- no sign art (usp): dark plate + ghosted spritesheet gun
        love.graphics.setColor(0.16, 0.16, 0.2)
        love.graphics.rectangle('fill', x, y, self.width, self.height)
        love.graphics.setColor(0.05, 0.05, 0.08)
        love.graphics.rectangle('line', x, y, self.width, self.height)

        local quad = Assets.quads[Gun.quadName(self.gunId)][1]
        local _, _, qw, qh = quad:getViewport()
        local s = math.min((self.width - 4) / qw, (self.height - 4) / qh)
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.draw(Assets.spritesheet, quad,
            x + self.width / 2, y + self.height / 2, 0, s, s, qw / 2, qh / 2)
    end

    local txt = '$' .. self.price
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 0.85, 0.35)
    love.graphics.print(txt, x + self.width / 2 - smallFont:getWidth(txt) / 2,
        y - smallFont:getHeight())
    love.graphics.setFont(font)
    love.graphics.setColor(Color.white())
end

return GunWall
