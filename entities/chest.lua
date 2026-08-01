-- Mystery box: pay, watch sprites spin above it, get a random reward.
-- Guns must be taken with E within the take-window or they're lost;
-- grenades / med kits / ammo refills apply automatically at spin end.
-- The roll is resolved at pay time; the spin is pure presentation.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Gun = require('hand_items.gun')
local Gif = require('core.gif')

local Chest = {}
Chest.__index = Chest
setmetatable(Chest, Entity)

-- Sprite is 64x64 but the hitbox is only the bottom 64x32; the top 32px is a
-- walk-behind cap (same split-depth trick as the crate, one anchor).
local SPRITE_W, SPRITE_H = 64, 64
local CAP = SPRITE_H - 32 -- 32px overhang above the hitbox

function Chest:new(x, y)
    -- box = the 64x32 hitbox (the sprite is drawn CAP px above it, see draw)
    local obj = Entity:new(x, y, SPRITE_W, SPRITE_H - CAP)
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

    -- lid animation, driven straight from the gif: frame 1 = closed, last =
    -- fully open. lidDir +1 opens, -1 closes, 0 = settled.
    obj.lid = Gif.load('assets/shopbox_open.gif')
    obj.lidFrame = 1
    obj.lidTimer = 0
    obj.lidDir = 0

    setmetatable(obj, Chest)
    return obj
end

-- Depth anchor = top of the hitbox (like the crate): feet below draw in front,
-- above draw behind and get covered by the whole sprite incl. the cap.
function Chest:sortY()
    return self.y
end

function Chest:openLid()  self.lidDir = 1  end
function Chest:closeLid() self.lidDir = -1 end

-- Spin price right now: fire sale power-up slashes it while it runs
function Chest:currentCost()
    if world and world.buffs and world.buffs.firesale > 0 then
        return TUNE.powerups.fireSaleCost
    end
    return TUNE.chest.cost
end

-- quads cycled above the box while spinning (tint = molotov placeholder)
local spinQuads = {
    { q = 'pistol' }, { q = 'ak47' }, { q = 'm4a1' }, { q = 'shotgun' },
    { q = 'grenade' }, { q = 'grenade', tint = { 1, 0.5, 0.15 } },
}

-- Weighted pick over categories that can currently help the player.
-- Owned-gun rolls become an ammo refill for that gun.
function Chest:roll(player)
    local weights = {}
    for key, w in pairs(TUNE.chest.weights) do
        local valid = true
        if (key == 'grenade' or key == 'molotov') and player:throwableSpace() <= 0 then
            valid = false -- slot 4 is one shared pool
        elseif key == 'healthpack' and player.medkits >= TUNE.healthpack.maxCarry then
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

    if chosen == 'grenade' or chosen == 'molotov' or chosen == 'healthpack' then
        return { kind = chosen }
    end

    -- gun roll: dupe becomes a refill
    for i = 1, 2 do
        local owned = player.items[i]
        if owned and owned.id == chosen then
            return { kind = 'refill', gunId = chosen, name = Gun.names[chosen] }
        end
    end
    return { kind = 'gun', gunId = chosen, name = Gun.names[chosen] }
end

function Chest:giveGun(player)
    player:giveGun(Gun.newById(self.result.gunId)) -- replaced gun is lost (box ate it)
end

function Chest:interact(player, world)
    if self.state == 'idle' then
        if player:trySpend(self:currentCost()) then
            self.result = self:roll(player)
            self.state = 'spinning'
            self.timer = TUNE.chest.spinTime
            self:openLid()
        end
    elseif self.state == 'offering' then
        self:giveGun(player)
        self.state = 'idle'
        self.result = nil
        self:closeLid()
    end
end

function Chest:update(dt, world)
    -- advance the lid open/close animation
    if self.lidDir ~= 0 then
        self.lidTimer = self.lidTimer + dt
        local step = TUNE.chest.openTime / (self.lid.frames - 1)
        while self.lidDir ~= 0 and self.lidTimer >= step do
            self.lidTimer = self.lidTimer - step
            self.lidFrame = self.lidFrame + self.lidDir
            if self.lidFrame <= 1 then self.lidFrame, self.lidDir = 1, 0 end
            if self.lidFrame >= self.lid.frames then
                self.lidFrame, self.lidDir = self.lid.frames, 0
            end
        end
    end

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
            self:closeLid()
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
            if gun and gun.id == r.gunId then gun:refill() end
        end
        self.toastText = T('hud.chest_refill', r.name)
    elseif r.kind == 'grenade' then
        player:addThrowable('he')
        self.toastText = T('hud.chest_grenade')
    elseif r.kind == 'molotov' then
        player:addThrowable('molotov')
        self.toastText = T('hud.chest_molotov')
    elseif r.kind == 'healthpack' then
        player:addMedkit()
        self.toastText = T('hud.chest_health')
    end

    self.toastTimer = 2
    self.state = 'idle'
    self.result = nil
    self:closeLid()
end

-- Run-save: a paid spin (or a gun waiting on the lid) survives save & quit —
-- money already left the wallet, the reward must not vanish with it
function Chest:serialize()
    return {
        x = self.x, y = self.y,
        state = self.state,
        timer = self.timer,
        takeTimer = self.takeTimer,
        result = self.result
            and { kind = self.result.kind, gunId = self.result.gunId } or nil,
    }
end

function Chest:restoreState(d)
    self.state = d.state or 'idle'
    self.timer = d.timer or 0
    self.takeTimer = d.takeTimer or 0
    self.result = d.result
    if self.result and self.result.gunId then
        self.result.name = Gun.names[self.result.gunId]
        if not self.result.name then -- gun id gone from the roster: eat the roll
            self.state, self.result = 'idle', nil
        end
    end
    -- snap the lid: open for live states, closed for idle (no mid-tween saves)
    if self.state == 'idle' then
        self.lidFrame, self.lidDir = 1, 0
    else
        self.lidFrame, self.lidDir = self.lid.frames, 0
    end
end

-- H overlay: solid 64x32 box + the interact zone where E works
function Chest:drawHitbox()
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0, 1, 0, 0.9)
    love.graphics.rectangle('line', self.x, self.y, self.width, self.height)
    local pad = TUNE.chest.interactPad
    love.graphics.setColor(1, 0.9, 0.3, 0.6)
    love.graphics.rectangle('line', self.x - pad, self.y - pad,
        self.width + pad * 2, self.height + pad * 2)
    love.graphics.setColor(Color.white())
end

function Chest:draw()
    local x = math.floor(self.x)
    local top = math.floor(self.y) - CAP  -- sprite sits CAP px above the hitbox

    -- the box itself (lid frame from the gif)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.lid.image, self.lid.quads[self.lidFrame], x, top)

    love.graphics.setFont(smallFont)
    local cx = x + self.width / 2

    if self.state == 'idle' then
        local txt = '$' .. self:currentCost()
        if self:currentCost() < TUNE.chest.cost then
            love.graphics.setColor(0.4, 1, 0.4) -- fire sale: discount reads green
        else
            love.graphics.setColor(1, 0.85, 0.35)
        end
        love.graphics.print(txt, cx - smallFont:getWidth(txt)/2, top - smallFont:getHeight() - 2)

        if self.toastText then
            love.graphics.setColor(1, 0.9, 0.3)
            love.graphics.print(self.toastText,
                cx - smallFont:getWidth(self.toastText)/2, top - smallFont:getHeight() - 14)
        end
    elseif self.state == 'spinning' then
        -- item sprites flicker above the box, bobbing slightly
        local entry = spinQuads[self.spinQuad]
        local quad = Assets.quads[entry.q][1]
        local _, _, qw, qh = quad:getViewport()
        local bob = math.sin(self.timer * 10) * 2
        local t = entry.tint
        if t then love.graphics.setColor(t[1], t[2], t[3])
        else love.graphics.setColor(1, 1, 1) end
        love.graphics.draw(Assets.spritesheet, quad,
            math.floor(cx), math.floor(top - 14 + bob), 0, 1, 1, qw/2, qh/2)
    elseif self.state == 'offering' then
        local quad = Assets.quads[Gun.quadName(self.result.gunId)][1]
        local _, _, qw, qh = quad:getViewport()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(Assets.spritesheet, quad,
            math.floor(cx), top - 16, 0, 1, 1, qw/2, qh/2)

        -- shrinking take-window bar
        local frac = self.takeTimer / TUNE.chest.takeWindow
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x, top - 6, self.width, 3)
        love.graphics.setColor(1, 0.9, 0.3)
        love.graphics.rectangle('fill', x, top - 6, self.width * frac, 3)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(Color.white())
end

return Chest
