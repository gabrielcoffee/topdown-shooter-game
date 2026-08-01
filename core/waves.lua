-- Wave FSM: optional 'pregame' hold (run-start fade) -> 'wave_start' banner ->
-- 'active' drip-spawn -> cleared -> 'wave_end' banner -> next wave, forever.
-- Wave 0 is a dev sandbox: no zombies ever spawn and it never ends
-- (chat: `wave 0`). All numbers come from TUNE.waves. World owns one.

local Enemy = require('entities.enemy')
local Theme = require('ui.theme')
local flux = require('lib.flux')

local Waves = {}
Waves.__index = Waves

-- zombies in wave w: quotaBase + w*(w+1)/2 -> 4, 6, 9, 13, 18, 24...
local function quotaFor(w)
    return TUNE.waves.quotaBase + w * (w + 1) / 2
end

-- secs between spawns, shrinking each wave down to the floor
local function delayFor(w)
    local t = TUNE.waves
    return math.max(t.spawnDelayFloor, t.spawnDelayStart * t.spawnDelayDecay ^ (w - 1))
end

-- last weights bracket whose fromWave <= w
local function weightsFor(w)
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

-- Weighted power-up kind for a carrier zombie
local function pickPowerup()
    local total = 0
    for _, w in pairs(TUNE.powerups.weights) do total = total + w end
    local pick = love.math.random() * total
    local chosen
    for kind, w in pairs(TUNE.powerups.weights) do
        pick = pick - w
        if pick <= 0 then chosen = kind break end
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
        carriersThisWave = 0, -- power-up carriers spawned this wave (capped)
    }
    setmetatable(obj, Waves)
    return obj
end

-- Re-entrant: restore() calls this with the saved wave number
function Waves:startWave(n)
    self.wave = n
    self.state = 'wave_start'
    self.timer = TUNE.waves.startIntermission
    self.remaining = (n == 0) and 0 or quotaFor(n) -- wave 0: sandbox, no zombies
    self.carriersThisWave = 0
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
        remaining = self.remaining,
        spawnTimer = self.spawnTimer,
        carriersThisWave = self.carriersThisWave,
        pendingWave = self.pendingWave,
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
    local current = world.currentRoom and world.currentRoom.name
    local adjacent = world:adjacentRooms()
    for _, sp in ipairs(self.spawnPoints) do
        if sp.roomName == current then
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

function Waves:spawnOne(world)
    local points = self:activePoints(world)
    if #points == 0 then return end -- map without spawn markers: never crash
    local sp = points[love.math.random(#points)]
    local t = pickType(self.wave)

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
        e.carrier = pickPowerup()
        self.carriersThisWave = self.carriersThisWave + 1
    end

    world:addEntity(e)
end

function Waves:update(dt, world)
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
        while self.remaining > 0 and self.spawnTimer <= 0 do
            self:spawnOne(world)
            self.remaining = self.remaining - 1
            self.spawnTimer = self.spawnTimer + delayFor(self.wave)
        end

        -- wave 0 never ends: free roam until a chat command moves it on
        if self.wave > 0 and self.remaining == 0 and liveEnemies(world) == 0 then
            self.state = 'wave_end'
            self.timer = TUNE.waves.endIntermission
            self:slamBanner()
            -- checkpoint: a crash or force-quit resumes from the cleared wave
            require('core.save').saveRun(world:serialize())
        end

    elseif self.state == 'wave_end' then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self:startWave(self.wave + 1)
        end
    end
end

-- Native resolution, drawn with the HUD
function Waves:drawBanner()
    if self.state == 'wave_start' then
        Theme.drawTitle(T('hud.wave', self.wave), self.bannerY)
    elseif self.state == 'wave_end' then
        Theme.drawTitle(T('hud.wave_complete'), self.bannerY)
    end
end

return Waves
