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

-- Save pixelated graphics
love.graphics.setDefaultFilter('nearest', 'nearest')

-- Load the images
Assets.spritesheet = love.graphics.newImage('assets/spritesheet.png')

-- Quads for the images
Assets.quads = {
    player = loadQuads(0, 0, 32, 32, 4),

    pistol = loadQuads(0, 32, 26, 32, 1),
    grenade = loadQuads(0, 64, 32, 32, 1),
    knife = loadQuads(0, 96, 32, 32, 1),

    ak47 = loadQuads(32, 32, 48, 32, 1),
    m4a1 = loadQuads(32, 64, 56, 32, 1),
    shotgun = loadQuads(32, 96, 40, 32, 1),

    aim = loadQuads(80, 32, 16, 16, 1),
    bullet = loadQuads(96, 32, 4, 2, 1),
    muzzle = loadQuads(112, 32, 12, 12, 3)
}

return Assets 