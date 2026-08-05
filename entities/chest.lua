-- Mystery box: pay, watch sprites spin above it, get a random reward.
-- Guns must be taken with E within the take-window or they're lost;
-- grenades / med kits / ammo refills apply automatically at spin end.
-- The roll is resolved at pay time; the spin is pure presentation.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Gun = require('hand_items.gun')
local Gif = require('core.gif')
local Audio = require('core.audio')

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
    obj.lid = Gif.load('assets/images/world/shopbox_open.gif')
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
    { q = 'grenade' }, { q = 'molotov' }, { q = 'medkit' },
}

-- spinQuads index that shows a roll result (the wheel must land on it)
local function resultIndex(r)
    local want
    if r.kind == 'grenade' then want = 5
    elseif r.kind == 'molotov' then want = 6
    elseif r.kind == 'healthpack' then want = 7
    else -- gun or refill: the gun's own sprite
        for i, e in ipairs(spinQuads) do
            if e.q == r.gunId then want = i break end
        end
    end
    return want
end

-- Can this consumable still help the player right now?
local function fitsPlayer(player, kind)
    if kind == 'healthpack' then
        return player.medkits < TUNE.healthpack.maxCarry
    end
    -- shared pool + per-kind cap (canAddThrowable checks both)
    return player:canAddThrowable(kind)
end

-- Fresh consumable bag: one card per bagCards count, Fisher-Yates shuffled
local function buildBag()
    local cards = {}
    for kind, n in pairs(TUNE.chest.bagCards) do
        for _ = 1, n do table.insert(cards, kind) end
    end
    for i = #cards, 2, -1 do
        local j = love.math.random(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    return { cards = cards, draws = 0 }
end

-- Top valid card leaves the bag; cards that can't help right now are skipped
-- and stay for later. After bagResetAfter draws (or an emptied bag) the next
-- draw starts from a fresh shuffle. The bag lives on the world — every box
-- shares it and it rides along in the run save.
local function drawFromBag(world, player)
    for _ = 1, 2 do
        local bag = world.chestBag or buildBag()
        world.chestBag = bag
        for idx, kind in ipairs(bag.cards) do
            if fitsPlayer(player, kind) then
                table.remove(bag.cards, idx)
                bag.draws = bag.draws + 1
                if bag.draws >= TUNE.chest.bagResetAfter or #bag.cards == 0 then
                    world.chestBag = nil
                end
                return kind
            end
        end
        world.chestBag = nil -- nothing usable left: reshuffle and rescan
    end
end

-- Two-stage roll: gun gate first (base odds + bonus per throwable/med kit
-- held; guaranteed gun when nothing else can drop), then the consumable bag.
-- Owned-gun rolls become an ammo refill for that gun.
function Chest:roll(player, world)
    local C = TUNE.chest
    local anyConsumable = false
    for kind in pairs(C.bagCards) do
        if fitsPlayer(player, kind) then anyConsumable = true break end
    end

    local held = player.grenades + player.molotovs + player.medkits
    local gunOdds = C.gunChance + C.gunChancePerItem * held
    if anyConsumable and love.math.random() >= gunOdds then
        return { kind = drawFromBag(world, player) }
    end

    -- gun roll: weighted split, dupe becomes a refill
    local total = 0
    for _, w in pairs(C.gunWeights) do total = total + w end
    local pick = love.math.random() * total
    local chosen
    for id, w in pairs(C.gunWeights) do
        pick = pick - w
        if pick <= 0 then chosen = id break end
    end
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
            self.result = self:roll(player, world)
            self.state = 'spinning'
            self.timer = TUNE.chest.spinTime
            self:openLid()
            local cx, cy = self:getCenter()
            Audio.playAt('crate_open', cx, cy)
        end
    elseif self.state == 'offering' then
        -- E collects whatever was rolled; if it doesn't fit any more (pool
        -- filled up during the spin) the offer just keeps waiting
        local r = self.result
        if r.kind == 'gun' then
            self:giveGun(player)
        elseif r.kind == 'refill' then
            for i = 1, 2 do
                local gun = player.items[i]
                if gun and gun.id == r.gunId then gun:refill() end
            end
            self.toastText = T('hud.chest_refill', r.name)
        elseif r.kind == 'grenade' then
            if not player:addThrowable('he') then return end
            self.toastText = T('hud.chest_grenade')
        elseif r.kind == 'molotov' then
            if not player:addThrowable('molotov') then return end
            self.toastText = T('hud.chest_molotov')
        elseif r.kind == 'healthpack' then
            if not player:addMedkit() then return end
            self.toastText = T('hud.chest_health')
        end
        if r.kind ~= 'gun' then self.toastTimer = 2 end
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

    -- warm glow on the cycling/offered item while the box is live (50% of the
    -- player light); added lazily so it also comes back after a save load
    local wantGlow = self.state ~= 'idle'
    if world and world.lighting then
        if wantGlow and not self.spinLight then
            local b = TUNE.lighting.playerBright * TUNE.chest.spinGlow
            self.spinLight = world.lighting:addPoint(
                self.x + self.width / 2, self.y - CAP - 14,
                b, b * 0.88, b * 0.68, TUNE.chest.spinGlowRange)
        elseif not wantGlow and self.spinLight then
            world.lighting:removePoint(self.spinLight)
            self.spinLight = nil
        end
    end

    if self.state == 'spinning' then
        -- wheel spin loop: also restarts after loading a mid-spin save
        if not self.spinSound then
            local cx, cy = self:getCenter()
            self.spinSound = Audio.playAt('spin_wheel', cx, cy)
        end

        -- roulette pacing: secs per sprite ramps from spinCycleStart to
        -- spinCycleEnd — a blur at first, then ticking to a stop
        local C = TUNE.chest
        local p = 1 - math.max(self.timer, 0) / C.spinTime
        local step = C.spinCycleStart
            + (C.spinCycleEnd - C.spinCycleStart) * p ^ C.spinSlowdown

        if self.timer <= step then
            -- last tick: land on the sprite of what was actually rolled
            self.spinQuad = resultIndex(self.result) or self.spinQuad
        else
            self.spinTimer = self.spinTimer + dt
            if self.spinTimer >= step then
                self.spinTimer = 0
                self.spinQuad = self.spinQuad % #spinQuads + 1
            end
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

-- Spin over: EVERY reward waits on the lid for an E within the take-window
-- (walk away and it's lost — the box already ate the money)
function Chest:resolve(world)
    self.spinSound = nil -- tail rings out on its own; next spin grabs a fresh voice
    self.state = 'offering'
    self.takeTimer = TUNE.chest.takeWindow
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
        -- item sprites flicker above the box, bobbing slightly, and the whole
        -- carousel rises out of the box over the spin (spinRise px below at
        -- the start, at its final height when the wheel stops)
        local entry = spinQuads[self.spinQuad]
        local quad = Assets.quads[entry.q][1]
        local _, _, qw, qh = quad:getViewport()
        local bob = math.sin(self.timer * 10) * 2
        local rise = TUNE.chest.spinRise * (self.timer / TUNE.chest.spinTime)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(Assets.spritesheet, quad,
            math.floor(cx), math.floor(top - 14 + bob + rise), 0, 1, 1, qw/2, qh/2)
    elseif self.state == 'offering' then
        -- the reward's own sprite waits on the lid (guns and consumables alike)
        local r = self.result
        local quadName
        if r.kind == 'gun' or r.kind == 'refill' then quadName = Gun.quadName(r.gunId)
        elseif r.kind == 'grenade' then quadName = 'grenade'
        elseif r.kind == 'molotov' then quadName = 'molotov'
        else quadName = 'medkit' end
        local quad = Assets.quads[quadName][1]
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
