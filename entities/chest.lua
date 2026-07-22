-- Mystery box: pay, watch sprites spin above it, get a random reward.
-- Guns must be taken with E within the take-window or they're lost;
-- grenades / med kits / ammo refills apply automatically at spin end.
-- The roll is resolved at pay time; the spin is pure presentation.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Gun = require('hand_items.gun')
local HandItem = require('hand_items.hand_item')

local Chest = {}
Chest.__index = Chest
setmetatable(Chest, Entity)

local gunFactories = {
    ak47   = function() return Gun:newAk47() end,
    m4a1   = function() return Gun:newM4A1() end,
    sawedoff = function() return Gun:newShotgun() end,
}

local gunNames = { ak47 = 'AK-47', m4a1 = 'M4A1', sawedoff = 'Sawed-Off' }

function Chest:new(x, y)
    local obj = Entity:new(x, y, TUNE.tiles.size, TUNE.tiles.size)
    obj.type = 'chest'
    obj.isObstacle = true

    obj.state = 'idle' -- idle | spinning | offering
    obj.timer = 0
    obj.takeTimer = 0
    obj.result = nil       -- { kind='gun'|'refill'|'grenade'|'healthpack', gunId?, name? }
    obj.spinQuad = 1
    obj.spinTimer = 0
    obj.toastText = nil
    obj.toastTimer = 0

    setmetatable(obj, Chest)
    return obj
end

-- quads cycled above the box while spinning
local spinQuads = { 'pistol', 'ak47', 'm4a1', 'shotgun', 'grenade' }

-- Weighted pick over categories that can currently help the player.
-- Owned-gun rolls become an ammo refill for that gun.
function Chest:roll(player)
    local weights = {}
    for key, w in pairs(TUNE.chest.weights) do
        local valid = true
        if key == 'grenade' and player.grenades >= TUNE.grenade.maxCarry then
            valid = false
        elseif key == 'healthpack' and player.items[5] ~= nil then
            valid = false
        end
        if valid then weights[key] = w end
    end

    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local pick = love.math.random() * total
    local chosen
    for key, w in pairs(weights) do
        pick = pick - w
        if pick <= 0 then chosen = key break end
    end

    if chosen == 'grenade' or chosen == 'healthpack' then
        return { kind = chosen }
    end

    -- gun roll: dupe becomes a refill
    for i = 1, 2 do
        local owned = player.items[i]
        if owned and owned.id == chosen then
            return { kind = 'refill', gunId = chosen, name = gunNames[chosen] }
        end
    end
    return { kind = 'gun', gunId = chosen, name = gunNames[chosen] }
end

-- Target slot: empty gun slot first, else the gun in hand,
-- else the last gun slot the player held
function Chest:giveGun(player)
    local target
    if not player.items[2] then target = 2
    elseif not player.items[1] then target = 1
    elseif player.itemIndex == 1 or player.itemIndex == 2 then target = player.itemIndex
    else target = player.lastGunSlot end

    player.items[target] = gunFactories[self.result.gunId]()
    player.itemIndex = target
    player.lastGunSlot = target
end

function Chest:interact(player, world)
    if self.state == 'idle' then
        if player.money >= TUNE.chest.cost then
            player.money = player.money - TUNE.chest.cost
            self.result = self:roll(player)
            self.state = 'spinning'
            self.timer = TUNE.chest.spinTime
        end
    elseif self.state == 'offering' then
        self:giveGun(player)
        self.state = 'idle'
        self.result = nil
    end
end

function Chest:update(dt, world)
    if self.toastTimer > 0 then
        self.toastTimer = self.toastTimer - dt
        if self.toastTimer <= 0 then self.toastText = nil end
    end

    if self.state == 'spinning' then
        self.spinTimer = self.spinTimer + dt
        if self.spinTimer >= TUNE.chest.spinCycleTime then
            self.spinTimer = 0
            self.spinQuad = self.spinQuad % #spinQuads + 1
        end

        self.timer = self.timer - dt
        if self.timer <= 0 then
            self:resolve(world)
        end
    elseif self.state == 'offering' then
        self.takeTimer = self.takeTimer - dt
        if self.takeTimer <= 0 then -- money spent, gun lost
            self.state = 'idle'
            self.result = nil
        end
    end
end

-- Spin over: guns wait for a second E, everything else applies now
function Chest:resolve(world)
    local player = world.player
    local r = self.result

    if r.kind == 'gun' then
        self.state = 'offering'
        self.takeTimer = TUNE.chest.takeWindow
        return
    end

    if r.kind == 'refill' then
        for i = 1, 2 do
            local gun = player.items[i]
            if gun and gun.id == r.gunId then
                gun:cancelReload()
                gun.curClip = gun.maxClip
                gun.bulletsLeft = gun.maxClip * 3
            end
        end
        self.toastText = T('hud.chest_refill', r.name)
    elseif r.kind == 'grenade' then
        player.grenades = math.min(TUNE.grenade.maxCarry, player.grenades + 1)
        self.toastText = T('hud.chest_grenade')
    elseif r.kind == 'healthpack' then
        player.items[5] = HandItem:newHealthPack()
        self.toastText = T('hud.chest_health')
    end

    self.toastTimer = 2
    self.state = 'idle'
    self.result = nil
end

function Chest:draw()
    local x, y = math.floor(self.x), math.floor(self.y)

    love.graphics.setColor(0.45, 0.2, 0.55)
    love.graphics.rectangle('fill', x, y, self.width, self.height)
    love.graphics.setColor(0.75, 0.5, 0.9)
    love.graphics.rectangle('line', x, y, self.width, self.height)
    love.graphics.rectangle('line', x + 4, y + 4, self.width - 8, self.height - 8)

    love.graphics.setFont(smallFont)
    local cx = x + self.width / 2

    if self.state == 'idle' then
        local txt = '$' .. TUNE.chest.cost
        love.graphics.setColor(Color.black())
        love.graphics.print(txt, cx - smallFont:getWidth(txt)/2, y - smallFont:getHeight())

        if self.toastText then
            love.graphics.setColor(1, 0.9, 0.3)
            love.graphics.print(self.toastText,
                cx - smallFont:getWidth(self.toastText)/2, y - 24)
        end
    elseif self.state == 'spinning' then
        -- item sprites flicker above the box, bobbing slightly
        local quad = Assets.quads[spinQuads[self.spinQuad]][1]
        local _, _, qw, qh = quad:getViewport()
        local bob = math.sin(self.timer * 10) * 2
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(Assets.spritesheet, quad,
            math.floor(cx), math.floor(y - 20 + bob), 0, 1, 1, qw/2, qh/2)
    elseif self.state == 'offering' then
        local quad = Assets.quads[self.result.gunId == 'sawedoff' and 'shotgun'
            or self.result.gunId][1]
        local _, _, qw, qh = quad:getViewport()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(Assets.spritesheet, quad,
            math.floor(cx), y - 22, 0, 1, 1, qw/2, qh/2)

        -- shrinking take-window bar
        local frac = self.takeTimer / TUNE.chest.takeWindow
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x, y - 8, self.width, 3)
        love.graphics.setColor(1, 0.9, 0.3)
        love.graphics.rectangle('fill', x, y - 8, self.width * frac, 3)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(Color.white())
end

return Chest
