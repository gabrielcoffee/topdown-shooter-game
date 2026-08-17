-- Gameplay replication: what turns two lobbies into one game.
--
-- Host-authoritative, full rate, no prediction. Clients send their 16-byte
-- input struct 60 times a second and draw whatever comes back; the host runs
-- the only real simulation there is and broadcasts it 60 times a second. LAN
-- round-trip is ~1ms against a 16.7ms frame, so there is no latency to hide
-- and none of the machinery you would need to hide it -- no interpolation, no
-- rollback, no reconciliation. See the note in TUNE.net.
--
-- Snapshots are ABSOLUTE, never deltas. Every one carries the whole live
-- world, so a dropped packet costs one frame and fixes itself on the next
-- rather than leaving the client permanently wrong. That is what buys the
-- right to send them unreliably.
--
-- Two rates, because the costs are wildly different:
--   * every frame: players and zombies -- the things that move
--   * every propsEvery-th frame: crates, chests, ground loot, fire, doors --
--     the things that sit still for seconds at a time
--
-- Entity identity is Entity.netId, stamped at construction (entities/entity.lua)
-- and until now unused. Clients never mint their own for a replicated type:
-- the counter is module-wide, so a locally-built zombie would collide with a
-- host id sooner or later.
--
-- One-shot cosmetics (a shot fired, a zombie dying, a door coming open) ride
-- an event channel instead of the snapshot -- they are instants, not state,
-- and a snapshot can only ever say "this is gone now", which is not enough to
-- know where to put the blood.

local Protocol = require('net.protocol')
local Transport = require('net.transport')

local Rep = {}

-- net/session.lua requires this file to dispatch into it, so the reference
-- back has to be lazy or the two never finish loading
local function Session() return require('net.session') end

Rep.role = nil      -- 'host' | 'client' | nil (solo: everything here is inert)
Rep.slot = nil      -- our slot in the session roster
Rep.tick = 0

local inputAccum, snapAccum = 0, 0
local snapCount = 0
local byNetId = {}      -- client: netId -> entity, rebuilt as snapshots arrive
local seen = {}         -- client: scratch set of netIds present this snapshot
local eventBuf = {}     -- host: cosmetic events queued this frame

-- How many snapshots between full props sections. 6 at 60Hz = ten a second,
-- which is far more often than a crate moves.
local PROPS_EVERY = 6

-- Positions go on the wire as quarter-pixels in a uint16. The map's bounding
-- box is 3200x1344, so the largest value is 12800 -- comfortably inside the
-- range, and a quarter of a world pixel is an eighth of a screen pixel at
-- SCALE 2, well under anything an eye can find.
local POS = 4

-- Wire enums. Order IS the format: appending is safe, reordering or removing
-- is not, and either way Protocol.VERSION has to go up with it.
local ZKIND  = { 'slow', 'normal', 'fast' }
local GUNID  = { 'usp', 'ak47', 'm4a1', 'shotgun' }
local PUKIND = { 'nuke', 'maxammo', 'instakill', 'freeze', 'doublepoints',
                 'firesale', 'carpenter' }
local WSTATE = { 'pregame', 'wave_start', 'active', 'wave_end' }
local BUFFS  = { 'instakill', 'freeze', 'doublepoints', 'firesale' }

local function indexOf(list)
    local t = {}
    for i, v in ipairs(list) do t[v] = i end
    return t
end
local ZIDX, GIDX, PIDX, WIDX = indexOf(ZKIND), indexOf(GUNID),
                               indexOf(PUKIND), indexOf(WSTATE)

-- cosmetic one-shots
Rep.EV = { SHOT = 1, KILL = 2, HIT = 3, DOOR = 4, POWERUP = 5, MELEE = 6 }

-- ------------------------------------------------------------------ helpers

function Rep.isHost()   return Rep.role == 'host' end
function Rep.isClient() return Rep.role == 'client' end
function Rep.active()   return Rep.role ~= nil end

local function wpos(w, x, y)
    w:u16(math.max(0, x) * POS)
    w:u16(math.max(0, y) * POS)
end

local function rpos(r)
    local x, y = r:u16(), r:u16()
    if x == nil or y == nil then return 0, 0 end
    return x / POS, y / POS
end

-- pack a list of booleans into one byte, in order
local function bits(...)
    local v, n = 0, select('#', ...)
    for i = 1, n do
        if select(i, ...) then v = v + 2 ^ (i - 1) end
    end
    return v
end

local function bit(v, i) return math.floor(v / 2 ^ (i - 1)) % 2 == 1 end

-- ------------------------------------------------------------------ session

function Rep.begin(role, slot)
    Rep.role, Rep.slot = role, slot
    Rep.tick, inputAccum, snapAccum, snapCount = 0, 0, 0, 0
    byNetId, eventBuf = {}, {}
end

function Rep.stop()
    Rep.role, Rep.slot = nil, nil
    byNetId, eventBuf = {}, {}
end

-- ------------------------------------------------------------- host: events

-- Queued rather than sent immediately so a frame's worth share one packet:
-- a shotgun blast is 14 pellets and a nuke is 60 deaths, and that many tiny
-- reliable sends would cost more than the snapshot they ride next to.
function Rep.event(kind, ...)
    if Rep.role ~= 'host' then return end
    eventBuf[#eventBuf + 1] = { kind = kind, n = select('#', ...), ... }
end

local function flushEvents()
    if #eventBuf == 0 then return end
    local w = Protocol.writer(Protocol.MSG.EVENT)
    w:u8(math.min(#eventBuf, 255))
    for i = 1, math.min(#eventBuf, 255) do
        local e = eventBuf[i]
        w:u8(e.kind)
        if e.kind == Rep.EV.SHOT then
            w:u8(e[1])            -- slot
            wpos(w, e[2], e[3])   -- muzzle
            w:f32(e[4])           -- angle
            w:u8(GIDX[e[5]] or 0) -- gun id
        elseif e.kind == Rep.EV.KILL or e.kind == Rep.EV.HIT then
            wpos(w, e[1], e[2])
            w:f32(e[3])           -- impact angle, for the splatter
        elseif e.kind == Rep.EV.DOOR then
            w:str(e[1])           -- door id: an LDtk string, stable everywhere
        elseif e.kind == Rep.EV.POWERUP then
            w:u8(PIDX[e[1]] or 0)
            w:u8(e[2] or 0)       -- picker slot
        elseif e.kind == Rep.EV.MELEE then
            wpos(w, e[1], e[2])
            w:f32(e[3])
        end
    end
    for i = #eventBuf, 1, -1 do eventBuf[i] = nil end
    Session().send(Transport.CHAN.EVENT, w:build(), 'reliable')
end

-- ---------------------------------------------------------- host: snapshot

local function writeWaves(w, waves)
    w:u16(waves.wave or 1)
    w:u8(WIDX[waves.state] or 1)
    w:f32(waves.timer or 0)
    w:u16(math.max(0, waves.remaining or 0))
    w:f32(waves.spawnTimer or 0)
    w:u8(waves.carriersThisWave or 0)
    w:u8(waves.pendingWave or 1)
    w:bool(waves.clearedNightmare)
end

local function writePlayer(w, p, slot)
    w:u8(slot)
    wpos(w, p.x, p.y)
    w:i16(p.vx or 0)
    w:i16(p.vy or 0)
    w:u8(math.max(0, math.min(255, math.floor(p.health + 0.5))))
    w:u8(bits(p.facingLeft, p.running, p.downed, p.dead, p.falling,
              p.flying, (p.invulnTimer or 0) > 0, p.healing ~= nil))
    w:u8(math.max(0, math.min(255, math.ceil(p.bleed or 0))))
    -- revive hold as a 0-255 fraction: the bar only needs to look right
    local rk = p.reviving and (p.reviving / TUNE.revive.reviveTime) or 0
    w:u8(math.max(0, math.min(255, math.floor(rk * 255))))
    w:u32(math.max(0, math.floor(p.money or 0)))
    w:u32(math.max(0, math.floor(p.earnedTotal or 0)))
    w:u8(p.itemIndex or 1)
    w:u8(p.grenades or 0)
    w:u8(p.molotovs or 0)
    w:u8(p.medkits or 0)
    w:u8(p.throwableType == 'molotov' and 2 or 1)
    for i = 1, 2 do
        local g = p.items[i]
        w:u8(g and (GIDX[g.id] or 0) or 0)
        w:u8(g and math.min(255, g.curClip or 0) or 0)
        w:u16(g and math.min(65535, g.bulletsLeft or 0) or 0)
    end
end

local function writeProps(w, world)
    local crates, chests, guns, pus, fires = {}, {}, {}, {}, {}
    for _, e in ipairs(world.entities) do
        if e.toRemove then -- gone this frame, not part of the picture
        elseif e.type == 'crate' then crates[#crates + 1] = e
        elseif e.type == 'chest' then chests[#chests + 1] = e
        elseif e.type == 'dropped_gun' then guns[#guns + 1] = e
        elseif e.type == 'powerup' then pus[#pus + 1] = e
        elseif e.type == 'fire_patch' then fires[#fires + 1] = e
        end
    end

    w:u16(#crates)
    for _, e in ipairs(crates) do
        w:u16(e.netId); wpos(w, e.x, e.y); w:u16(math.max(0, e.health))
    end
    w:u8(#chests)
    for _, e in ipairs(chests) do
        w:u16(e.netId)
        wpos(w, e.x, e.y)
        w:str(e.state or 'idle')
        w:f32(e.timer or 0)
        w:f32(e.takeTimer or 0)
        w:str(e.result and (e.result.kind or '') or '')
        w:str(e.result and (e.result.gunId or '') or '')
    end
    w:u8(#guns)
    for _, e in ipairs(guns) do
        w:u16(e.netId); wpos(w, e.x, e.y)
        w:u8(GIDX[e.gun.id] or 0)
        w:u8(math.min(255, e.gun.curClip or 0))
        w:u16(math.min(65535, e.gun.bulletsLeft or 0))
        w:f32(e.life or 0)
    end
    w:u8(#pus)
    for _, e in ipairs(pus) do
        local cx, cy = e:getCenter()
        w:u16(e.netId); wpos(w, cx, cy)
        w:u8(PIDX[e.kind] or 0); w:f32(e.life or 0)
    end
    w:u8(#fires)
    for _, e in ipairs(fires) do
        local cx, cy = e:getCenter()
        w:u16(e.netId); wpos(w, cx, cy); w:f32(e.age or 0)
    end
end

-- Every snapshot carries a tick one higher than the last. Clients drop
-- anything not newer than what they already applied, which is what makes it
-- safe to send these unreliably and out of order.
function Rep.buildSnapshot(world, withProps)
    Rep.tick = Rep.tick + 1
    local w = Protocol.writer(Protocol.MSG.SNAPSHOT)
    w:u32(Rep.tick)
    w:u16(math.min(65535, world.kills or 0))
    w:bool(world.gameOver)
    w:bool(world.cheated)
    for _, k in ipairs(BUFFS) do w:f32(world.buffs[k] or 0) end
    writeWaves(w, world.waves)

    local np = 0
    for _ in ipairs(world.players) do np = np + 1 end
    w:u8(np)
    for i, p in ipairs(world.players) do writePlayer(w, p, p.netSlot or i) end

    local zs = {}
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and e.health > 0 then
            zs[#zs + 1] = e
        end
    end
    w:u16(#zs)
    for _, e in ipairs(zs) do
        w:u16(e.netId)
        w:u8(ZIDX[e.kind] or 2)
        wpos(w, e.x, e.y)
        w:i16(e.vx or 0)
        w:i16(e.vy or 0)
        w:u16(math.max(0, math.min(65535, math.floor(e.health))))
        w:u8(PIDX[e.carrier] or 0)
    end

    w:bool(withProps)
    if withProps then writeProps(w, world) end
    return w:build()
end

-- --------------------------------------------------------- client: applying

local Enemy, DroppedGun, Powerup, FirePatch, Gun

local function lazyRequires()
    Enemy = Enemy or require('entities.enemy')
    DroppedGun = DroppedGun or require('entities.dropped_gun')
    Powerup = Powerup or require('entities.powerup')
    FirePatch = FirePatch or require('entities.fire_patch')
    Gun = Gun or require('hand_items.gun')
end

-- netId -> live entity, rebuilt lazily. world.entities is a flat array with
-- no index of its own, and scanning it per record would be O(n^2) against a
-- 60-zombie wave.
local function reindex(world)
    for k in pairs(byNetId) do byNetId[k] = nil end
    for _, e in ipairs(world.entities) do
        if e.netId then byNetId[e.netId] = e end
    end
end

local function applyWaves(r, world)
    local wv = world.waves
    local wave = r:u16()
    local state = WSTATE[r:u8() or 1] or 'pregame'
    local timer = r:f32()
    local remaining = r:u16()
    local spawnTimer = r:f32()
    local carriers = r:u8()
    local pendingWave = r:u8()
    local cleared = r:bool()
    if not r:ok() then return end

    -- a new wave or a new phase is what slams the banner down; the host does
    -- it inside startWave, and this is the client's equivalent trigger
    if wave ~= wv.wave or state ~= wv.state then
        if state == 'wave_start' or state == 'wave_end' then wv:slamBanner() end
    end
    wv.wave, wv.state, wv.timer = wave, state, timer
    wv.remaining, wv.spawnTimer = remaining, spawnTimer
    wv.carriersThisWave, wv.pendingWave = carriers, pendingWave
    wv.clearedNightmare = cleared
end

local function applyPlayer(r, world)
    local slot = r:u8()
    local x, y = rpos(r)
    local vx, vy = r:i16(), r:i16()
    local health = r:u8()
    local fl = r:u8()
    local bleed = r:u8()
    local revive = r:u8()
    local money, earned = r:u32(), r:u32()
    local itemIndex = r:u8()
    local grenades, molotovs, medkits, throwable = r:u8(), r:u8(), r:u8(), r:u8()
    local guns = {}
    for i = 1, 2 do
        guns[i] = { id = GUNID[r:u8() or 0], clip = r:u8(), reserve = r:u16() }
    end
    if not r:ok() or not slot then return end

    local p = world.netBySlot and world.netBySlot[slot]
    if not p then
        -- a player we have not seen: everyone but us is added on demand, so
        -- a mid-run joiner needs no separate message to become visible
        if slot == Rep.slot then
            p = world.player
        else
            p = world:addPlayer(x, y)
            if not p then return end
        end
        p.netSlot = slot
        world.netBySlot = world.netBySlot or {}
        world.netBySlot[slot] = p
        local s = Session().players[slot]
        p.netName = s and s.name or nil
    end

    p.x, p.y, p.vx, p.vy = x, y, vx, vy
    p.health = health
    p.facingLeft = bit(fl, 1)
    p.running    = bit(fl, 2)
    p.downed     = bit(fl, 3)
    p.dead       = bit(fl, 4)
    p.falling    = bit(fl, 5)
    p.flying     = bit(fl, 6)
    p.invulnTimer = bit(fl, 7) and math.max(p.invulnTimer or 0, 0.1) or 0
    p.healing    = bit(fl, 8) and (p.healing or TUNE.healthpack.useTime) or nil
    p.bleed = bleed
    p.reviving = revive > 0 and (revive / 255) * TUNE.revive.reviveTime or nil
    p.money, p.earnedTotal = money, earned
    p.grenades, p.molotovs, p.medkits = grenades, molotovs, medkits
    p.throwableType = (throwable == 2) and 'molotov' or 'grenade'

    for i = 1, 2 do
        local g = guns[i]
        if g.id then
            if not p.items[i] or p.items[i].id ~= g.id then
                p.items[i] = Gun.newById(g.id)
                p.items[i].owner = p
            end
            p.items[i].curClip = g.clip
            p.items[i].bulletsLeft = g.reserve
        else
            p.items[i] = nil
        end
    end
    if itemIndex and p.items[itemIndex] ~= nil or itemIndex == 3
        or itemIndex == 4 or itemIndex == 5 then
        p.itemIndex = itemIndex
    end
end

local function applyZombies(r, world)
    local n = r:u16()
    if not n or not r:ok() then return end
    for k in pairs(seen) do seen[k] = nil end

    for _ = 1, n do
        local netId = r:u16()
        local kind = ZKIND[r:u8() or 2] or 'normal'
        local x, y = rpos(r)
        local vx, vy = r:i16(), r:i16()
        local health = r:u16()
        local carrier = PUKIND[r:u8() or 0]
        if not r:ok() then return end

        seen[netId] = true
        local e = byNetId[netId]
        if not e or e.type ~= 'enemy' then
            e = Enemy.fromSave({ kind = kind, x = x, y = y,
                                 health = health, carrier = carrier },
                               world.waves.wave or 1)
            e.netId = netId -- the host's id wins; ours is thrown away
            world:addEntity(e)
            byNetId[netId] = e
        end
        e.x, e.y, e.vx, e.vy = x, y, vx, vy
        e.health = health
        e.carrier = carrier
    end

    -- anything the host no longer lists is gone. The blood and the sound
    -- came from a KILL event; this is just the bookkeeping.
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and not seen[e.netId] then
            if e.growlSrc then e.growlSrc:stop() end
            e.toRemove = true
            byNetId[e.netId] = nil
        end
    end
end

local function applyProps(r, world)
    lazyRequires()
    local live = {}

    local nc = r:u16() or 0
    for _ = 1, nc do
        local netId, x, y = r:u16(), nil, nil
        x, y = rpos(r)
        local hp = r:u16()
        if not r:ok() then return end
        live[netId] = true
        local e = byNetId[netId]
        if e and e.type == 'crate' then
            e.x, e.y, e.health = x, y, hp
        end
        -- a crate the client does not have is one the map built differently;
        -- rebuilding geometry mid-run is the carpenter's job, not a prop sync
    end

    local nch = r:u8() or 0
    for _ = 1, nch do
        local netId = r:u16()
        local x, y = rpos(r)
        local state, timer, takeTimer = r:str(), r:f32(), r:f32()
        local kind, gunId = r:str(), r:str()
        if not r:ok() then return end
        live[netId] = true
        local e = byNetId[netId]
        if e and e.type == 'chest' then
            e.state, e.timer, e.takeTimer = state, timer, takeTimer
            if kind ~= '' then
                e.result = { kind = kind, gunId = gunId ~= '' and gunId or nil }
                if e.result.gunId then
                    e.result.name = Gun.names[e.result.gunId] or e.result.gunId
                end
            else
                e.result = nil
            end
        end
    end

    local ng = r:u8() or 0
    for _ = 1, ng do
        local netId = r:u16()
        local x, y = rpos(r)
        local gunId, clip, reserve, life = GUNID[r:u8() or 0], r:u8(), r:u16(), r:f32()
        if not r:ok() then return end
        live[netId] = true
        local e = byNetId[netId]
        if not e and gunId then
            local gun = Gun.newById(gunId)
            if gun then
                gun.curClip, gun.bulletsLeft = clip, reserve
                e = DroppedGun:new(x, y, gun)
                e.netId = netId
                world:addEntity(e)
                byNetId[netId] = e
            end
        end
        if e and e.type == 'dropped_gun' then e.x, e.y, e.life = x, y, life end
    end

    local np = r:u8() or 0
    for _ = 1, np do
        local netId = r:u16()
        local x, y = rpos(r)
        local kind, life = PUKIND[r:u8() or 0], r:f32()
        if not r:ok() then return end
        live[netId] = true
        local e = byNetId[netId]
        if not e and kind then
            e = Powerup:new(x, y, kind)
            e.netId = netId
            world:addEntity(e)
            byNetId[netId] = e
        end
        if e and e.type == 'powerup' then e.life = life end
    end

    local nf = r:u8() or 0
    for _ = 1, nf do
        local netId = r:u16()
        local x, y = rpos(r)
        local age = r:f32()
        if not r:ok() then return end
        live[netId] = true
        local e = byNetId[netId]
        if not e then
            e = FirePatch:new(x, y)
            e.netId = netId
            world:addEntity(e)
            byNetId[netId] = e
        end
        if e and e.type == 'fire_patch' then e.age = age end
    end

    -- ground loot and fire the host has stopped listing has expired
    for _, e in ipairs(world.entities) do
        if not e.toRemove and not live[e.netId]
            and (e.type == 'dropped_gun' or e.type == 'powerup'
                 or e.type == 'fire_patch') then
            e.toRemove = true
            byNetId[e.netId] = nil
        end
    end
end

function Rep.applySnapshot(r, world)
    world = world or _G.world
    if not world or Rep.role ~= 'client' then return end
    lazyRequires()

    local tick = r:u32()
    if not tick then return end
    -- unreliable channel: an older snapshot arriving after a newer one would
    -- drag the world backwards
    if Rep.lastTick and tick <= Rep.lastTick then return end
    Rep.lastTick = tick

    world.kills = r:u16() or world.kills
    world.gameOver = r:bool()
    world.cheated = r:bool()
    for _, k in ipairs(BUFFS) do world.buffs[k] = r:f32() or 0 end
    applyWaves(r, world)
    if not r:ok() then return end

    reindex(world)

    local np = r:u8() or 0
    for _ = 1, np do
        applyPlayer(r, world)
        if not r:ok() then return end
    end

    applyZombies(r, world)
    if not r:ok() then return end

    if r:bool() then applyProps(r, world) end
end

-- ----------------------------------------------------------- client: events

function Rep.applyEvent(r, world)
    world = world or _G.world
    if not world then return end
    lazyRequires()
    local Audio = require('core.audio')
    local Bullet = require('entities.bullet')

    local n = r:u8() or 0
    for _ = 1, n do
        local kind = r:u8()
        if not r:ok() then return end

        if kind == Rep.EV.SHOT then
            local slot = r:u8()
            local x, y = rpos(r)
            local angle = r:f32()
            local gunId = GUNID[r:u8() or 0]
            if not r:ok() then return end
            if gunId then
                local p = world.netBySlot and world.netBySlot[slot]
                local proto = Gun.newById(gunId)
                Audio.playAt(gunId .. '_shot', x, y, 1, TUNE.audio.pitchJitter, world)
                world.vfx:muzzleSparks(x, y, angle)
                local mb = TUNE.lighting.muzzleBright
                world.lighting:flash(x, y, mb, mb * 0.8, mb * 0.45,
                    TUNE.lighting.muzzleRange, TUNE.lighting.muzzleTime)
                -- One event per trigger pull, not per pellet: a shotgun blast
                -- is 14 bullets and the cone is pure decoration on this
                -- machine, so the client rolls its own rather than paying 14x
                -- the bandwidth to see the host's exact scatter.
                local pellets = (proto and proto.pellets) or 1
                for i = 1, pellets do
                    local a = angle
                    if pellets > 1 then
                        a = a + (love.math.random() * 2 - 1) * proto.spread
                    end
                    local b = Bullet:new(x, y, a, 0, 0,
                        proto and proto.bulletLifeTime or 0.5, nil, 1, i == 1, p)
                    world:addEntity(b)
                end
            end

        elseif kind == Rep.EV.KILL then
            local x, y = rpos(r)
            local angle = r:f32()
            if not r:ok() then return end
            world.vfx:bloodSplatter(x, y, angle)
            world.decals:add(x, y)
            Audio.playAt('flesh_hit', x, y, 1, TUNE.audio.pitchJitter, world)

        elseif kind == Rep.EV.HIT then
            local x, y = rpos(r)
            local angle = r:f32()
            if not r:ok() then return end
            world.vfx:bloodSplatter(x, y, angle)

        elseif kind == Rep.EV.MELEE then
            local x, y = rpos(r)
            local angle = r:f32()
            if not r:ok() then return end
            world.vfx:bloodSplatter(x, y, angle)
            Audio.playAt('knife_hit', x, y, 1, TUNE.audio.pitchJitter, world)

        elseif kind == Rep.EV.DOOR then
            local id = r:str()
            if not r:ok() then return end
            for _, e in ipairs(world.entities) do
                if e.type == 'door' and e.id == id and not e.toRemove then
                    world:openDoor(e)
                    break
                end
            end

        elseif kind == Rep.EV.POWERUP then
            local pk = PUKIND[r:u8() or 0]
            r:u8() -- picker slot, informational
            if not r:ok() then return end
            if pk then
                world.pickupToast = { text = T('powerup.' .. pk), t = 2 }
                Audio.play('spin_wheel', 0.5)
            end
        end
    end
end

-- ------------------------------------------------------ host: the roster

-- Give a connected slot a body in the world. Called for everyone already in
-- the lobby when the run starts, and again for anyone who joins mid-run.
function Rep.hostAddPlayer(slot, world)
    world = world or _G.world
    if not world or Rep.role ~= 'host' or slot == Rep.slot then return end
    world.netBySlot = world.netBySlot or {}
    if world.netBySlot[slot] then return world.netBySlot[slot] end

    -- drop in next to whoever is still standing, not at the map's start room:
    -- a joiner landing three rooms behind the group is a joiner walking
    -- through everything the group already cleared
    local anchor = world:upPlayers()[1] or world.player
    local p = world:addPlayer(anchor.x + 24, anchor.y)
    if not p then return end
    p.netSlot = slot
    p.currentRoom = anchor.currentRoom
    world:snapCamera(p)
    world.netBySlot[slot] = p
    local s = Session().players[slot]
    p.netName = s and s.name or nil
    return p
end

function Rep.hostRemovePlayer(slot, world)
    world = world or _G.world
    if not world or not world.netBySlot then return end
    local p = world.netBySlot[slot]
    if not p then return end
    world.netBySlot[slot] = nil
    world:removePlayer(p)
end

-- Everyone in the lobby gets a body the moment the run starts.
function Rep.hostSeedPlayers(world)
    if Rep.role ~= 'host' then return end
    for slot in pairs(Session().players) do
        Rep.hostAddPlayer(slot, world)
    end
end

-- --------------------------------------------------------------- host inbox

-- A client's input packet, written straight into that player's struct.
function Rep.hostInput(slot, data, world)
    world = world or _G.world
    if not world or Rep.role ~= 'host' then return end
    local p = world.netBySlot and world.netBySlot[slot]
    if not p then return end
    Protocol.unpackInput(data, p.input)
end

-- --------------------------------------------------------------- the pump

-- Called from states/playing every frame, AFTER world:update. Everything the
-- network does in a run happens here.
function Rep.update(dt, world)
    if Rep.role == nil then return end

    if Rep.role == 'client' then
        inputAccum = inputAccum + dt
        local period = 1 / (TUNE.net.inputRate or 60)
        if inputAccum >= period then
            inputAccum = inputAccum % period
            Session().send(Transport.CHAN.SNAPSHOT,
                Protocol.packInput(world.player.input), 'unreliable')
        end
        return
    end

    -- host
    flushEvents()
    snapAccum = snapAccum + dt
    local period = 1 / (TUNE.net.snapshotRate or 60)
    if snapAccum < period then return end
    snapAccum = snapAccum % period

    snapCount = snapCount + 1
    local withProps = (snapCount % PROPS_EVERY) == 0
    Session().send(Transport.CHAN.SNAPSHOT,
        Rep.buildSnapshot(world, withProps), 'unreliable')
end

return Rep
