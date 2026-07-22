-- A gun lying on the ground. Holds a live Gun instance (ammo state travels
-- with it), picked up with E; pickup with full slots swaps guns in place.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Gun = require('hand_items.gun')

local DroppedGun = {}
DroppedGun.__index = DroppedGun
setmetatable(DroppedGun, Entity)

function DroppedGun:new(x, y, gun)
    local obj = Entity:new(x, y, TUNE.tiles.size, TUNE.tiles.size)
    obj.type = 'dropped_gun'
    obj.gun = gun
    obj.bobTimer = 0
    setmetatable(obj, DroppedGun)
    return obj
end

function DroppedGun:update(dt, world)
    self.bobTimer = self.bobTimer + dt
end

function DroppedGun:draw()
    local quad = Assets.quads[Gun.quadName(self.gun.id)][1]
    local _, _, qw, qh = quad:getViewport()
    local cx, cy = self:getCenter()
    local bob = math.sin(self.bobTimer * 4) * 2

    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse('fill', math.floor(cx), math.floor(cy + qh/2 + 2), qw/2, 3)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(Assets.spritesheet, quad,
        math.floor(cx), math.floor(cy + bob), 0, 1, 1, qw/2, qh/2)
end

return DroppedGun
