-- Power-up drop: left behind by a glowing carrier zombie, picked up by
-- WALKING over it (no E). Bobs, blinks near the end of its lifetime, then
-- vanishes. Placeholder 32x32 procedural sprites per kind — real art later.
-- Kinds: nuke, maxammo, instakill, freeze, doublepoints.

local Entity = require('entities.entity')
local Audio = require('core.audio')

local Powerup = {}
Powerup.__index = Powerup
setmetatable(Powerup, Entity)

-- cx/cy = center (usually the dead carrier's center)
function Powerup:new(cx, cy, kind)
    local obj = Entity:new(cx - 16, cy - 16, 32, 32)
    obj.type = 'powerup'
    obj.kind = kind
    obj.bobTimer = love.math.random() * math.pi * 2
    obj.life = TUNE.powerups.lifetime
    setmetatable(obj, Powerup)
    return obj
end

function Powerup:update(dt, world)
    self.bobTimer = self.bobTimer + dt
    self.life = self.life - dt
    if self.life <= 0 then
        self.toRemove = true
        return
    end

    -- walk-over pickup (padded AABB vs the player)
    local pad = TUNE.powerups.pickupPad
    for _, p in ipairs(world.players) do
        if p.health > 0 and not p.toRemove
            and p.x < self.x + self.width + pad and p.x + p.width > self.x - pad
            and p.y < self.y + self.height + pad and p.y + p.height > self.y - pad then
            self:apply(world, p)
            self.toRemove = true
            return
        end
    end
end

-- picker = who walked over it; buffs are shared, cash pays the picker
function Powerup:apply(world, picker)
    local P = TUNE.powerups
    local player = picker or world.player

    if self.kind == 'nuke' then
        -- kill every live zombie; nukedSilent skips the per-zombie death SFX
        -- (audio pool flood) and stops carriers dropping fresh power-ups
        for _, e in ipairs(world.entities) do
            if e.type == 'enemy' and not e.toRemove and e.health > 0 then
                e.health = 0
                e.nukedSilent = true
            end
        end
        local cx, cy = player:getCenter()
        world.lighting:flash(cx, cy, 1, 1, 0.9, 900, 0.4)
        Audio.play('grenade_blast')
        player:addMoney(P.nukeMoney)
    elseif self.kind == 'maxammo' then
        -- both gun slots to full (instant reload included); bullets only —
        -- throwables never top up (grenades stay a chest/wallet purchase)
        for i = 1, 2 do
            local gun = player.items[i]
            if gun then gun:refill() end
        end
    elseif self.kind == 'instakill' then
        world.buffs.instakill = P.instakillTime
    elseif self.kind == 'freeze' then
        world.buffs.freeze = P.freezeTime
    elseif self.kind == 'doublepoints' then
        world.buffs.doublepoints = P.doublePointsTime
    elseif self.kind == 'firesale' then
        world.buffs.firesale = P.fireSaleTime
    elseif self.kind == 'carpenter' then
        world:rebuildCrates()
        player:addMoney(P.carpenterMoney)
    end

    world.pickupToast = { text = T('powerup.' .. self.kind), t = 2 }
    Audio.play('gun_draw', 0.8) -- pickup blip placeholder
end

-- Icon painter shared by the ground drop and the HUD buff readout: draws the
-- kind's placeholder icon (~26px art) centered on (cx, cy), scaled.
function Powerup.drawIcon(k, cx, cy, scale)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(scale or 1)

    if k == 'nuke' then
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.circle('fill', 0, 0, 12)
        love.graphics.setColor(0.1, 0.1, 0.1)
        love.graphics.circle('fill', 0, 0, 5)
    elseif k == 'maxammo' then
        love.graphics.setColor(0.25, 0.8, 0.3)
        love.graphics.rectangle('fill', -11, -8, 22, 16, 2, 2)
        love.graphics.setColor(0.1, 0.3, 0.12)
        love.graphics.rectangle('line', -11, -8, 22, 16, 2, 2)
    elseif k == 'instakill' then
        love.graphics.setColor(0.95, 0.95, 0.95)
        love.graphics.circle('fill', 0, 0, 12)
        love.graphics.setColor(0.85, 0.1, 0.1)
        love.graphics.setLineWidth(3)
        love.graphics.line(-7, -7, 7, 7)
        love.graphics.line(-7, 7, 7, -7)
        love.graphics.setLineWidth(1)
    elseif k == 'freeze' then
        love.graphics.setColor(0.35, 0.85, 1)
        love.graphics.polygon('fill', 0, -13, 10, 0, 0, 13, -10, 0)
    elseif k == 'doublepoints' then
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.circle('fill', 0, 0, 12)
        love.graphics.setColor(0.25, 0.15, 0)
        love.graphics.setFont(smallFont) -- glyph is icon art, not HUD text
        local txt = 'x2'
        love.graphics.print(txt, -smallFont:getWidth(txt) / 2,
            -smallFont:getHeight() / 2)
        love.graphics.setFont(font)
    elseif k == 'firesale' then
        love.graphics.setColor(0.3, 0.9, 0.35)
        love.graphics.circle('fill', 0, 0, 12)
        love.graphics.setColor(0, 0.25, 0.05)
        love.graphics.setFont(smallFont)
        local txt = '$'
        love.graphics.print(txt, -smallFont:getWidth(txt) / 2,
            -smallFont:getHeight() / 2)
        love.graphics.setFont(font)
    elseif k == 'carpenter' then
        love.graphics.setColor(0.62, 0.42, 0.18)
        love.graphics.rectangle('fill', -11, -9, 22, 18, 2, 2)
        love.graphics.setColor(0.85, 0.65, 0.35)
        love.graphics.setLineWidth(2)
        love.graphics.line(-11, -9, 11, 9)
        love.graphics.line(-11, 9, 11, -9)
        love.graphics.rectangle('line', -11, -9, 22, 18, 2, 2)
        love.graphics.setLineWidth(1)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function Powerup:draw()
    local P = TUNE.powerups

    -- end-of-life blink (same pattern as dropped guns)
    if self.life < P.blinkTime
        and (self.life % (P.blinkInterval * 2)) < P.blinkInterval then
        return
    end

    local cx = math.floor(self.x + self.width / 2)
    local bob = math.sin(self.bobTimer * 4) * 2
    local cy = math.floor(self.y + self.height / 2 + bob)

    -- drop shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse('fill', cx, self.y + self.height - 2, 10, 4)

    Powerup.drawIcon(self.kind, cx, cy, 1)
end

return Powerup
