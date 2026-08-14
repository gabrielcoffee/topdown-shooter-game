local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')

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

-- The walkable axis of the doorway, probed once from the map: a door set in
-- a wall has solid tiles on two opposite sides and open floor on the other
-- two — the lock icon belongs on an open side, facing the player. Falls back
-- to the door's own shape if the probe is ambiguous (freestanding door).
function Door:passageAxis(map)
    if self.axis then return self.axis end
    local cx, cy = self:getCenter()
    local probe = TUNE.tiles.size / 2
    local sideWalls = map:isSolidAt(self.x - probe, cy)
        and map:isSolidAt(self.x + self.width + probe, cy)
    local capWalls = map:isSolidAt(cx, self.y - probe)
        and map:isSolidAt(cx, self.y + self.height + probe)
    if sideWalls and not capWalls then
        self.axis = 'vertical'       -- walls left/right: walk through up-down
    elseif capWalls and not sideWalls then
        self.axis = 'horizontal'     -- walls above/below: walk through left-right
    else
        self.axis = self.width >= self.height and 'vertical' or 'horizontal'
    end
    return self.axis
end

-- Lock icon floated in front of the door, on whichever open side the player
-- is: fades in from lockFadeFar down to lockFadeNear, so it reads as "this
-- one opens" without cluttering the room from across the map.
function Door:drawLock()
    local D = TUNE.door
    local cx, cy = self:getCenter()
    local near = world:nearestPlayer(cx, cy) or world.player
    if not near then return end
    local px, py = near:getCenter()
    local dx, dy = px - cx, py - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    local alpha = (D.lockFadeFar - dist) / (D.lockFadeFar - D.lockFadeNear)
    alpha = math.max(0, math.min(1, alpha))
    if alpha <= 0 then return end

    local quad = Assets.quads.lock[1]
    local _, _, qw, qh = quad:getViewport()
    local ix, iy
    if self:passageAxis(world.map) == 'vertical' then
        ix = cx
        iy = dy < 0 and (self.y - D.lockGap - qh / 2)
                     or (self.y + self.height + D.lockGap + qh / 2)
    else
        ix = dx < 0 and (self.x - D.lockGap - qw / 2)
                     or (self.x + self.width + D.lockGap + qw / 2)
        iy = cy
    end

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(Assets.spritesheet, quad,
        math.floor(ix), math.floor(iy), 0, 1, 1, qw / 2, qh / 2)
    love.graphics.setColor(Color.white())
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

    self:drawLock()
end

return Door
