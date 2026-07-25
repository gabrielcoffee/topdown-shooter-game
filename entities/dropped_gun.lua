-- A gun lying on the ground. Holds a live Gun instance (ammo state travels
-- with it), picked up with E; pickup with full slots swaps guns in place.
-- Ground guns are temporary: they blink near the end of their life and
-- vanish (TUNE.droppedGun.lifetime), so the map can't be littered.

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
    obj.life = TUNE.droppedGun.lifetime
    setmetatable(obj, DroppedGun)
    return obj
end

-- Drop `gun` on the ground just in front of `ent`, clamped inside the map.
function DroppedGun.dropNear(world, gun, ent)
    local size = TUNE.tiles.size
    local cx, cy = ent:getCenter()
    local off = TUNE.droppedGun.dropOffset * (ent.facingLeft and -1 or 1)
    local x = math.max(0, math.min(cx + off - size/2, world.mapW - size))
    local y = math.max(0, math.min(cy - size/2, world.mapH - size))
    local dg = DroppedGun:new(x, y, gun)
    world:addEntity(dg)
    return dg
end

function DroppedGun:update(dt, world)
    self.bobTimer = self.bobTimer + dt
    self.life = self.life - dt
    if self.life <= 0 then self.toRemove = true end
end

function DroppedGun:draw()
    -- about to expire: blink so it reads as "grab it now"
    if self.life < TUNE.droppedGun.blinkTime
        and math.floor(self.life / TUNE.droppedGun.blinkInterval) % 2 == 0 then
        return
    end

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
