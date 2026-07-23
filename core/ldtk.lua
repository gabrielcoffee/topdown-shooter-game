-- LDtk project loader. Edit maps/level1.ldtk in the LDtk app, save, press U.
--
-- Every LDtk level is a room (Celeste-style). All rooms get stitched into ONE
-- global tile grid in world pixel coords, so collision, A* and lighting work
-- across rooms unchanged — zombies path between rooms for free. Cells outside
-- every room are 'void': blocked like solid, drawn near-black.
--
-- Rooms must stay aligned to the 32px grid in LDtk (default snap does this).

local json = require('lib.json')

local Ldtk = {}

Ldtk.VOID = -1

-- IntGrid value -> gameplay type. 0/unlisted = ground.
local tileTypes = {
    [1] = 'solid',
    [2] = 'spikes',
    [3] = 'water',
    [4] = 'mud',
    [5] = 'hole',
    [6] = 'torch',
    [Ldtk.VOID] = 'void',
}

function Ldtk.load(path)
    local raw, err = love.filesystem.read(path)
    assert(raw, ('cannot read %s: %s'):format(path, tostring(err)))
    local data = json.decode(raw)

    local ts = TUNE.tiles.size

    -- world bounding box over all levels, so the global grid starts at (0,0)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    for _, lv in ipairs(data.levels) do
        minX = math.min(minX, lv.worldX)
        minY = math.min(minY, lv.worldY)
        maxX = math.max(maxX, lv.worldX + lv.pxWid)
        maxY = math.max(maxY, lv.worldY + lv.pxHei)
    end

    local cols = math.ceil((maxX - minX) / ts)
    local rows = math.ceil((maxY - minY) / ts)

    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            grid[r][c] = Ldtk.VOID
        end
    end

    local rooms, objects = {}, {}
    for _, lv in ipairs(data.levels) do
        local ox, oy = lv.worldX - minX, lv.worldY - minY
        table.insert(rooms, {
            name = lv.identifier,
            x = ox, y = oy, w = lv.pxWid, h = lv.pxHei,
        })

        local colOff = math.floor(ox / ts + 0.5)
        local rowOff = math.floor(oy / ts + 0.5)

        for _, layer in ipairs(lv.layerInstances or {}) do
            if layer.__type == 'IntGrid' and #layer.intGridCsv > 0 then
                for i, id in ipairs(layer.intGridCsv) do
                    local c = (i - 1) % layer.__cWid + 1
                    local r = math.floor((i - 1) / layer.__cWid) + 1
                    grid[rowOff + r][colOff + c] = id
                end
            elseif layer.__type == 'Entities' then
                for _, e in ipairs(layer.entityInstances) do
                    local o = {
                        type = e.__identifier:lower(),
                        x = ox + e.px[1],
                        y = oy + e.px[2],
                    }
                    -- entity fields (door price/id, spawn door link, ...)
                    for _, f in ipairs(e.fieldInstances or {}) do
                        o[f.__identifier] = f.__value
                    end
                    table.insert(objects, o)
                end
            end
        end
    end

    return {
        grid = grid,
        rooms = rooms,
        objects = objects,
        tileTypes = tileTypes,
        groundFillId = 0,
        tileset = 'assets/images/tileset.png', -- optional, colored squares until it exists
    }
end

return Ldtk
