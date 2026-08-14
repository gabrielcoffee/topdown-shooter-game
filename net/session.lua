-- The LAN session: who is connected, what state the group is in, and the
-- message handling that keeps a lobby in sync. Sits above net/transport and
-- net/discovery; the UI (states/multiplayer, states/lobby) only talks to this.
--
-- Phase 2 scope is the lobby: connect, roster, ready, start. Gameplay
-- replication (snapshots, events, voice) hangs off the same poll loop in
-- phase 3.

local Transport = require('net.transport')
local Discovery = require('net.discovery')
local Protocol = require('net.protocol')
local Name = require('core.name')

local Session = {}

Session.state = 'offline' -- offline | hosting | joining | lobby | playing
Session.role = nil        -- 'host' | 'client'
Session.players = {}      -- slot -> { slot, name, ready, isHost, peer }
Session.localSlot = nil
Session.voiceMode = 'global' -- 'global' | 'proximity', host's choice
Session.errorKey = nil    -- i18n key of whatever went wrong last
Session.onStart = nil     -- UI sets this; fired when the run begins

local transport = nil
local joinTimer = 0

-- ------------------------------------------------------------------ roster

local function rosterCount()
    local n = 0
    for _ in pairs(Session.players) do n = n + 1 end
    return n
end

local function takenNames(exceptSlot)
    local t = {}
    for slot, p in pairs(Session.players) do
        if slot ~= exceptSlot then t[p.name] = true end
    end
    return t
end

local function freeSlot()
    for i = 1, TUNE.net.maxPlayers do
        if not Session.players[i] then return i end
    end
end

local function playerByPeer(peer)
    for _, p in pairs(Session.players) do
        if p.peer == peer then return p end
    end
end

function Session.roster()
    local out = {}
    for i = 1, TUNE.net.maxPlayers do out[i] = Session.players[i] end
    return out
end

function Session.count() return rosterCount() end
function Session.isHost() return Session.role == 'host' end
function Session.active() return Session.state ~= 'offline' end
function Session.localPlayer() return Session.players[Session.localSlot] end

function Session.everyoneReady()
    local any = false
    for _, p in pairs(Session.players) do
        if not p.isHost and not p.ready then return false end
        any = true
    end
    return any
end

-- ------------------------------------------------------------- host -> all

local function sendLobby()
    if Session.role ~= 'host' or not transport then return end
    local w = Protocol.writer(Protocol.MSG.LOBBY)
    w:u8(rosterCount())
    for i = 1, TUNE.net.maxPlayers do
        local p = Session.players[i]
        if p then
            w:u8(p.slot)
            w:str(p.name)
            w:bool(p.ready)
            w:bool(p.isHost)
        end
    end
    w:u8(Session.voiceMode == 'proximity' and 1 or 0)
    transport:broadcast(Transport.CHAN.EVENT, w:build(), 'reliable')
end

local function refreshBeacon()
    if Session.role ~= 'host' then return end
    Discovery.setInfo({
        name = (Session.players[1] and Session.players[1].name) or Name.get(),
        players = rosterCount(),
        maxPlayers = TUNE.net.maxPlayers,
        state = Session.state == 'playing' and 'playing' or 'lobby',
        port = TUNE.net.gamePort,
    })
end

-- ------------------------------------------------------------------ start

function Session.startHost()
    Session.leave()
    local t, err = Transport.host(TUNE.net.gamePort)
    if not t then
        Session.errorKey = 'net.err_listen'
        return false, err
    end
    transport = t
    Session.role = 'host'
    Session.state = 'lobby'
    Session.localSlot = 1
    Session.players = {
        [1] = { slot = 1, name = Name.get(), ready = true, isHost = true },
    }
    Discovery.startHost({
        name = Session.players[1].name,
        players = 1, maxPlayers = TUNE.net.maxPlayers,
        state = 'lobby', port = TUNE.net.gamePort,
    })
    return true
end

function Session.join(ip, port)
    Session.leave()
    local t, err = Transport.join(ip, port or TUNE.net.gamePort)
    if not t then
        Session.errorKey = 'net.err_connect'
        return false, err
    end
    transport = t
    Session.role = 'client'
    Session.state = 'joining'
    Session.players = {}
    Session.localSlot = nil
    joinTimer = TUNE.net.connectTimeout
    return true
end

function Session.leave()
    if transport then
        if Session.state ~= 'offline' then
            local w = Protocol.writer(Protocol.MSG.BYE)
            transport:broadcast(Transport.CHAN.EVENT, w:build(), 'reliable')
        end
        transport:close()
    end
    transport = nil
    Discovery.stopHost()
    Session.state = 'offline'
    Session.role = nil
    Session.players = {}
    Session.localSlot = nil
end

function Session.setReady(v)
    local me = Session.localPlayer()
    if Session.role == 'host' then
        if me then me.ready = v end
        sendLobby()
        return
    end
    if not transport then return end
    local w = Protocol.writer(Protocol.MSG.READY)
    w:bool(v)
    transport:broadcast(Transport.CHAN.EVENT, w:build(), 'reliable')
end

function Session.setVoiceMode(mode)
    if Session.role ~= 'host' then return end
    Session.voiceMode = (mode == 'proximity') and 'proximity' or 'global'
    sendLobby()
end

-- Host only. Everyone jumps into the run together.
function Session.startRun()
    if Session.role ~= 'host' or not transport then return false end
    Session.state = 'playing'
    refreshBeacon()
    local w = Protocol.writer(Protocol.MSG.START)
    transport:broadcast(Transport.CHAN.EVENT, w:build(), 'reliable')
    if Session.onStart then Session.onStart() end
    return true
end

-- ------------------------------------------------------------- host inbox

local function hostHandle(event)
    local id = Protocol.msgId(event.data)
    local r = Protocol.reader(event.data)
    r:u8()

    if id == Protocol.MSG.HELLO then
        local version = r:u8()
        local wanted = r:str()
        if not r:ok() then return end

        local function reject(code)
            local w = Protocol.writer(Protocol.MSG.REJECT)
            w:u8(code)
            transport:send(event.peer, Transport.CHAN.EVENT, w:build(), 'reliable')
        end

        if version ~= Protocol.VERSION then return reject(Protocol.REJECT.VERSION) end
        local slot = freeSlot()
        if not slot then return reject(Protocol.REJECT.FULL) end
        local valid, clean = Name.validate(wanted)
        if not valid then
            clean = Name.sanitize(wanted)
            if not clean then return reject(Protocol.REJECT.BAD_NAME) end
        end
        clean = Name.dedupe(clean, takenNames())

        Session.players[slot] = {
            slot = slot, name = clean, ready = false,
            isHost = false, peer = event.peer,
        }

        local w = Protocol.writer(Protocol.MSG.WELCOME)
        w:u8(slot)
        w:str(clean)
        w:u8(TUNE.net.maxPlayers)
        w:bool(Session.state == 'playing')
        transport:send(event.peer, Transport.CHAN.EVENT, w:build(), 'reliable')

        sendLobby()
        refreshBeacon()

    elseif id == Protocol.MSG.READY then
        local p = playerByPeer(event.peer)
        if p then
            p.ready = r:bool()
            sendLobby()
        end

    elseif id == Protocol.MSG.BYE then
        local p = playerByPeer(event.peer)
        if p then
            Session.players[p.slot] = nil
            sendLobby()
            refreshBeacon()
        end
    end
end

-- ----------------------------------------------------------- client inbox

local function clientHandle(event)
    local id = Protocol.msgId(event.data)
    local r = Protocol.reader(event.data)
    r:u8()

    if id == Protocol.MSG.WELCOME then
        local slot = r:u8()
        local name = r:str()
        r:u8() -- maxPlayers, informational
        local alreadyPlaying = r:bool()
        if not r:ok() then return end
        Session.localSlot = slot
        Session.state = alreadyPlaying and 'playing' or 'lobby'
        Session.errorKey = nil
        -- the host may have renamed us (collision or sanitising)
        if name and name ~= '' then Session.assignedName = name end
        if alreadyPlaying and Session.onStart then Session.onStart() end

    elseif id == Protocol.MSG.REJECT then
        local code = r:u8()
        Session.errorKey = Protocol.rejectText[code] or 'net.err_connect'
        Session.leave()

    elseif id == Protocol.MSG.LOBBY then
        local n = r:u8() or 0
        local players = {}
        for _ = 1, n do
            local slot = r:u8()
            local name = r:str()
            local ready = r:bool()
            local isHost = r:bool()
            if not r:ok() then return end
            players[slot] = { slot = slot, name = name, ready = ready, isHost = isHost }
        end
        local proximity = r:u8()
        if not r:ok() then return end
        Session.players = players
        Session.voiceMode = (proximity == 1) and 'proximity' or 'global'

    elseif id == Protocol.MSG.START then
        Session.state = 'playing'
        if Session.onStart then Session.onStart() end

    elseif id == Protocol.MSG.BYE then
        Session.errorKey = 'net.err_host_left'
        Session.leave()
    end
end

-- ------------------------------------------------------------------- pump

function Session.update(dt)
    Discovery.update(dt)
    if not transport then return end

    if Session.state == 'joining' then
        joinTimer = joinTimer - dt
        if joinTimer <= 0 then
            Session.errorKey = 'net.err_timeout'
            Session.leave()
            return
        end
    end

    for _, event in ipairs(transport:poll()) do
        if event.type == 'connect' then
            if Session.role == 'client' then
                -- the socket is up; now ask to be let in
                local w = Protocol.writer(Protocol.MSG.HELLO)
                w:u8(Protocol.VERSION)
                w:str(Name.get())
                transport:broadcast(Transport.CHAN.EVENT, w:build(), 'reliable')
            end

        elseif event.type == 'disconnect' then
            if Session.role == 'host' then
                local p = playerByPeer(event.peer)
                if p then
                    Session.players[p.slot] = nil
                    sendLobby()
                    refreshBeacon()
                end
            else
                Session.errorKey = 'net.err_host_left'
                Session.leave()
                return
            end

        elseif event.type == 'receive' then
            if Session.role == 'host' then hostHandle(event) else clientHandle(event) end
            if not transport then return end -- a REJECT tore the session down
        end
    end
end

-- debug overlay numbers
function Session.stats()
    if not transport then return nil end
    return {
        bytesIn = transport.bytesIn, bytesOut = transport.bytesOut,
        peers = transport:peerCount(), rtt = transport:rtt(),
    }
end

return Session
