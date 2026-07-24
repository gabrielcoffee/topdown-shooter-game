-- Player spawn marker. Placed in LDtk (blue cross, max 1 per level) to say
-- where the player enters/respawns. Purely positional — it has no update or
-- collision, and is only drawn as a debug marker with the H hitbox overlay.

local Entity = require('entities.entity')
local Color = require('core.color')

local PlayerSpawn = {}
PlayerSpawn.__index = PlayerSpawn
setmetatable(PlayerSpawn, Entity)

function PlayerSpawn:new(x, y)
    local obj = Entity:new(x, y, TUNE.tiles.size, TUNE.tiles.size)
    obj.type = 'playerspawn'
    setmetatable(obj, PlayerSpawn)
    return obj
end

-- Where the player's top-left should sit to be centered on this marker.
function PlayerSpawn:playerPos(pw, ph)
    local cx, cy = self:getCenter()
    return cx - pw / 2, cy - ph / 2
end

function PlayerSpawn:drawHitbox()
    local cx, cy = self:getCenter()
    love.graphics.setColor(0.2, 0.53, 0.87, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.line(cx - 8, cy, cx + 8, cy)
    love.graphics.line(cx, cy - 8, cx, cy + 8)
    love.graphics.circle('line', cx, cy, 3)
    love.graphics.setColor(Color.white())
end

return PlayerSpawn
