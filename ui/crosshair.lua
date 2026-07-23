-- CS-style crosshair: 4 chips that open with the current spread (movement +
-- recoil) and close when standing still. Never drawn past where the held
-- gun's bullets can actually reach. Color (white/green) + outline come from
-- SETTINGS, geometry and feel from TUNE.crosshair. Drawn at SCALE so the
-- chips stay pixel-art sized.

local Crosshair = {}

-- The two allowed colors (ids are what gets saved)
Crosshair.colors = {
    { id = 'white', name = 'WHITE', rgb = {1, 1, 1} },
    { id = 'green', name = 'GREEN', rgb = {0.2, 1, 0.2} },
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

local gap = nil -- smoothed px gap (center to chip inner edge), world-pixel units

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
end

function Crosshair.draw(world)
    local player = world.player
    local held = player.items[player.itemIndex]
    if held and held.isKnife then return end -- knife has no aim

    local K = TUNE.crosshair
    local g = gap or K.gapMin
    local mx, my = require('ui.screen').mouse()

    -- the crosshair never sits past the bullet's actual reach
    if held and held.isGun then
        local pcx, pcy = player:getCenter()
        local sx = (pcx - world.camX) * SCALE
        local sy = (pcy - world.camY) * SCALE
        local reach = (held.tipLen + TUNE.bullet.speed * held.bulletLifeTime) * SCALE
        local dx, dy = mx - sx, my - sy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > reach then
            mx = sx + dx / dist * reach
            my = sy + dy / dist * reach
        end
    end

    love.graphics.push()
    love.graphics.translate(mx, my)
    love.graphics.scale(SCALE, SCALE)

    -- right / left chips lie flat, top / bottom stand upright
    local len, thick = K.chipLen, K.chipThick
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
