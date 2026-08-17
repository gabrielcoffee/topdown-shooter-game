-- Two-process LAN test. net/session.lua is a singleton (the UI treats it as
-- one), so a host and a client cannot both live in one LÖVE instance -- this
-- is driven by launching the game twice:
--
--   love . lanhost          # waits for a client, prints what it sees
--   love . lanjoin 127.0.0.1
--
-- Both print machine-readable lines to stderr and exit 0 on success, 1 on
-- timeout. tools/lantest.sh runs the pair and checks the output.

local Session = require('net.session')
local Discovery = require('net.discovery')
local State = require('core.state')

local Lantest = {}

-- How many zombies the host plants once the run is up. The client asserts it
-- sees exactly this many, which is the whole point of the exercise: a number
-- that only exists on the other machine.
local PLANTED = 5

local function log(fmt, ...)
    io.stderr:write('LAN ' .. string.format(fmt, ...) .. '\n')
    io.stderr:flush()
end

local function rosterLine()
    local parts = {}
    for _, p in ipairs(Session.roster()) do
        parts[#parts + 1] = ('%d:%s:%s%s'):format(
            p.slot, p.name, p.ready and 'ready' or 'notready', p.isHost and ':host' or '')
    end
    return table.concat(parts, ',')
end

-- Pump the session at a fixed step until `done` returns true or we run out
-- of patience. Returns whether `done` fired.
local function pump(seconds, done)
    local dt = 1/60
    local deadline = love.timer.getTime() + seconds
    local lastRoster = nil
    while love.timer.getTime() < deadline do
        Session.update(dt)
        local line = rosterLine()
        if line ~= lastRoster then
            lastRoster = line
            log('ROSTER %s', line)
        end
        if done and done() then return true end
        love.timer.sleep(dt)
    end
    return false
end

-- Same as pump, but also ticks the game state, so a live run actually
-- simulates and net/replication.lua gets its per-frame turn.
local function pumpRun(seconds, done, each)
    local dt = 1/60
    local deadline = love.timer.getTime() + seconds
    while love.timer.getTime() < deadline do
        Session.update(dt)
        State.update(dt)
        if each then each() end
        if done and done() then return true end
        love.timer.sleep(dt)
    end
    return false
end

local function countZombies()
    local n = 0
    for _, e in ipairs((world and world.entities) or {}) do
        if e.type == 'enemy' and not e.toRemove then n = n + 1 end
    end
    return n
end

-- Both sides enter the run the same way the lobby does it.
local function enterRun()
    Session.onStart = function()
        State.switch('playing', {
            multiplayer = true,
            role = Session.isHost() and 'host' or 'client',
            slot = Session.localSlot,
        })
    end
end

function Lantest.host(seconds)
    seconds = seconds or 20
    local ok, err = Session.startHost()
    if not ok then
        log('FAIL could not host: %s', tostring(err))
        os.exit(1)
    end
    log('HOSTING port=%d name=%s ip=%s',
        TUNE.net.gamePort, Session.players[1].name, tostring(Discovery.localIP()))

    -- wait for a client to join AND mark itself ready
    local joined = pump(seconds, function()
        local p = Session.players[2]
        return p ~= nil and p.ready
    end)
    if not joined then
        log('FAIL no client joined and readied in %ds', seconds)
        Session.leave()
        os.exit(1)
    end
    log('CLIENT_READY name=%s slot=%d', Session.players[2].name, Session.players[2].slot)

    -- everyone ready -> start the run, then confirm we moved state
    enterRun()
    Session.startRun()
    log('STARTED state=%s', Session.state)

    -- the run is up on both machines now. Everything past here is testing
    -- replication rather than the lobby.
    pumpRun(1)
    if not world then
        log('FAIL host never built a world')
        Session.leave()
        os.exit(1)
    end
    if #world.players ~= 2 then
        log('FAIL host world has %d players, expected 2', #world.players)
        Session.leave()
        os.exit(1)
    end
    log('HOST_WORLD players=%d slot=%d', #world.players, Session.localSlot)

    -- plant a known number of zombies at known spots. The client has no way
    -- to know about any of them except through a snapshot.
    local Enemy = require('entities.enemy')
    local px, py = world.player.x, world.player.y
    for i = 1, PLANTED do
        world:addEntity(Enemy:newSlow(px + 80 + i * 24, py + 40, 1))
    end
    log('PLANTED n=%d', PLANTED)

    -- Move, so the client has a position CHANGE to follow rather than an
    -- initial placement it could have guessed. Driving this through the input
    -- struct does not work here: states/playing calls Input.poll every frame,
    -- which reads a keyboard nobody is touching and clears the button again.
    -- Walking the player directly is the same thing as far as the wire is
    -- concerned -- a position that differs from one snapshot to the next.
    local startX = world.player.x
    pumpRun(2, nil, function() world.player.x = world.player.x + 1 end)
    log('HOST_MOVED from=%.1f to=%.1f zombies=%d',
        startX, world.player.x, countZombies())
    if world.player.x - startX < 30 then
        log('FAIL host player did not actually move')
        Session.leave()
        os.exit(1)
    end

    pumpRun(1)
    Session.leave()
    log('PASS host')
    os.exit(0)
end

function Lantest.join(ip, seconds)
    seconds = seconds or 20
    ip = ip or '127.0.0.1'

    -- the browser should see the host's beacon before we even connect
    Discovery.startBrowsing()
    local sawBeacon = false
    local deadline = love.timer.getTime() + 8
    while love.timer.getTime() < deadline do
        Discovery.update(1/60)
        local list = Discovery.list()
        if #list > 0 then
            sawBeacon = true
            log('DISCOVERED name=%s players=%d/%d state=%s ip=%s port=%d',
                list[1].name, list[1].players, list[1].maxPlayers,
                list[1].state, tostring(list[1].ip), list[1].port)
            break
        end
        love.timer.sleep(1/60)
    end
    if not sawBeacon then log('WARN no beacon seen, joining by address anyway') end

    local ok, err = Session.join(ip, TUNE.net.gamePort)
    if not ok then
        log('FAIL could not join: %s', tostring(err))
        os.exit(1)
    end

    -- wait to be admitted
    local admitted = pump(seconds, function() return Session.state == 'lobby' end)
    if not admitted then
        log('FAIL never admitted (state=%s err=%s)',
            Session.state, tostring(Session.errorKey))
        os.exit(1)
    end
    log('ADMITTED slot=%d name=%s', Session.localSlot,
        tostring(Session.assignedName))

    -- the host must have told us about itself, not just about us
    local sawHost = false
    for _, p in ipairs(Session.roster()) do
        if p.isHost then sawHost = true end
    end
    log('SAW_HOST %s', tostring(sawHost))

    enterRun()
    Session.setReady(true)
    log('READY_SENT')

    -- host starts the run once it sees us ready
    local started = pump(seconds, function() return Session.state == 'playing' end)
    if not started then
        log('FAIL run never started (state=%s)', Session.state)
        Session.leave()
        os.exit(1)
    end
    log('PLAYING voice=%s', Session.voiceMode)

    -- ------------------------------------------------- replication proper
    local built = pumpRun(5, function() return world ~= nil end)
    if not built or not world then
        log('FAIL client never built a world')
        Session.leave()
        os.exit(1)
    end
    if world.authoritative then
        log('FAIL client world thinks it is authoritative')
        Session.leave()
        os.exit(1)
    end
    log('CLIENT_WORLD authoritative=%s slot=%d',
        tostring(world.authoritative), Session.localSlot)

    -- the host's player has to appear here, and it is not one we made
    local sawHostPlayer = pumpRun(5, function() return #world.players >= 2 end)
    if not sawHostPlayer then
        log('FAIL only %d player(s) in the client world after 5s', #world.players)
        Session.leave()
        os.exit(1)
    end
    log('SYNCED_PLAYERS n=%d', #world.players)

    -- and so do the zombies the host planted, which exist nowhere else
    local sawZombies = pumpRun(6, function() return countZombies() >= PLANTED end)
    log('SYNCED_ZOMBIES n=%d want=%d', countZombies(), PLANTED)
    if not sawZombies then
        log('FAIL zombies never replicated')
        Session.leave()
        os.exit(1)
    end

    -- follow the host's player moving: a position that changes over time is
    -- proof the snapshots are still arriving, not just the first one
    local other
    for _, p in ipairs(world.players) do
        if p ~= world.player then other = p end
    end
    local x0 = other and other.x or 0
    pumpRun(2)
    local x1 = other and other.x or 0
    log('SYNCED_MOVE dx=%.1f', x1 - x0)
    if math.abs(x1 - x0) < 8 then
        log('FAIL the host player never moved on this machine')
        Session.leave()
        os.exit(1)
    end

    Session.leave()
    log('PASS client')
    os.exit(0)
end

return Lantest
