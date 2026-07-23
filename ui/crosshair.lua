-- CS-style crosshair: 4 chips that open with the current spread (movement +
-- recoil) and close when standing still. Look (color / size / tilt / outline)
-- comes from SETTINGS, geometry and feel from TUNE.crosshair. Drawn at SCALE
-- so the chips stay pixel-art sized.

local Crosshair = {}

-- Preset palette the options menu cycles through (ids are what gets saved)
Crosshair.colors = {
    { id = 'white',   name = 'WHITE',   rgb = {1, 1, 1} },
    { id = 'green',   name = 'GREEN',   rgb = {0.2, 1, 0.2} },
    { id = 'cyan',    name = 'CYAN',    rgb = {0.2, 1, 1} },
    { id = 'yellow',  name = 'YELLOW',  rgb = {1, 1, 0.2} },
    { id = 'red',     name = 'RED',     rgb = {1, 0.25, 0.25} },
    { id = 'magenta', name = 'MAGENTA', rgb = {1, 0.3, 1} },
}

function Crosshair.colorById(id)
    for _, c in ipairs(Crosshair.colors) do
        if c.id == id then return c end
    end
    return Crosshair.colors[1]
end

function Crosshair.nextColorId(id, dir)
    for i, c in ipairs(Crosshair.colors) do
        if c.id == id then
            return Crosshair.colors[((i - 1 + dir) % #Crosshair.colors) + 1].id
        end
    end
    return Crosshair.colors[1].id
end

local gap = nil  -- smoothed px gap (center to chip inner edge), world-pixel units
local tiltT = 0  -- 0..1 eased progress of the 45° tilt

function Crosshair.update(dt, world)
    local K = TUNE.crosshair
    local player = world.player
    local held = player.items[player.itemIndex]
    local moveFactor = player.moveFactor or 0

    local target
    if held and held.isGun then
        target = K.gapMin + held:currentSpread(moveFactor) * K.spreadToPx
    else
        target = K.gapMin + moveFactor * K.itemMoveGap
    end
    if gap == nil then gap = target end
    gap = gap + (target - gap) * math.min(1, K.openSpeed * dt)

    -- tilt eases in while a living zombie's hitbox sits under the mouse
    local wantTilt = false
    if SETTINGS.crossTilt then
        local mx, my = love.mouse.getPosition()
        local wx, wy = mx / SCALE + world.camX, my / SCALE + world.camY
        for _, e in ipairs(world.entities) do
            if e.type == 'enemy' and not e.toRemove and e.health > 0 then
                local cx, cy = e:getCenter()
                local dx, dy = wx - cx, wy - cy
                if dx * dx + dy * dy <= e.radius * e.radius then
                    wantTilt = true
                    break
                end
            end
        end
    end
    tiltT = math.max(0, math.min(1, tiltT + (wantTilt and 1 or -1) * K.tiltSpeed * dt))
end

function Crosshair.draw()
    local K = TUNE.crosshair
    local s = SETTINGS.crossSize or 1
    local len, thick = K.chipLen * s, K.chipThick * s
    local g = gap or K.gapMin
    local mx, my = love.mouse.getPosition()

    love.graphics.push()
    love.graphics.translate(mx, my)
    love.graphics.scale(SCALE, SCALE)
    love.graphics.rotate(tiltT * math.pi / 4)

    -- right / left chips lie flat, top / bottom stand upright
    local chips = {
        {  g,          -thick / 2, len,   thick },
        { -g - len,    -thick / 2, len,   thick },
        { -thick / 2,   g,         thick, len },
        { -thick / 2,  -g - len,   thick, len },
    }

    if SETTINGS.crossOutline then
        love.graphics.setColor(0, 0, 0)
        for _, c in ipairs(chips) do
            love.graphics.rectangle('fill', c[1] - 1, c[2] - 1, c[3] + 2, c[4] + 2)
        end
    end

    local rgb = Crosshair.colorById(SETTINGS.crossColor).rgb
    love.graphics.setColor(rgb[1], rgb[2], rgb[3])
    for _, c in ipairs(chips) do
        love.graphics.rectangle('fill', c[1], c[2], c[3], c[4])
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return Crosshair
