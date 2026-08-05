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

-- neon shop signs for the wall buys (64x32, drawn as-is over the wall)
Assets.wallArt = {
    ak47 = love.graphics.newImage('assets/images/guns/ak_wall.png'),
    m4a1 = love.graphics.newImage('assets/images/guns/m4_wall.png'),
    shotgun = love.graphics.newImage('assets/images/guns/shotgun_wall.png'),
}

-- SCENERY ATLAS ------------------------------------------------------------
-- One map/biome = one 32px-tall row of the spritesheet, same columns every
-- time, so a new map is just a new row (level1 = y 256, next one = y 288, ...):
--
--   x   0       solid (wall)              32x32
--   x  32..159  ground, 4 variants        32x32  (needs all 4 to activate)
--   x 160       torch                     32x32  (flame against the LEFT edge,
--                                                 mirrored in game by neighbor)
--   x 192       big prop A                32x32  (sways)
--   x 224       big prop B                32x32  (sways)
--   x 256..287  grass, 4 variants         16x16  packed 2x2 (sways)
--   x 288..319  rock, 4 variants          16x16  packed 2x2 (static)
--
-- Every entry activates on its own the moment its cells are painted, so art
-- can land one sprite at a time — unpainted cells simply stay out of the game.
-- `wind` and `stem` are per-prop: stem = px at the bottom that stay planted.
local SCENERY_PROPS = {
    { kind = 'bush',  x = 192, y = 0,  w = 32, h = 32, wind = true,  stem = 3 },
    { kind = 'bush',  x = 224, y = 0,  w = 32, h = 32, wind = true,  stem = 3 },
    { kind = 'grass', x = 256, y = 0,  w = 16, h = 16, wind = true,  stem = 3 },
    { kind = 'grass', x = 272, y = 0,  w = 16, h = 16, wind = true,  stem = 3 },
    { kind = 'grass', x = 256, y = 16, w = 16, h = 16, wind = true,  stem = 3 },
    { kind = 'grass', x = 272, y = 16, w = 16, h = 16, wind = true,  stem = 3 },
    { kind = 'rock',  x = 288, y = 0,  w = 16, h = 16, wind = false, stem = 0 },
    { kind = 'rock',  x = 304, y = 0,  w = 16, h = 16, wind = false, stem = 0 },
    { kind = 'rock',  x = 288, y = 16, w = 16, h = 16, wind = false, stem = 0 },
    { kind = 'rock',  x = 304, y = 16, w = 16, h = 16, wind = false, stem = 0 },
}

local sheetData = love.image.newImageData('assets/images/spritesheet.png')

-- any painted pixel in the cell = the artist filled this slot in
local function cellPainted(x, y, w, h)
    if x + w > sheetData:getWidth() or y + h > sheetData:getHeight() then return false end
    for py = y, y + h - 1 do
        for px = x, x + w - 1 do
            local _, _, _, a = sheetData:getPixel(px, py)
            if a > 0 then return true end
        end
    end
    return false
end

local sceneryCache = {}

-- Scenery set for a map row: { ground = {quads}|nil, torch = quad|nil,
-- props = { {quad, w, h, wind, stem, kind}, ... } }
function Assets.sceneryRow(rowY)
    if sceneryCache[rowY] then return sceneryCache[rowY] end

    local set = { props = {} }

    if cellPainted(0, rowY, 32, 32) then
        set.solid = love.graphics.newQuad(0, rowY, 32, 32, Assets.spritesheet)
    end

    local ground = {}
    for i = 0, 3 do
        if not cellPainted(32 + i * 32, rowY, 32, 32) then ground = nil break end
        ground[#ground + 1] = love.graphics.newQuad(
            32 + i * 32, rowY, 32, 32, Assets.spritesheet)
    end
    set.ground = ground

    if cellPainted(160, rowY, 32, 32) then
        set.torch = love.graphics.newQuad(160, rowY, 32, 32, Assets.spritesheet)
    end

    for _, p in ipairs(SCENERY_PROPS) do
        if cellPainted(p.x, rowY + p.y, p.w, p.h) then
            set.props[#set.props + 1] = {
                kind = p.kind, wind = p.wind, stem = p.stem,
                x = p.x, y = rowY + p.y, w = p.w, h = p.h,
                quad = love.graphics.newQuad(
                    p.x, rowY + p.y, p.w, p.h, Assets.spritesheet),
            }
        end
    end

    sceneryCache[rowY] = set
    return set
end

-- WALL AUTOTILE --------------------------------------------------------------
-- 7x3 block of 32px tiles at (0, 288). Walls pick their sprite from the 8
-- neighbors around them (core/map wallQuad):
--
--   cols 0-2            3x3 blob: outer corners, edges, full center
--   cols 3-5, row 0     1-tile-thick horizontal run: left cap, middle, right cap
--   col 6               1-tile-thick vertical run: top cap, middle, bottom cap
--   cols 3-4, rows 1-2  inner corners: notch on the one open diagonal, each
--                       notch pointing at the center of this 2x2 group
--
-- Activates only once the block is painted; until then core/map falls back to
-- the flat scenery solid tile.
local WALL_X, WALL_Y = 0, 288

if cellPainted(WALL_X, WALL_Y, 32, 32) then
    local function wq(col, row)
        return love.graphics.newQuad(
            WALL_X + col * 32, WALL_Y + row * 32, 32, 32, Assets.spritesheet)
    end
    Assets.walls = {
        tl = wq(0, 0), top    = wq(1, 0), tr = wq(2, 0),
        l  = wq(0, 1), c      = wq(1, 1), r  = wq(2, 1),
        bl = wq(0, 2), bottom = wq(1, 2), br = wq(2, 2),
        capL = wq(3, 0), h = wq(4, 0), capR = wq(5, 0),
        capT = wq(6, 0), v = wq(6, 1), capB = wq(6, 2),
        -- named by the open diagonal the notch faces
        innSE = wq(3, 1), innSW = wq(4, 1),
        innNE = wq(3, 2), innNW = wq(4, 2),
    }
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

    -- lock icon floated in front of closed doors
    lock = loadQuads(240, 0, 16, 16, 1),

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