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
Assets.spritesheet = love.graphics.newImage('assets/spritesheet.png')
Assets.bg_dust = love.graphics.newImage('assets/images/bg_dust.png')
Assets.bg_dust:setWrap("repeat", "repeat")

-- neon shop signs for the wall buys (64x32, drawn as-is over the wall)
Assets.wallArt = {
    ak47 = love.graphics.newImage('assets/ak_wall.png'),
    m4a1 = love.graphics.newImage('assets/m4_wall.png'),
    shotgun = love.graphics.newImage('assets/shotgun_wall.png'),
}

-- Tile art with random variants: tile type -> horizontal strip of 32x32
-- cells on the spritesheet. A strip only activates when every declared cell
-- is painted, so entries can be declared before the art is exported — the
-- map keeps its flat-color fallback until the full strip exists.
local tileVariantDefs = {
    ground = { x = 0, y = 288, count = 4 },
}

Assets.tileVariants = {}
do
    local data = love.image.newImageData('assets/spritesheet.png')

    local function cellPainted(x, y)
        if x + 32 > data:getWidth() or y + 32 > data:getHeight() then return false end
        for py = y, y + 31 do
            for px = x, x + 31 do
                local _, _, _, a = data:getPixel(px, py)
                if a > 0 then return true end
            end
        end
        return false
    end

    for tileType, def in pairs(tileVariantDefs) do
        local quads = {}
        for i = 0, def.count - 1 do
            if not cellPainted(def.x + i * 32, def.y) then quads = nil break end
            quads[#quads + 1] = love.graphics.newQuad(
                def.x + i * 32, def.y, 32, 32, Assets.spritesheet)
        end
        Assets.tileVariants[tileType] = quads
    end
end

-- Quads for the images
Assets.quads = {
    player = loadQuads(0, 0, 32, 32, 4),

    -- Items live in the first column, one row each; the "player holding it"
    -- version sits right after the item in the same row.
    pistol = loadQuads(0, 32, 32, 32, 1),
    medkit = loadQuads(64, 32, 32, 32, 1),
    grenade = loadQuads(0, 64, 32, 32, 1),
    molotov = loadQuads(64, 64, 32, 32, 1),
    knife = loadQuads(0, 96, 32, 32, 1),

    ak47 = loadQuads(0, 128, 64, 32, 1),
    m4a1 = loadQuads(0, 160, 64, 32, 1),
    shotgun = loadQuads(0, 192, 64, 32, 1),

    held_pistol = loadQuads(32, 32, 32, 32, 1),
    held_medkit = loadQuads(96, 32, 32, 32, 1),
    held_grenade = loadQuads(32, 64, 32, 32, 1),
    held_molotov = loadQuads(96, 64, 32, 32, 1),
    held_knife = loadQuads(32, 96, 32, 32, 1),

    held_ak47 = loadQuads(64, 128, 64, 32, 1),
    held_m4a1 = loadQuads(64, 160, 64, 32, 1),
    held_shotgun = loadQuads(64, 192, 64, 32, 1),
    held_shotgun_pump = loadQuads(128, 192, 64, 32, 1), -- rack pose, next cell after held_shotgun

    -- spent casings, 8x8 cells (art is 16px apart on the sheet), ejected by the
    -- gun: red shotgun shell / brass rifle case / short pistol case
    shell_shotgun = loadQuads(196, 4, 8, 8, 1),
    shell_rifle   = loadQuads(212, 4, 8, 8, 1), -- ak47 + m4a1
    shell_pistol  = loadQuads(228, 4, 8, 8, 1), -- usp

    -- crate: flat 32x32 top-down sprite, hitbox = sprite box
    crate = loadQuads(32, 224, 32, 32, 1),

    aim = loadQuads(128, 0, 16, 16, 1),
    bullet = loadQuads(144, 0, 4, 2, 1),
    muzzle = loadQuads(160, 0, 12, 12, 3),

    bg_dust = loadBgQuads(0, 0, SCREENWIDTH, SCREENHEIGHT, 1, Assets.bg_dust)
}

-- Re-cut the fullscreen bg quad after the logical size changes (aspect switch).
function Assets.rebakeBg()
    Assets.quads.bg_dust = loadBgQuads(0, 0, SCREENWIDTH, SCREENHEIGHT, 1, Assets.bg_dust)
end

return Assets 