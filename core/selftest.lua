-- Scripted gameplay checks: `love . selftest`. Drives a real World through
-- the input struct (core/input.lua) instead of the keyboard, so the whole
-- player input path is exercised without a human at the controls.
--
-- This is the regression gate for the input refactor: the autotest screenshot
-- modes prove the game draws, this proves it still responds.

local Selftest = {}

local checks, fails = 0, 0

local function ok(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.stderr:write('FAIL: ' .. msg .. '\n')
        io.stderr:flush()
    end
end

-- Progress marker: successful checks are silent, so without these a hang
-- anywhere in the run looks identical to a hang on the first line.
local function section(name)
    io.stderr:write('-- ' .. name .. '\n')
    io.stderr:flush()
end

-- Run the world forward n frames at a fixed step
local function step(world, n)
    for _ = 1, (n or 1) do world:update(1/60) end
end

local function freshWorld()
    local World = require('core.world')
    local w = World:new({})
    _G.world = w -- chat commands and a few HUD reads still go through the global
    -- the run normally opens with a wave banner hold; skip it so zombies and
    -- timers behave like mid-run
    step(w, 2)
    return w
end

function Selftest.run()
    local Input = require('core.input')

    -- ================================================== wire format (no world)
    section("wire format")
    local Protocol = require('net.protocol')

    local w = Protocol.writer(Protocol.MSG.HELLO)
    w:u8(7); w:u16(4242); w:i16(-1234); w:u32(4000000000)
    w:f32(12.5); w:bool(true); w:bool(false); w:str('coffeebreak')
    local packed = w:build()
    ok(Protocol.msgId(packed) == Protocol.MSG.HELLO, 'message id reads back')

    local r = Protocol.reader(packed)
    ok(r:u8() == Protocol.MSG.HELLO, 'reader: id')
    ok(r:u8() == 7, 'reader: u8')
    ok(r:u16() == 4242, 'reader: u16')
    ok(r:i16() == -1234, 'reader: i16 keeps the sign')
    ok(r:u32() == 4000000000, 'reader: u32 past 2^31')
    ok(math.abs(r:f32() - 12.5) < 1e-6, 'reader: f32')
    ok(r:bool() == true and r:bool() == false, 'reader: bools')
    ok(r:str() == 'coffeebreak', 'reader: string')
    ok(r:ok(), 'reader reports no failure')

    -- a truncated packet must fail closed, not throw
    local trunc = Protocol.reader(packed:sub(1, 4))
    trunc:u8(); trunc:u8(); trunc:u16(); trunc:u32(); trunc:str()
    ok(not trunc:ok(), 'truncated packet fails closed instead of erroring')
    ok(Protocol.msgId('') == nil, 'empty packet has no id')

    -- input round-trip: this is the packet a client sends 60x a second
    local src = Input.new()
    src.seq, src.aimX, src.aimY = 900001, -123.5, 4096.25
    src.up, src.shoot, src.slot3, src.typing = true, true, true, true
    local wire = Protocol.packInput(src)
    ok(#wire == 16, ('input packet is 16 bytes, got %d'):format(#wire))
    local got = Protocol.unpackInput(wire)
    ok(got ~= nil, 'input unpacked')
    ok(got.seq == src.seq, 'input: seq survives')
    ok(got.up and got.shoot and got.slot3, 'input: pressed buttons survive')
    ok(not got.down and not got.reload and not got.slot1, 'input: unpressed stay false')
    ok(got.typing == true, 'input: typing flag survives')
    ok(math.abs(got.aimX - src.aimX) < 0.01
        and math.abs(got.aimY - src.aimY) < 0.01, 'input: aim survives')

    -- every button must round-trip, not just the three above
    local allSet = Input.new()
    for _, b in ipairs(Input.buttons) do allSet[b] = true end
    local back = Protocol.unpackInput(Protocol.packInput(allSet))
    local everyBit = true
    for _, b in ipairs(Input.buttons) do
        if not back[b] then everyBit = false end
    end
    ok(everyBit, 'input: all ' .. #Input.buttons .. ' buttons round-trip')

    -- beacon record
    local beacon = Protocol.packBeacon({
        name = 'Notch', players = 2, maxPlayers = 4, state = 'playing', port = 23471 })
    local info = Protocol.unpackBeacon(beacon)
    ok(info ~= nil, 'beacon parsed')
    ok(info.name == 'Notch' and info.players == 2 and info.maxPlayers == 4,
        'beacon: roster fields')
    ok(info.state == 'playing' and info.port == 23471, 'beacon: state and port')
    ok(Protocol.unpackBeacon(Protocol.packBeacon({ hostId = 'abc123' })).hostId == 'abc123',
        'beacon: hostId identifies a host across addresses')
    ok(Protocol.unpackBeacon('garbage') == nil, 'foreign UDP traffic is ignored')
    ok(Protocol.unpackBeacon(nil) == nil, 'nil beacon is ignored')

    -- ---------------------------------------------------------------- move
    section("movement")
    local world = freshWorld()
    local p = world.player
    local inp = p.input

    local x0 = p.x
    inp.right = true
    step(world, 30)
    ok(p.x > x0 + 1, ('move right moved the player (x %.1f -> %.1f)'):format(x0, p.x))

    local x1 = p.x
    inp.right = false
    step(world, 30)
    ok(math.abs(p.vx) < 1, ('releasing right decelerates (vx %.2f)'):format(p.vx))
    ok(p.x >= x1, 'no backwards drift after release')

    -- diagonal must not outrun a straight line
    inp.right, inp.down = true, true
    step(world, 30)
    local diagSpeed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    inp.right, inp.down = false, false
    step(world, 30)
    inp.right = true
    step(world, 30)
    local straightSpeed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    inp.right = false
    ok(math.abs(diagSpeed - straightSpeed) < 2,
        ('diagonal speed matches straight (%.1f vs %.1f)'):format(diagSpeed, straightSpeed))

    -- ------------------------------------------------------------- typing
    section("typing gate")
    world = freshWorld()
    p, inp = world.player, world.player.input
    Input.clear(inp)
    step(world, 10)
    local tx = p.x
    inp.right, inp.typing = true, true
    step(world, 30)
    ok(math.abs(p.x - tx) < 0.5, 'chat focus blocks movement')
    inp.typing = false
    step(world, 20)
    ok(p.x > tx + 1, 'movement resumes once chat closes')

    -- -------------------------------------------------------------- slots
    section("slots")
    world = freshWorld()
    p, inp = world.player, world.player.input
    ok(p.itemIndex == 1, 'starts on slot 1')
    inp.slot3 = true
    step(world, 2)
    ok(p.itemIndex == 3, 'slot3 selects the knife, got ' .. tostring(p.itemIndex))
    inp.slot3 = false
    step(world, 2)

    -- a held slot key must not re-select every frame
    p:selectSlot(1)
    local switchAfter = p.switchTimer
    inp.slot1 = true
    step(world, 10)
    ok(p.switchTimer <= switchAfter, 'holding a slot key does not re-deploy')
    inp.slot1 = false

    -- quick-knife toggles and comes back
    world = freshWorld()
    p, inp = world.player, world.player.input
    inp.quickknife = true
    step(world, 2)
    ok(p.itemIndex == 3, 'quickknife draws the knife')
    inp.quickknife = false
    step(world, 2)
    inp.quickknife = true
    step(world, 2)
    ok(p.itemIndex == 1, 'quickknife swaps back to the gun')
    inp.quickknife = false

    -- -------------------------------------------------------------- shoot
    section("shooting")
    world = freshWorld()
    p, inp = world.player, world.player.input
    local gun = p.items[1]
    p:selectSlot(1)
    step(world, 30) -- clear the deploy lockout
    local clip0 = gun.curClip
    local pcx, pcy = p:getCenter()
    inp.aimX, inp.aimY = pcx + 200, pcy
    inp.shoot = true
    step(world, 2)
    ok(gun.curClip == clip0 - 1,
        ('shoot fired one round (clip %d -> %d)'):format(clip0, gun.curClip))

    -- a bullet actually entered the world
    local bullets = 0
    for _, e in ipairs(world.entities) do
        if e.type == 'bullet' then bullets = bullets + 1 end
    end
    ok(bullets > 0, 'firing spawned a bullet entity')
    inp.shoot = false

    -- ------------------------------------------------------- locked input
    section("locked input")
    -- a button already held when the world spawns must not act until released
    world = freshWorld()
    p, inp = world.player, world.player.input
    p:selectSlot(1)
    step(world, 30)
    p.lockedInputs.shoot = true
    local clipL = p.items[1].curClip
    inp.shoot = true
    step(world, 5)
    ok(p.items[1].curClip == clipL, 'locked shoot does not fire')
    inp.shoot = false
    step(world, 2)
    ok(p.lockedInputs.shoot == nil, 'lock clears once the button is released')
    inp.shoot = true
    step(world, 2)
    ok(p.items[1].curClip == clipL - 1, 'fires again after the lock cleared')
    inp.shoot = false

    -- ------------------------------------------------------------- reload
    section("reload")
    world = freshWorld()
    p, inp = world.player, world.player.input
    p:selectSlot(1)
    step(world, 30)
    local g = p.items[1]
    g.curClip = 1
    inp.reload = true
    step(world, 2)
    ok(g.reloading or g.reloadTimer and g.reloadTimer > 0 or g.curClip > 1,
        'reload key started a reload')
    inp.reload = false

    -- --------------------------------------------------------------- aim
    section("aim")
    world = freshWorld()
    p, inp = world.player, world.player.input
    local cx, cy = p:getCenter()
    inp.aimX, inp.aimY = cx - 300, cy
    step(world, 2)
    ok(p.facingLeft == true, 'aiming left faces the player left')
    inp.aimX = cx + 300
    step(world, 2)
    ok(p.facingLeft == false, 'aiming right faces the player right')

    -- ==================================================== co-op groundwork
    section("co-op groundwork")
    -- Everything below runs with a second player in world.players, which is
    -- exactly the shape LAN co-op produces.

    local Enemy = require('entities.enemy')

    -- ------------------------------------------------- players / nearest
    section("players/nearest")
    world = freshWorld()
    local p1 = world.player
    local p2 = world:addPlayer(p1.x + 400, p1.y)
    ok(p2 ~= nil, 'addPlayer returned a player')
    ok(#world.players == 2, 'two players in the world')
    ok(world.player == p1, 'world.player still points at the local player')
    ok(p1.netId ~= p2.netId, 'players got distinct netIds')

    local c1x, c1y = p1:getCenter()
    ok(world:nearestPlayer(c1x, c1y) == p1, 'nearestPlayer picks the close one')
    local c2x, c2y = p2:getCenter()
    ok(world:nearestPlayer(c2x, c2y) == p2, 'nearestPlayer picks the other one')

    -- ------------------------------------------------------ run-over rule
    section("run-over rule")
    ok(world:anyoneAlive(), 'both alive')
    p1.health = 0
    step(world, 2)
    ok(world:anyoneAlive(), 'one player down is not a game over')
    ok(not world.gameOver, 'gameOver stays false with a survivor')
    ok(world:nearestPlayer(c1x, c1y) == p2, 'a downed player is not a target')
    p2.health = 0
    step(world, 2)
    ok(world.gameOver, 'last player down ends the run')

    -- --------------------------------------------------- money goes to the
    section("money attribution")
    -- shooter, not to whoever happens to be player 1
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 400, p1.y)
    local z = Enemy:newSlow(p2.x + 60, p2.y, 1)
    world:addEntity(z)
    local m1, m2 = p1.money, p2.money
    z:takeDamage(1, world, { hitReward = 10, killBonus = 0 }, p2)
    ok(p2.money == m2 + 10, ('shooter was paid (%d -> %d)'):format(m2, p2.money))
    ok(p1.money == m1, 'the other player was not paid')

    -- a nil attacker still pays someone (solo, environmental)
    z:takeDamage(1, world, { hitReward = 5, killBonus = 0 }, nil)
    ok(p1.money == m1 + 5, 'nil attacker falls back to the local player')

    -- ------------------------------------------------- zombies pick a target
    section("zombie targeting")
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 600, p1.y)
    local near = Enemy:newSlow(p2.x - 40, p2.y, 1)
    world:addEntity(near)
    step(world, 4)
    ok(near.target == p2, 'zombie chases the nearest player, not player 1')

    -- -------------------------------------------- independent room/cameras
    section("cameras")
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 200, p1.y)
    step(world, 4)
    ok(p1.camX ~= nil and p2.camX ~= nil, 'both players have a camera')
    ok(world.camX == p1.camX, 'world camera mirrors the local player')

    -- --------------------------------------------- freeze rules per mode
    section("freeze rules")
    -- helper: park a zombie next to the player and force a camera pan
    local function panWithZombie(w, p)
        local z2 = Enemy:newSlow(p.x + 120, p.y + 120, 1)
        w:addEntity(z2)
        step(w, 4)
        p.transition = {
            t = 0, room = p.currentRoom,
            fromCamX = p.camX, fromCamY = p.camY,
            toCamX = p.camX + 50, toCamY = p.camY,
            playerFromX = p.x, playerFromY = p.y,
            nudgeX = TUNE.rooms.nudgePx, nudgeY = 0,
        }
        return z2, z2.x, z2.y
    end

    -- SOLO: the world still freezes, and the player still drifts into the room
    world = freshWorld()
    p1 = world.player
    ok(not world:isMultiplayer(), 'one player = singleplayer rules')
    ok(world:transitionTime() == TUNE.rooms.transitionTime,
        'solo pan runs at the full transitionTime')
    local zom, zx, zy = panWithZombie(world, p1)
    local pxBefore = p1.x
    step(world, 6)
    ok(zom.x == zx and zom.y == zy,
        'solo: world freezes during the pan, zombies hold still')
    ok(p1.x > pxBefore, 'solo: player still drifts into the new room')

    -- CO-OP: no freeze, and the pan is coopTimeMult as long
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 400, p1.y)
    ok(world:isMultiplayer(), 'two players = multiplayer rules')
    ok(math.abs(world:transitionTime()
        - TUNE.rooms.transitionTime * TUNE.rooms.coopTimeMult) < 1e-9,
        ('co-op pan is %gx as long'):format(TUNE.rooms.coopTimeMult))
    zom, zx, zy = panWithZombie(world, p1)
    step(world, 6)
    ok(zom.x ~= zx or zom.y ~= zy,
        'co-op: zombies keep moving while a camera pans')

    -- and it actually finishes in the shorter time
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 400, p1.y)
    panWithZombie(world, p1)
    local coopFrames = math.ceil(world:transitionTime() * 60) + 2
    step(world, coopFrames)
    ok(p1.transition == nil, 'co-op pan completed inside the shortened window')

    -- ------------------------------------------------ real room transition
    section("room transition")
    -- the pan was rewritten to run per player without freezing the world, so
    -- walking into another room still has to actually change rooms
    world = freshWorld()
    p1 = world.player
    local other
    for _, r in ipairs(world.rooms) do
        if r ~= p1.currentRoom then other = r break end
    end
    if other then
        local startRoom = p1.currentRoom
        -- drop the player into the middle of another room and let the check run
        p1.x, p1.y = other.x + other.w/2 - p1.width/2, other.y + other.h/2 - p1.height/2
        step(world, 2)
        ok(p1.transition ~= nil or p1.currentRoom == other,
            'entering another room starts a transition')
        step(world, math.ceil(TUNE.rooms.transitionTime * 60) + 6)
        ok(p1.currentRoom == other,
            ('transition completed into the new room (%s -> %s)')
                :format(startRoom.name, p1.currentRoom.name))
        ok(p1.transition == nil, 'transition cleared when it finished')
        ok(world.visitedRooms[other.name] == true, 'the new room is marked visited')
        local wantX, wantY = world:cameraFor(other, p1:getCenter())
        ok(math.abs(p1.camX - wantX) < 1 and math.abs(p1.camY - wantY) < 1,
            'camera settled on the new room')
    else
        io.stderr:write('NOTE: map has one room, transition test skipped\n')
    end

    -- ============================================== ENet over the loopback
    -- A host and a client in this same process, talking over 127.0.0.1. This
    -- is the closest thing to a real session that fits in an automated run --
    -- it exercises connect, both reliability modes, all three channels and a
    -- clean disconnect.
    section("enet loopback")
    do
        local Transport = require('net.transport')
        local Protocol = require('net.protocol')

        -- a port nobody else is on, so a real session running alongside the
        -- test cannot make it flap
        local PORT = TUNE.net.gamePort + 7

        local host, herr = Transport.host(PORT)
        ok(host ~= nil, 'host started: ' .. tostring(herr))

        if host then
            local client, cerr = Transport.join('127.0.0.1', PORT)
            ok(client ~= nil, 'client socket opened: ' .. tostring(cerr))

            -- pump both sides until `done` says so, or we give up
            local function pump(seconds, done)
                local deadline = love.timer.getTime() + seconds
                local hostEvents, clientEvents = {}, {}
                while love.timer.getTime() < deadline do
                    for _, e in ipairs(host:poll()) do hostEvents[#hostEvents+1] = e end
                    if client then
                        for _, e in ipairs(client:poll()) do clientEvents[#clientEvents+1] = e end
                    end
                    if done and done(hostEvents, clientEvents) then break end
                    love.timer.sleep(0.002)
                end
                return hostEvents, clientEvents
            end

            local function firstOf(events, kind)
                for _, e in ipairs(events) do if e.type == kind then return e end end
            end

            -- handshake
            local hEvents, cEvents = pump(3, function(h, c)
                return firstOf(h, 'connect') and firstOf(c, 'connect')
            end)
            local hConnect = firstOf(hEvents, 'connect')
            ok(hConnect ~= nil, 'host saw the client connect')
            ok(firstOf(cEvents, 'connect') ~= nil, 'client saw the host accept')
            ok(host:peerCount() == 1, 'host tracks exactly one peer')

            if hConnect then
                local peer = hConnect.peer

                -- reliable, on the event channel
                local hello = Protocol.writer(Protocol.MSG.HELLO)
                hello:str('coffeebreak')
                client:broadcast(Transport.CHAN.EVENT, hello:build(), 'reliable')

                local got = pump(2, function(h)
                    return firstOf(h, 'receive') ~= nil
                end)
                local rx = firstOf(got, 'receive')
                ok(rx ~= nil, 'host received the reliable packet')
                if rx then
                    ok(rx.channel == Transport.CHAN.EVENT, 'arrived on the event channel')
                    ok(Protocol.msgId(rx.data) == Protocol.MSG.HELLO, 'message id intact')
                    local rr = Protocol.reader(rx.data)
                    rr:u8()
                    ok(rr:str() == 'coffeebreak', 'payload intact over the wire')
                end

                -- unreliable, on the snapshot channel, host -> client
                local snap = Protocol.writer(Protocol.MSG.SNAPSHOT)
                snap:u16(1234)
                host:send(peer, Transport.CHAN.SNAPSHOT, snap:build(), 'unreliable')

                local _, cGot = pump(2, function(_, c)
                    return firstOf(c, 'receive') ~= nil
                end)
                local crx = firstOf(cGot, 'receive')
                ok(crx ~= nil, 'client received the unreliable snapshot')
                if crx then
                    ok(crx.channel == Transport.CHAN.SNAPSHOT, 'arrived on the snapshot channel')
                    local sr = Protocol.reader(crx.data)
                    sr:u8()
                    ok(sr:u16() == 1234, 'snapshot payload intact')
                end

                -- an input packet over the real wire, the 60Hz path
                local sent = Input.new()
                sent.seq, sent.aimX, sent.aimY = 42, 10.5, -20.25
                sent.left, sent.reload = true, true
                client:broadcast(Transport.CHAN.SNAPSHOT,
                    Protocol.packInput(sent), 'unreliable')
                local hGot2 = pump(2, function(h)
                    for _, e in ipairs(h) do
                        if e.type == 'receive'
                            and Protocol.msgId(e.data) == Protocol.MSG.INPUT then return true end
                    end
                end)
                local inputRx
                for _, e in ipairs(hGot2) do
                    if e.type == 'receive' and Protocol.msgId(e.data) == Protocol.MSG.INPUT then
                        inputRx = e
                    end
                end
                ok(inputRx ~= nil, 'input packet crossed the wire')
                if inputRx then
                    local back = Protocol.unpackInput(inputRx.data)
                    ok(back and back.seq == 42 and back.left and back.reload
                        and not back.right, 'input survived the round trip')
                end

                ok(host.bytesIn > 0 and host.bytesOut > 0, 'host counted traffic both ways')
            end

            -- clean shutdown: the host must be told, not just time out
            client:close()
            local hBye = pump(2, function(h) return firstOf(h, 'disconnect') ~= nil end)
            ok(firstOf(hBye, 'disconnect') ~= nil, 'host saw a clean disconnect')
            ok(host:peerCount() == 0, 'peer dropped from the roster')

            host:close()
        end
    end

    -- =========================================== LAN discovery over UDP
    -- Real sockets, real broadcast. macOS refuses 255.255.255.255 and refuses
    -- SO_BROADCAST before bind, so this is the check that the recipe in
    -- net/discovery.lua is actually the working one.
    section("lan discovery")
    do
        local Discovery = require('net.discovery')

        local ip = Discovery.localIP()
        io.stderr:write('   local ip: ' .. tostring(ip) .. '\n')

        local browsing, berr = Discovery.startBrowsing()
        ok(browsing == true, 'browser bound the beacon port: ' .. tostring(berr))

        local hosted, herr = Discovery.startHost({
            name = 'Notch', players = 2, maxPlayers = 4,
            state = 'lobby', port = TUNE.net.gamePort,
        })
        ok(hosted == true, 'host started beaconing: ' .. tostring(herr))
        ok(Discovery.hosting() and Discovery.browsing(), 'both sides report running')

        -- give the beacon a moment to loop back around
        local deadline = love.timer.getTime() + 2
        while love.timer.getTime() < deadline do
            Discovery.update(1/60)
            if #Discovery.list() > 0 then break end
            love.timer.sleep(0.01)
        end

        local list = Discovery.list()
        ok(#list >= 1, ('browser found the host (%d entries)'):format(#list))
        if list[1] then
            ok(list[1].name == 'Notch', 'discovered name is right')
            ok(list[1].players == 2 and list[1].maxPlayers == 4, 'discovered roster')
            ok(list[1].state == 'lobby', 'discovered state')
            ok(list[1].port == TUNE.net.gamePort, 'discovered game port')
            ok(list[1].ip ~= nil, 'discovered address: ' .. tostring(list[1].ip))
        end
        -- one host must not appear twice just because it answered on both
        -- loopback and the LAN address
        ok(#list == 1, ('a single host lists once, got %d'):format(#list))

        -- roster updates without restarting the beacon
        Discovery.setInfo({ name = 'Notch', players = 3, maxPlayers = 4,
                            state = 'playing', port = TUNE.net.gamePort })
        Discovery.beacon()
        deadline = love.timer.getTime() + 1
        while love.timer.getTime() < deadline do
            Discovery.update(1/60)
            if (Discovery.list()[1] or {}).players == 3 then break end
            love.timer.sleep(0.01)
        end
        ok((Discovery.list()[1] or {}).players == 3, 'roster change reached the browser')
        ok((Discovery.list()[1] or {}).state == 'playing', 'state change reached the browser')

        -- a host that stops talking ages off the list
        Discovery.stopHost()
        ok(not Discovery.hosting(), 'host stopped')
        local entry = Discovery.list()[1]
        if entry then entry.lastSeen = love.timer.getTime() - TUNE.net.beaconTimeout - 1 end
        Discovery.update(1/60)
        ok(#Discovery.list() == 0, 'silent host aged off the list')

        Discovery.shutdown()
        ok(not Discovery.browsing(), 'discovery shut down cleanly')
    end

    io.stderr:write(('\nSELFTEST %d/%d checks passed\n'):format(checks - fails, checks))
    os.exit(fails == 0 and 0 or 1)
end

return Selftest
