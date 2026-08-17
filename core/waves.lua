-- Wave FSM: optional 'pregame' hold (run-start fade) -> 'wave_start' banner ->
-- 'active' drip-spawn -> cleared -> 'wave_end' banner -> next wave, forever.
-- Wave 0 is a dev sandbox: no zombies ever spawn and it never ends
-- (chat: `wave 0`). All numbers come from TUNE.waves. World owns one.

local Enemy = require('entities.enemy')
local Theme = require('ui.theme')
local Particles = require('ui.particles')
local flux = require('lib.flux')

local Waves = {}
Waves.__index = Waves

-- every TUNE.waves.nightmare.every-th wave is a nightmare wave
-- (also read by entities/enemy.lua for the speed boost)
function Waves.isNightmare(w)
    local n = TUNE.waves.nightmare
    return n ~= nil and w > 0 and (n.every or 0) > 0 and w % n.every == 0
end

-- zombies in wave w: (quotaBase + w*(w+1)/2) * quotaMult, doubled on nightmares
local function quotaFor(w)
    local t = TUNE.waves
    local q = (t.quotaBase + w * (w + 1) / 2) * (t.quotaMult or 1)
    return math.floor(q + 0.5)
end

-- secs between spawns, shrinking each wave down to the floor.
-- Nightmares don't add zombies or speed — they only spawn FASTER (and mix
-- the types differently, see weights).
local function delayFor(w)
    local t = TUNE.waves
    local d = math.max(t.spawnDelayFloor, t.spawnDelayStart * t.spawnDelayDecay ^ (w - 1))
    if Waves.isNightmare(w) then d = d * (t.nightmare.spawnDelayMult or 1) end
    return d
end

-- last weights bracket whose fromWave <= w; nightmares use their own mix
local function weightsFor(w)
    if Waves.isNightmare(w) then return TUNE.waves.nightmare.weights end
    local picked
    for _, bracket in ipairs(TUNE.waves.weights) do
        if bracket.fromWave <= w then picked = bracket end
    end
    return picked
end

local function pickType(w)
    local wt = weightsFor(w)
    local roll = love.math.random() * (wt.slow + wt.normal + wt.fast)
    if roll < wt.slow then return 'slow' end
    if roll < wt.slow + wt.normal then return 'normal' end
    return 'fast'
end

-- Weighted power-up kind for a carrier zombie. Nightmares never hand out
-- a nuke (would trivialize the horde), so its weight is dropped and the
-- rest renormalize.
local function pickPowerup(noNuke)
    local total = 0
    for kind, w in pairs(TUNE.powerups.weights) do
        if not (noNuke and kind == 'nuke') then total = total + w end
    end
    local pick = love.math.random() * total
    local chosen
    for kind, w in pairs(TUNE.powerups.weights) do
        if not (noNuke and kind == 'nuke') then
            pick = pick - w
            if pick <= 0 then chosen = kind break end
        end
    end
    return chosen
end

local function liveEnemies(world)
    local n = 0
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove then n = n + 1 end
    end
    return n
end

function Waves:new(spawnPoints)
    local obj = {
        wave = 1,
        state = 'wave_start',
        timer = 0,
        remaining = 0,   -- zombies still to spawn this wave
        spawnTimer = 0,
        spawnPoints = spawnPoints,
        bannerY = -160,
        emberAlpha = 0,  -- menu embers behind the wave banner (fade in/out)
        carriersThisWave = 0, -- power-up carriers spawned this wave (capped)
        pending = {},    -- telegraphed spawns: ground haze now, zombie in 1s
    }
    setmetatable(obj, Waves)
    return obj
end

-- Re-entrant: restore() calls this with the saved wave number
function Waves:startWave(n)
    self.wave = n
    self.clearedNightmare = false
    self.state = 'wave_start'
    self.timer = TUNE.waves.startIntermission
    self.remaining = (n == 0) and 0 or quotaFor(n) -- wave 0: sandbox, no zombies
    self.carriersThisWave = 0
    self.pending = {} -- a forced wave switch drops half-telegraphed spawns
    self:slamBanner()
end

-- Hold the FSM silent (no banner, no spawns) for secs, then start wave n —
-- lets the run-start fade finish before the first banner slams down
function Waves:hold(secs, n)
    self.state = 'pregame'
    self.timer = secs
    self.pendingWave = n or 1
end

function Waves:slamBanner()
    self.bannerY = -160
    flux.to(self, TUNE.fx.titleSlamTime, { bannerY = 190 }):ease('quartin')
end

-- Run-save snapshot: the whole FSM, so a save mid-wave resumes with the same
-- zombies still owed and the same timers running
function Waves:serialize()
    return {
        wave = self.wave,
        state = self.state,
        timer = self.timer,
        -- mid-telegraph spawns fold back into the owed count; they re-run
        -- their telegraph on load instead of popping in with no warning
        remaining = self.remaining + #self.pending,
        spawnTimer = self.spawnTimer,
        carriersThisWave = self.carriersThisWave,
        pendingWave = self.pendingWave,
        clearedNightmare = self.clearedNightmare,
    }
end

function Waves:restore(d)
    self.wave = d.wave or 1
    self.state = d.state or 'wave_start'
    self.timer = d.timer or 0
    self.remaining = d.remaining or 0
    self.spawnTimer = math.max(0, d.spawnTimer or 0)
    self.carriersThisWave = d.carriersThisWave or 0
    self.pendingWave = d.pendingWave
    self.clearedNightmare = d.clearedNightmare or false
    self.pending = {}
    -- banner states come back with the title already slammed down
    if self.state == 'wave_start' or self.state == 'wave_end' then
        self.bannerY = 190
    end
end

-- Spawns follow the player: mostly the CURRENT room, and with
-- TUNE.waves.adjacentRoomChance a room right next door — but only one the
-- player has already been inside AND that is reachable right now (a locked
-- door between them means not adjacent; see World:adjacentRooms).
-- A room without markers falls back to visited rooms, then to every point
-- (a map without markers must never crash the spawner).
function Waves:activePoints(world)
    local inRoom, nextDoor, visited = {}, {}, {}
    -- co-op: "the current room" is every room somebody is standing in, and
    -- "next door" is anything adjacent to any of them
    local current, adjacent = {}, {}
    for _, p in ipairs(world.players) do
        if p.health > 0 and p.currentRoom then
            current[p.currentRoom.name] = true
            for name in pairs(world:adjacentRooms(p.currentRoom)) do
                adjacent[name] = true
            end
        end
    end
    for _, sp in ipairs(self.spawnPoints) do
        if sp.roomName and current[sp.roomName] then
            table.insert(inRoom, sp)
        elseif sp.roomName and adjacent[sp.roomName] and world.visitedRooms[sp.roomName] then
            table.insert(nextDoor, sp)
        end
        if not sp.roomName or world.visitedRooms[sp.roomName] then
            table.insert(visited, sp)
        end
    end
    if #nextDoor > 0 and #inRoom > 0
        and love.math.random() < TUNE.waves.adjacentRoomChance then
        return nextDoor
    end
    if #inRoom > 0 then return inRoom end
    if #nextDoor > 0 then return nextDoor end
    if #visited > 0 then return visited end
    return self.spawnPoints
end

-- Surprise spawn spot: a random walkable tile in a ring around the player,
-- inside the current room, clear of crates/doors. nil = no clear spot found
-- (caller falls back to the normal markers).
function Waves:nearPlayerPoint(world)
    local t = TUNE.waves
    local ts = TUNE.tiles.size
    -- co-op: surprise somebody at random, in their own room, so the scare
    -- isn't always aimed at the host
    local victim = world:randomLivePlayer()
    if not victim then return nil end
    local px, py = victim:getCenter()
    local room = victim.currentRoom
    for _ = 1, 12 do
        local ang = love.math.random() * math.pi * 2
        local dist = t.nearMinDist + love.math.random() * (t.nearMaxDist - t.nearMinDist)
        local x = math.floor((px + math.cos(ang) * dist) / ts) * ts
        local y = math.floor((py + math.sin(ang) * dist) / ts) * ts
        local cx, cy = x + ts / 2, y + ts / 2
        local tile = world.map:typeAt(cx, cy)
        local inRoom = not room or (cx >= room.x and cx < room.x + room.w
                                and cy >= room.y and cy < room.y + room.h)
        if inRoom and tile ~= 'solid' and tile ~= 'void' then
            local blocked = false
            for _, e in ipairs(world.entities) do
                if (e.type == 'crate' or e.type == 'door') and not e.toRemove
                    and cx >= e.x and cx < e.x + e.width
                    and cy >= e.y and cy < e.y + e.height then
                    blocked = true
                    break
                end
            end
            if not blocked then return { x = x, y = y } end
        end
    end
    return nil
end

-- Telegraph first: pick the point and type now, puff a haze cloud in the
-- zombie's colors over its spawn spot, and only materialize it after
-- telegraphTime (the classic "something is coming" beat)
function Waves:queueSpawn(world)
    local sp
    local nearChance = TUNE.waves.nearPlayerChance or 0
    if Waves.isNightmare(self.wave) then
        nearChance = TUNE.waves.nightmare.nearPlayerChance or nearChance
    end
    if love.math.random() < nearChance then
        sp = self:nearPlayerPoint(world)
    end
    if not sp then
        local points = self:activePoints(world)
        if #points == 0 then return end -- map without spawn markers: never crash
        sp = points[love.math.random(#points)]
    end
    table.insert(self.pending, {
        sp = sp,
        t = pickType(self.wave),
        timer = TUNE.waves.telegraphTime,
    })
end

function Waves:materialize(world, sp, t)
    -- center the zombie on the spawn tile; sizes differ per type
    local half = TUNE.tiles.size / 2
    local size = TUNE.zombies[t].size
    local x, y = sp.x + half - size/2, sp.y + half - size/2

    local e
    if t == 'slow' then e = Enemy:newSlow(x, y, self.wave)
    elseif t == 'normal' then e = Enemy:newNormal(x, y, self.wave)
    else e = Enemy:newFast(x, y, self.wave) end

    -- fast (runner) zombies may carry a power-up: they glow and drop it
    -- on death; capped per wave so late hordes don't rain pickups
    if t == 'fast' and self.carriersThisWave < TUNE.powerups.maxPerWave
        and love.math.random() < TUNE.powerups.carrierChance then
        e.carrier = pickPowerup(Waves.isNightmare(self.wave))
        self.carriersThisWave = self.carriersThisWave + 1
    end

    world:addEntity(e)
end

function Waves:update(dt, world)
    -- menu embers behind the banner, NIGHTMARE waves only: fade in on the
    -- slam, fade out over the last beat of the intermission
    local fadeT = TUNE.fx.bannerEmberFade or 0.6
    local target = (self.state == 'wave_start' and Waves.isNightmare(self.wave)
        and self.timer > fadeT) and 1 or 0
    local step = dt / fadeT
    if self.emberAlpha < target then
        self.emberAlpha = math.min(target, self.emberAlpha + step)
    else
        self.emberAlpha = math.max(target, self.emberAlpha - step)
    end
    if self.emberAlpha > 0 then Particles.update(dt) end

    if self.state == 'pregame' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self:startWave(self.pendingWave or 1)
        end

    elseif self.state == 'wave_start' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self.state = 'active'
            self.spawnTimer = 0 -- first zombie drops right away
        end

    elseif self.state == 'active' then
        self.spawnTimer = self.spawnTimer - dt
        -- alive cap: telegraphed spawns count too (they WILL be zombies)
        local cap = TUNE.waves.maxAlive or math.huge
        local alive = liveEnemies(world) + #self.pending
        while self.remaining > 0 and self.spawnTimer <= 0 and alive < cap do
            self:queueSpawn(world)
            alive = alive + 1
            self.remaining = self.remaining - 1
            self.spawnTimer = self.spawnTimer + delayFor(self.wave)
        end
        -- cap reached: hold the timer at zero so freed slots refill at the
        -- normal pace instead of bursting out the whole accumulated debt
        if self.remaining > 0 and alive >= cap and self.spawnTimer < 0 then
            self.spawnTimer = 0
        end

        -- telegraphed spawns: haze every frame, zombie when the timer runs out
        local half = TUNE.tiles.size / 2
        for i = #self.pending, 1, -1 do
            local p = self.pending[i]
            p.timer = p.timer - dt
            world.vfx:spawnCloud(p.sp.x + half, p.sp.y + half,
                TUNE.zombies[p.t].size / 2, TUNE.zombies[p.t].cloudColor)
            if p.timer <= 0 then
                self:materialize(world, p.sp, p.t)
                table.remove(self.pending, i)
            end
        end

        -- wave 0 never ends: free roam until a chat command moves it on
        if self.wave > 0 and self.remaining == 0 and #self.pending == 0
            and liveEnemies(world) == 0 then
            self.state = 'wave_end'
            self.timer = TUNE.waves.endIntermission
            -- surviving a nightmare pays: cash now, bonus line on the banner
            self.clearedNightmare = Waves.isNightmare(self.wave)
            if self.clearedNightmare then
                for _, p in ipairs(world.players) do
                    if p.health > 0 then
                        p:addMoney(TUNE.waves.nightmare.bonusMoney or 0)
                    end
                end
            end
            self:slamBanner()
            -- checkpoint: a crash or force-quit resumes from the cleared wave
            require('core.save').saveRun(world:serialize())
        end

    elseif self.state == 'wave_end' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            -- co-op: anyone who bled out sits the wave out and comes back
            -- for the next one, on the starting loadout (see Player:respawn).
            -- Done before startWave so they are on their feet in time to be
            -- counted as a spawn anchor.
            for _, p in ipairs(world.players) do
                if p.dead then p:respawn(world) end
            end
            self:startWave(self.wave + 1)
        end
    end
end

-- Native resolution, drawn with the HUD
function Waves:drawBanner()
    if (self.emberAlpha or 0) > 0.01 then
        Particles.drawEmbers(self.emberAlpha)
    end
    if self.state == 'wave_start' then
        if Waves.isNightmare(self.wave) then
            Theme.drawTitle(T('hud.wave_nightmare', self.wave), self.bannerY,
                Theme.colors.nightmare)
        else
            Theme.drawTitle(T('hud.wave', self.wave), self.bannerY)
        end
    elseif self.state == 'wave_end' then
        Theme.drawTitle(T('hud.wave_complete'), self.bannerY)
        if self.clearedNightmare then
            Theme.drawHint(T('hud.nightmare_bonus', TUNE.waves.nightmare.bonusMoney or 0),
                self.bannerY + 70, Theme.colors.nightmare)
        end
    end
end

return Waves
