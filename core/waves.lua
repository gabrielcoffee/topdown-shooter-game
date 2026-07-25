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
    local roll = love.math.random() * (wt.slow + wt.fast + wt.runner)
    if roll < wt.slow then return 'slow' end
    if roll < wt.slow + wt.fast then return 'fast' end
    return 'runner'
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

-- Points behind an unopened door stay inactive
function Waves:activePoints(world)
    local active = {}
    for _, sp in ipairs(self.spawnPoints) do
        if not sp.door or world.openedDoors[sp.door] then
            table.insert(active, sp)
        end
    end
    if #active == 0 then return self.spawnPoints end
    return active
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
    elseif t == 'fast' then e = Enemy:newFast(x, y, self.wave)
    else e = Enemy:newRunner(x, y, self.wave) end
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

        -- live cap: past maxAlive the rest of the quota queues up (separation
        -- is O(n^2) and every zombie repaths — an uncapped late wave hitches).
        -- While capped the timer holds at 0 so deaths don't trigger a burst.
        local alive = liveEnemies(world)
        if alive >= TUNE.waves.maxAlive then
            self.spawnTimer = math.max(self.spawnTimer, 0)
        end
        while self.remaining > 0 and self.spawnTimer <= 0
            and alive < TUNE.waves.maxAlive do
            self:spawnOne(world)
            alive = alive + 1
            self.remaining = self.remaining - 1
            self.spawnTimer = self.spawnTimer + delayFor(self.wave)
        end

        -- wave 0 never ends: free roam until a chat command moves it on
        if self.wave > 0 and self.remaining == 0 and liveEnemies(world) == 0 then
            self.state = 'wave_end'
            self.timer = TUNE.waves.endIntermission
            self:slamBanner()
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
