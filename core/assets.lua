local Assets = {}

local function loadQuads(startX, startY, width, height, totalFrames)
    local quads = {}

    for i = 0, totalFrames-1 do
        table.insert(
            quads,
            love.graphics.newQuad(
                startX + (i * width),
                startY,
                width, height, Assets.spritesheet
            )
        )
    end

    return quads
end

local function loadBgQuads(startX, startY, width, height, totalFrames, sprite)
    local quads = {}

    for i = 0, totalFrames-1 do
        table.insert(
            quads,
            love.graphics.newQuad(
                startX + (i * width),
                startY,
                width, height, sprite
            )
        )
    end

    return quads
end

-- Save pixelated graphics
love.graphics.setDefaultFilter('nearest', 'nearest')

-- Load the images
Assets.spritesheet = love.graphics.newImage('assets/images/spritesheet.png')
Assets.bg_dust = love.graphics.newImage('assets/images/bg_dust.png')
Assets.bg_dust:setWrap("repeat", "repeat")

-- Quads for the images
Assets.quads = {
    player = loadQuads(0, 0, 32, 32, 4),

    -- Items live in the first column, one row each; the "player holding it"
    -- version sits right after the item in the same row.
    pistol = loadQuads(0, 32, 32, 32, 1),
    grenade = loadQuads(0, 64, 32, 32, 1),
    knife = loadQuads(0, 96, 32, 32, 1),

    ak47 = loadQuads(0, 128, 64, 32, 1),
    m4a1 = loadQuads(0, 160, 64, 32, 1),
    shotgun = loadQuads(0, 192, 64, 32, 1),

    held_pistol = loadQuads(32, 32, 32, 32, 1),
    held_grenade = loadQuads(32, 64, 32, 32, 1),
    held_knife = loadQuads(32, 96, 32, 32, 1),

    held_ak47 = loadQuads(64, 128, 64, 32, 1),
    held_m4a1 = loadQuads(64, 160, 64, 32, 1),
    held_shotgun = loadQuads(64, 192, 64, 32, 1),

    aim = loadQuads(128, 0, 16, 16, 1),
    bullet = loadQuads(144, 0, 4, 2, 1),
    muzzle = loadQuads(160, 0, 12, 12, 3),

    bg_dust = loadBgQuads(0, 0, SCREENWIDTH, SCREENHEIGHT, 1, Assets.bg_dust)
}

return Assets 