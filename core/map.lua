local Assets = require('core.assets')

local Map = {}
Map.__index = Map

-- Stable pseudo-random pick per cell (classic sin-fract hash): the same
-- tile always shows the same variant, no stored state, no per-frame flicker.
local function variantIndex(col, row, n)
    return math.floor((math.sin(col * 127.1 + row * 311.7) * 43758.5453) % 1 * n) + 1
end

-- Placeholder colors per tile type, used until real tile art exists
local typeColors = {
    ground = {0.42, 0.38, 0.30},
    solid  = {0.22, 0.22, 0.26},
    spikes = {0.62, 0.62, 0.66},
    water  = {0.20, 0.45, 0.75},
    mud    = {0.30, 0.21, 0.12},
    hole   = {0.05, 0.05, 0.05},
    torch  = {0.95, 0.55, 0.15}, -- bright so it reads as the light source
    void   = {0.02, 0.02, 0.03}, -- between rooms: blocked, near-black
}

function Map:new(levelDef)
    local obj = {
        grid = levelDef.grid, -- global 2D grid built by core/ldtk
        tileSize = TUNE.tiles.size,
        tileTypes = levelDef.tileTypes,
        groundFillId = levelDef.groundFillId,
        surfaces = levelDef.surfaces, -- tile type -> footstep material
        -- ground/torch/prop art for this map (see core/assets sceneryRow)
        scenery = Assets.sceneryRow(levelDef.tileRow),
    }

    obj.rows = #obj.grid
    obj.cols = #obj.grid[1]
    obj.pixelW = obj.cols * obj.tileSize
    obj.pixelH = obj.rows * obj.tileSize

    -- Tileset is optional: colored squares stand in until one is exported
    if levelDef.tileset and love.filesystem.getInfo(levelDef.tileset) then
        obj.tileset = love.graphics.newImage(levelDef.tileset)
        obj.quads = {}
        local perRow = math.floor(obj.tileset:getWidth() / obj.tileSize)
        for _, row in ipairs(obj.grid) do
            for _, id in ipairs(row) do
                if id >= 0 and not obj.quads[id] then
                    obj.quads[id] = love.graphics.newQuad(
                        (id % perRow) * obj.tileSize,
                        math.floor(id / perRow) * obj.tileSize,
                        obj.tileSize, obj.tileSize, obj.tileset
                    )
                end
            end
        end
    end

    setmetatable(obj, Map)
    return obj
end

-- Tile type at a world pixel position. Outside the map counts as solid.
function Map:typeAt(px, py)
    local col = math.floor(px / self.tileSize) + 1
    local row = math.floor(py / self.tileSize) + 1
    if row < 1 or row > self.rows or col < 1 or col > self.cols then
        return 'solid'
    end
    return self.tileTypes[self.grid[row][col]] or 'ground'
end

-- void (outside every room) blocks exactly like solid
function Map:isSolidAt(px, py)
    local t = self:typeAt(px, py)
    return t == 'solid' or t == 'void'
end

-- Straight walk over the tile grid: is a solid wall between a and b?
-- Shared LOS test: audio occlusion, knife swings, grenade blasts.
function Map:wallBetween(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return false end
    local steps = math.ceil(dist / 16) -- half-tile sampling
    for i = 1, steps - 1 do
        local t = i / steps
        if self:isSolidAt(ax + dx * t, ay + dy * t) then return true end
    end
    return false
end

-- Footstep material at a pixel: level's surfaces map keyed by tile type,
-- 'sand' when the level doesn't say (the map is a desert). Mud is always
-- dirt, whatever the map's surface table claims — wet ground squelches the
-- same everywhere.
function Map:surfaceAt(px, py)
    local t = self:typeAt(px, py)
    if t == 'mud' then return 'dirt' end
    return (self.surfaces and self.surfaces[t]) or 'sand'
end

function Map:setTile(col, row, id)
    if self.grid[row] and self.grid[row][col] then
        self.grid[row][col] = id
    end
end

function Map:draw(camX, camY)
    local ts = self.tileSize
    local c0 = math.max(1, math.floor(camX / ts) + 1)
    local r0 = math.max(1, math.floor(camY / ts) + 1)
    local c1 = math.min(self.cols, math.floor((camX + SCREENWIDTH/SCALE) / ts) + 1)
    local r1 = math.min(self.rows, math.floor((camY + SCREENHEIGHT/SCALE) / ts) + 1)

    for row = r0, r1 do
        for col = c0, c1 do
            local id = self.grid[row][col]
            local x, y = (col - 1) * ts, (row - 1) * ts
            local t = self.tileTypes[id] or 'ground'
            -- a torch tile is floor with a torch on the wall beside it, so it
            -- takes the ground art too (core/decor draws the torch itself)
            local variants = (t == 'ground' or t == 'torch') and self.scenery.ground
            if variants then
                -- hand-drawn art with variants wins over tileset and colors
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(Assets.spritesheet,
                    variants[variantIndex(col, row, #variants)], x, y)
            elseif t == 'solid' and self.scenery.solid then
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(Assets.spritesheet, self.scenery.solid, x, y)
            elseif self.tileset and self.quads[id] then
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(self.tileset, self.quads[id], x, y)
            else
                local c = typeColors[t]
                love.graphics.setColor(c[1], c[2], c[3])
                love.graphics.rectangle('fill', x, y, ts, ts)
            end
        end
    end
    love.graphics.setColor(1, 1, 1)
end

return Map
