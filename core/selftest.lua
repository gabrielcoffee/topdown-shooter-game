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

    io.stderr:write(('\nSELFTEST %d/%d checks passed\n'):format(checks - fails, checks))
    os.exit(fails == 0 and 0 or 1)
end

return Selftest
