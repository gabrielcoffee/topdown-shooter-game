-- Grenade targeting preview: while a grenade is held, two animated dotted
-- guides show the throw. An arc of dots marches from the player to the
-- landing point (the cursor, clamped to grenade.maxRange — same clamp the
-- actual throw uses), hopping with the same fake-3D arc the live grenade
-- flies. A dotted circle of the blast radius spins slowly at the landing
-- point. Grenades fly over walls, so the guides ignore them too.

local GrenadeAim = {}

local flowPhase = 0 -- px the arc dots have marched (wraps at dot spacing)
local spinPhase = 0 -- radians the blast circle has rotated

-- Numbers for whichever throwable is out; aim cosmetics (dot spacing etc.)
-- always come from the grenade block
local function tuneFor(world)
    return world.player.throwableType == 'molotov' and TUNE.molotov
        or TUNE.grenade
end

function GrenadeAim.update(dt)
    local G = TUNE.grenade
    flowPhase = (flowPhase + G.aimFlowSpeed * dt) % G.aimDotSpacing
    spinPhase = (spinPhase + G.aimSpinSpeed * dt) % (math.pi * 2)
end

-- Where the throwable would land right now: cursor clamped to maxRange.
-- The player's throw calls this too, so the preview is never a lie.
function GrenadeAim.target(world)
    local mx, my = require('ui.screen').mouse()
    local wx = mx / SCALE + world.camX
    local wy = my / SCALE + world.camY

    local pcx, pcy = world.player:getCenter()
    local dx, dy = wx - pcx, wy - pcy
    local dist = math.sqrt(dx * dx + dy * dy)
    local maxR = tuneFor(world).maxRange
    if dist > maxR then
        wx = pcx + dx / dist * maxR
        wy = pcy + dy / dist * maxR
    end
    return wx, wy
end

function GrenadeAim.draw(world)
    local player = world.player
    local held = player.items[player.itemIndex]
    if not (held and held.isThrowable and player:throwableCount() > 0) then return end

    local G = TUNE.grenade
    local pcx, pcy = player:getCenter()
    local tx, ty = GrenadeAim.target(world)

    love.graphics.push()
    love.graphics.scale(SCALE, SCALE)
    love.graphics.translate(-world.camX, -world.camY)
    if player.throwableType == 'molotov' then
        love.graphics.setColor(1, 0.55, 0.2, G.aimAlpha) -- fire orange
    else
        love.graphics.setColor(1, 1, 1, G.aimAlpha)
    end

    -- throw arc: dots march player -> landing point, lifted by the same
    -- parabolic hop the thrown grenade draws with
    local dx, dy = tx - pcx, ty - pcy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 1 then
        local s = flowPhase
        while s < dist do
            local t = s / dist
            local arc = math.sin(t * math.pi) * math.min(24, dist * 0.2)
            love.graphics.circle('fill', pcx + dx * t, pcy + dy * t - arc, G.aimDotSize)
            s = s + G.aimDotSpacing
        end
    end

    -- blast circle: evenly spaced dots, whole ring rotating slowly
    local r = tuneFor(world).blastRadius
    local dots = math.max(8, math.floor(2 * math.pi * r / G.aimDotSpacing))
    for i = 1, dots do
        local a = spinPhase + (i / dots) * math.pi * 2
        love.graphics.circle('fill', tx + math.cos(a) * r, ty + math.sin(a) * r, G.aimDotSize)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return GrenadeAim
