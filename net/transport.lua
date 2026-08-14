-- ENet wrapper. The only file in the game that touches `enet` -- everything
-- above it deals in peers, channels and byte strings.
--
-- ENet gives UDP plus optional per-message reliability and independent
-- channels, which is exactly the mix a game wants: positions can be dropped
-- (a newer one is already on the way), "you bought the door" cannot, and a
-- stalled reliable message on one channel must not hold up another.

local enet = require('enet')

local Transport = {}
Transport.__index = Transport

-- Channel assignment. Three, because the reliability needs genuinely differ.
Transport.CHAN = {
    EVENT    = 0, -- reliable: doors, pickups, kills, chat, join/leave
    SNAPSHOT = 1, -- unreliable: world state, newest always wins
    VOICE    = 2, -- unreliable: PCM chunks, a dropped one is a click
}
local CHANNEL_COUNT = 3

local function new(enetHost, role)
    return setmetatable({
        -- deliberately NOT called `host`: Transport.host is the constructor, so a
        -- nil `self.host` would silently resolve to that function through the
        -- metatable and index a function instead of failing
        enet = enetHost,
        role = role,       -- 'host' | 'client'
        peers = {},        -- peer -> true (host only)
        serverPeer = nil,  -- the host's peer (client only)
        bytesIn = 0,
        bytesOut = 0,
    }, Transport)
end

-- Listen on every interface. nil + message on failure (port already taken is
-- the usual one: a second copy of the game on the same machine).
function Transport.host(port)
    port = port or TUNE.net.gamePort
    local ok, h = pcall(enet.host_create,
        '0.0.0.0:' .. port, TUNE.net.maxPlayers, CHANNEL_COUNT)
    if not ok or not h then
        return nil, ('could not listen on port %d (in use?)'):format(port)
    end
    return new(h, 'host')
end

-- Client side. The connection is not established yet when this returns --
-- poll() delivers a 'connect' event once the handshake lands, or nothing at
-- all if the address is dead (the caller times out on TUNE.net.connectTimeout).
function Transport.join(ip, port)
    port = port or TUNE.net.gamePort
    local ok, h = pcall(enet.host_create) -- ephemeral local port
    if not ok or not h then
        return nil, 'could not open a local socket'
    end
    local ok2, peer = pcall(h.connect, h, ip .. ':' .. port, CHANNEL_COUNT)
    if not ok2 or not peer then
        return nil, ('could not reach %s:%d'):format(ip, port)
    end
    local t = new(h, 'client')
    t.serverPeer = peer
    return t
end

local MODE = { reliable = 'reliable', unreliable = 'unreliable' }

function Transport:send(peer, chan, data, mode)
    if not peer or not data then return false end
    local ok = pcall(peer.send, peer, data, chan, MODE[mode] or 'unreliable')
    if ok then self.bytesOut = self.bytesOut + #data end
    return ok
end

-- Host: to everyone. Client: to the host (the only peer it has).
function Transport:broadcast(chan, data, mode)
    if not data then return end
    if self.role == 'client' then
        return self:send(self.serverPeer, chan, data, mode)
    end
    pcall(self.enet.broadcast, self.enet, data, chan, MODE[mode] or 'unreliable')
    self.bytesOut = self.bytesOut + #data * self:peerCount()
end

-- Everyone except one peer (relaying a client's chat or voice onward)
function Transport:broadcastExcept(skip, chan, data, mode)
    for peer in pairs(self.peers) do
        if peer ~= skip then self:send(peer, chan, data, mode) end
    end
end

function Transport:peerCount()
    local n = 0
    for _ in pairs(self.peers) do n = n + 1 end
    return n
end

-- Drain everything waiting this frame. Returns a list of
-- { type = 'connect' | 'disconnect' | 'receive', peer, data, channel }.
-- service(0) never blocks, so this is safe to call every frame.
function Transport:poll()
    local out = {}
    if not self.enet then return out end
    while true do
        local ok, event = pcall(self.enet.service, self.enet, 0)
        if not ok or not event then break end

        if event.type == 'connect' then
            if self.role == 'host' then self.peers[event.peer] = true end
        elseif event.type == 'disconnect' then
            if self.role == 'host' then self.peers[event.peer] = nil end
        elseif event.type == 'receive' then
            self.bytesIn = self.bytesIn + #event.data
        end
        out[#out + 1] = event
    end
    return out
end

-- Round-trip time to a peer in ms, for the debug overlay
function Transport:rtt(peer)
    peer = peer or self.serverPeer
    if not peer then return 0 end
    local ok, v = pcall(peer.round_trip_time, peer)
    return ok and v or 0
end

-- Ask peers to close politely; poll() a few more frames to let it land
function Transport:disconnect()
    if self.role == 'client' and self.serverPeer then
        pcall(self.serverPeer.disconnect, self.serverPeer)
    else
        for peer in pairs(self.peers) do pcall(peer.disconnect, peer) end
    end
    if self.enet then pcall(self.enet.flush, self.enet) end
end

function Transport:close()
    self:disconnect()
    if self.enet then pcall(self.enet.destroy, self.enet) end
    self.enet, self.peers, self.serverPeer = nil, {}, nil
end

return Transport
