-- LAN game discovery: a host shouts a small UDP record onto the network every
-- second, browsers listen and build the server list. Plain LuaSocket, not
-- ENet -- ENet has no notion of "who is out there".
--
-- macOS is fussy here, and all of this was verified by hand before it was
-- written:
--   * setsockname('0.0.0.0', port) works; ('*', 0) does not
--   * setoption('broadcast', true) only works AFTER binding
--   * sending to 255.255.255.255 fails outright with "No route to host",
--     so the subnet address (10.0.0.255) has to be derived and used instead
--   * loopback works, so two copies on one machine can find each other

local socket = require('socket')
local Protocol = require('net.protocol')

local Discovery = {}

local host = nil     -- { sock, info, timer, id }
local browser = nil  -- { sock, found = { hostId -> entry } }

-- Our address on the LAN. Connecting a UDP socket sends nothing; it just asks
-- the routing table which interface would be used to reach the outside world.
local function localIP()
    local probe = socket.udp()
    if not probe then return nil end
    probe:setpeername('8.8.8.8', 53)
    local ip = probe:getsockname()
    probe:close()
    if ip == '0.0.0.0' then return nil end
    return ip
end

-- 10.0.0.209 -> 10.0.0.255. Assumes a /24, which every home and office LAN
-- this will ever run on uses.
local function broadcastAddr(ip)
    if not ip then return nil end
    return (ip:gsub('%.%d+$', '.255'))
end

function Discovery.localIP() return localIP() end

-- ------------------------------------------------------------------- host

-- info: { name, players, maxPlayers, state, port }
function Discovery.startHost(info)
    Discovery.stopHost()
    local sock = socket.udp()
    if not sock then return false, 'no UDP socket' end
    -- bind first: broadcast cannot be enabled on an unbound socket
    if not sock:setsockname('0.0.0.0', 0) then
        sock:close()
        return false, 'could not bind the beacon socket'
    end
    sock:settimeout(0)
    sock:setoption('broadcast', true)

    host = {
        sock = sock,
        info = info or {},
        timer = 0,
        -- random enough to tell two hosts apart for the lifetime of a session
        id = tostring(love.math.random(1, 2^30)) .. '-' .. tostring(os.time()),
        bcast = broadcastAddr(localIP()),
    }
    Discovery.beacon() -- answer immediately, don't make browsers wait a second
    return true
end

function Discovery.stopHost()
    if host and host.sock then host.sock:close() end
    host = nil
end

function Discovery.hosting() return host ~= nil end

-- Keep the advertised roster fresh without restarting the beacon
function Discovery.setInfo(info)
    if host then host.info = info end
end

function Discovery.beacon()
    if not host then return end
    local info = host.info
    local payload = Protocol.packBeacon({
        hostId = host.id,
        name = info.name,
        players = info.players,
        maxPlayers = info.maxPlayers or TUNE.net.maxPlayers,
        state = info.state,
        port = info.port or TUNE.net.gamePort,
    })
    -- the subnet address reaches the LAN; loopback covers a second copy on
    -- this same machine, which is how most testing actually happens
    if host.bcast then host.sock:sendto(payload, host.bcast, TUNE.net.beaconPort) end
    host.sock:sendto(payload, '127.0.0.1', TUNE.net.beaconPort)
end

-- ---------------------------------------------------------------- browser

function Discovery.startBrowsing()
    Discovery.stopBrowsing()
    local sock = socket.udp()
    if not sock then return false, 'no UDP socket' end
    -- two copies of the game on one machine both want this port
    sock:setoption('reuseaddr', true)
    if not sock:setsockname('0.0.0.0', TUNE.net.beaconPort) then
        sock:close()
        return false, ('beacon port %d is busy'):format(TUNE.net.beaconPort)
    end
    sock:settimeout(0)
    browser = { sock = sock, found = {} }
    return true
end

function Discovery.stopBrowsing()
    if browser and browser.sock then browser.sock:close() end
    browser = nil
end

function Discovery.browsing() return browser ~= nil end

-- Sorted list of live hosts for the server browser UI
function Discovery.list()
    if not browser then return {} end
    local out = {}
    for _, e in pairs(browser.found) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if a.name == b.name then return a.hostId < b.hostId end
        return (a.name or '') < (b.name or '')
    end)
    return out
end

function Discovery.update(dt)
    if host then
        host.timer = host.timer - dt
        if host.timer <= 0 then
            host.timer = TUNE.net.beaconInterval
            Discovery.beacon()
        end
    end

    if browser then
        -- drain whatever arrived; foreign traffic on this port is ignored
        while true do
            local data, ip = browser.sock:receivefrom()
            if not data then break end
            local info = Protocol.unpackBeacon(data)
            if info and info.hostId and info.version == Protocol.VERSION then
                local prev = browser.found[info.hostId]
                info.ip = (prev and prev.ip) or ip -- first address wins, stays stable
                info.lastSeen = love.timer.getTime()
                browser.found[info.hostId] = info
            end
        end
        -- a host that went quiet drops off the list
        local now = love.timer.getTime()
        for id, e in pairs(browser.found) do
            if now - e.lastSeen > TUNE.net.beaconTimeout then
                browser.found[id] = nil
            end
        end
    end
end

function Discovery.shutdown()
    Discovery.stopHost()
    Discovery.stopBrowsing()
end

return Discovery
