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

local Lantest = {}

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
    Session.startRun()
    log('STARTED state=%s', Session.state)
    pump(1) -- let START reach the client before we tear the socket down

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

    Session.leave()
    log('PASS client')
    os.exit(0)
end

return Lantest
