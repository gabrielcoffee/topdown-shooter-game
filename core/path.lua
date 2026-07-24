-- A* over the tile grid. Walls = solid tiles + whatever the caller marks
-- in `blocked` (unopened doors, crates). 8-directional, no corner cutting.
-- The start tile is always expandable and the goal tile ignores `blocked`:
-- a crate half-overlapping either tile must not make the whole search fail.
local Path = {}

local SQRT2 = math.sqrt(2)

local function key(col, row)
    return col .. ',' .. row
end

local function walkable(map, blocked, col, row)
    if col < 1 or col > map.cols or row < 1 or row > map.rows then
        return false
    end
    if blocked[key(col, row)] then
        return false
    end
    local t = map.tileTypes[map.grid[row][col]] or 'ground'
    return t ~= 'solid' and t ~= 'void'
end

-- octile distance heuristic
local function heuristic(c, r, gc, gr)
    local dx, dy = math.abs(c - gc), math.abs(r - gr)
    local lo, hi = math.min(dx, dy), math.max(dx, dy)
    return lo * SQRT2 + (hi - lo)
end

-- Returns array of {col, row} from start (exclusive) to goal, or nil
function Path.find(map, blocked, startCol, startRow, goalCol, goalRow)
    local goalKey = key(goalCol, goalRow)

    -- entity-blocked goal is still targetable (solid walls stay fatal)
    local function passable(col, row)
        if key(col, row) == goalKey then
            if col < 1 or col > map.cols or row < 1 or row > map.rows then
                return false
            end
            local t = map.tileTypes[map.grid[row][col]] or 'ground'
            return t ~= 'solid' and t ~= 'void'
        end
        return walkable(map, blocked, col, row)
    end

    if not passable(goalCol, goalRow) then
        return nil
    end
    if startCol == goalCol and startRow == goalRow then
        return {}
    end

    local startKey = key(startCol, startRow)
    local open = { { col = startCol, row = startRow, g = 0,
                     f = heuristic(startCol, startRow, goalCol, goalRow) } }
    local gScore = { [startKey] = 0 }
    local cameFrom = {}
    local closed = {}

    while #open > 0 do
        -- linear min-scan: grid is small (~1200 tiles), no heap needed
        local bestI = 1
        for i = 2, #open do
            if open[i].f < open[bestI].f then bestI = i end
        end
        local cur = table.remove(open, bestI)
        local curKey = key(cur.col, cur.row)

        if cur.col == goalCol and cur.row == goalRow then
            -- rebuild path back to start
            local path = {}
            local k = curKey
            while k and k ~= startKey do
                local node = cameFrom[k]
                table.insert(path, 1, { col = node.col, row = node.row })
                k = node.fromKey
            end
            return path
        end

        if not closed[curKey] then
            closed[curKey] = true

            for dc = -1, 1 do
                for dr = -1, 1 do
                    if not (dc == 0 and dr == 0) then
                        local nc, nr = cur.col + dc, cur.row + dr
                        local diagonal = dc ~= 0 and dr ~= 0
                        local ok = passable(nc, nr)

                        -- no cutting corners: both straight neighbors must be free
                        if ok and diagonal then
                            ok = walkable(map, blocked, cur.col + dc, cur.row)
                                and walkable(map, blocked, cur.col, cur.row + dr)
                        end

                        if ok then
                            local nKey = key(nc, nr)
                            local g = cur.g + (diagonal and SQRT2 or 1)
                            if gScore[nKey] == nil or g < gScore[nKey] then
                                gScore[nKey] = g
                                cameFrom[nKey] = { col = nc, row = nr, fromKey = curKey }
                                table.insert(open, { col = nc, row = nr, g = g,
                                    f = g + heuristic(nc, nr, goalCol, goalRow) })
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

return Path
