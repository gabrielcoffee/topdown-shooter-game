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
    end
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

    -- ---------------------------------------------------------------- move
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
    -- Everything below runs with a second player in world.players, which is
    -- exactly the shape LAN co-op produces.

    local Enemy = require('entities.enemy')

    -- ------------------------------------------------- players / nearest
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
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 600, p1.y)
    local near = Enemy:newSlow(p2.x - 40, p2.y, 1)
    world:addEntity(near)
    step(world, 4)
    ok(near.target == p2, 'zombie chases the nearest player, not player 1')

    -- -------------------------------------------- independent room/cameras
    world = freshWorld()
    p1 = world.player
    p2 = world:addPlayer(p1.x + 200, p1.y)
    step(world, 4)
    ok(p1.camX ~= nil and p2.camX ~= nil, 'both players have a camera')
    ok(world.camX == p1.camX, 'world camera mirrors the local player')

    -- a room pan on one player must not stop the world for anyone else
    world = freshWorld()
    p1 = world.player
    local zom = Enemy:newSlow(p1.x + 120, p1.y + 120, 1)
    world:addEntity(zom)
    step(world, 4)
    local zx, zy = zom.x, zom.y
    -- force a transition on the local player
    p1.transition = {
        t = 0, room = p1.currentRoom,
        fromCamX = p1.camX, fromCamY = p1.camY,
        toCamX = p1.camX + 50, toCamY = p1.camY,
    }
    step(world, 10)
    ok(zom.x ~= zx or zom.y ~= zy,
        'zombies keep moving while a camera pans (world no longer freezes)')

    -- ------------------------------------------------ real room transition
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

    io.stderr:write(('\nSELFTEST %d/%d checks passed\n'):format(checks - fails, checks))
    os.exit(fails == 0 and 0 or 1)
end

return Selftest
