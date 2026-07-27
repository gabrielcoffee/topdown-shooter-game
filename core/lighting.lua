-- Dynamic lighting wrapper around light_world.lua.
-- One instance per World run:
--   * ambient darkness + a light on the player
--   * torch tiles (map id 'torch') as flickering fixed lights
--   * shadow occluders: solid tiles (merged into rectangles), crates, doors —
--     lights can't reach behind them, so the player can't see the other side
--   * short-lived flash lights (muzzle flashes, explosions later)

local LightWorld = require('lib.light_world')

local Lighting = {}
Lighting.__index = Lighting

-- Merge solid tiles into as few rectangles as possible:
-- greedy horizontal runs per row, then identical runs merged vertically.
local function solidRects(map)
    local runs = {} -- list of {row, c0, c1}
    for row = 1, map.rows do
        local col = 1
        while col <= map.cols do
            if map.tileTypes[map.grid[row][col]] == 'solid' then
                local c0 = col
                while col <= map.cols and map.tileTypes[map.grid[row][col]] == 'solid' do
                    col = col + 1
                end
                table.insert(runs, { row = row, c0 = c0, c1 = col - 1, rows = 1 })
            else
                col = col + 1
            end
        end
    end

    -- merge a run into the one directly above when the columns match
    local merged = {}
    local open = {} -- keyed 'c0,c1' -> rect still growing
    for _, r in ipairs(runs) do
        local key = r.c0 .. ',' .. r.c1
        local prev = open[key]
        if prev and prev.row + prev.rows == r.row then
            prev.rows = prev.rows + 1
        else
            local rect = { row = r.row, c0 = r.c0, c1 = r.c1, rows = 1 }
            open[key] = rect
            table.insert(merged, rect)
        end
    end
    return merged
end

function Lighting.new(map)
    local self = setmetatable({}, Lighting)

    local a = TUNE.lighting.ambient
    self.lw = LightWorld({ ambient = { a, a, a } })
    -- light_world sizes its buffers to the OS window by default, so at fullscreen
    -- it re-renders every light pass at native resolution — the fullscreen lag.
    -- Pin them to the fixed logical canvas so cost is constant regardless of res.
    self.lw:refreshScreenSize(SCREENWIDTH, SCREENHEIGHT)
    self.lw:setShadowBlur(0)      -- hard shadows fit the pixel art + cheap
    self.lw.disableGlow = true    -- plain occluders: glow/material passes are
    self.lw.disableMaterial = true -- fullscreen canvas work for nothing

    -- warm light following the player (intensity via color scale, full 1.0 blinds)
    local b = TUNE.lighting.playerBright
    self.playerLight = self.lw:newLight(0, 0, b, b * 0.88, b * 0.68, TUNE.lighting.playerRange)

    self.flashes = {}  -- { light = <light>, t = secs left }
    self.tracked = {}  -- entity -> occluder body (crates, doors)
    self.torches = {}  -- { light = <light>, phase = <noise offset> }
    self.points = {}   -- persistent flickering lights (fire patches)

    if map then
        local ts = map.tileSize

        -- solid tiles cast shadows
        for _, r in ipairs(solidRects(map)) do
            local w = (r.c1 - r.c0 + 1) * ts
            local h = r.rows * ts
            local cx = (r.c0 - 1) * ts + w / 2
            local cy = (r.row - 1) * ts + h / 2
            self.lw:newRectangle(cx, cy, w, h)
        end

        -- torch tiles light up around themselves
        for row = 1, map.rows do
            for col = 1, map.cols do
                if map.tileTypes[map.grid[row][col]] == 'torch' then
                    local tb = TUNE.lighting.torchBright
                    local light = self.lw:newLight(
                        (col - 0.5) * ts, (row - 0.5) * ts,
                        tb, tb * 0.62, tb * 0.25, TUNE.lighting.torchRange)
                    table.insert(self.torches, {
                        light = light,
                        phase = love.math.random() * 100,
                    })
                end
            end
        end
    end

    return self
end

-- Entity that blocks light (crate, door). Follows the entity every update,
-- removed automatically when the entity dies/opens (toRemove).
function Lighting:trackOccluder(e)
    self.tracked[e] = self.lw:newRectangle(
        e.x + e.width / 2, e.y + e.height / 2, e.width, e.height)
end

-- Short-lived point light (muzzle flash, blast). x/y in world coords.
function Lighting:flash(x, y, r, g, b, range, time)
    local light = self.lw:newLight(x, y, r, g, b, range)
    table.insert(self.flashes, { light = light, t = time })
end

-- Persistent flickering point light (fire patch); caller keeps the handle
-- and must removePoint it when done
function Lighting:addPoint(x, y, r, g, b, range)
    local p = {
        light = self.lw:newLight(x, y, r, g, b, range),
        baseRange = range,
        phase = love.math.random() * 100,
    }
    table.insert(self.points, p)
    return p
end

function Lighting:removePoint(p)
    for i, q in ipairs(self.points) do
        if q == p then
            self.lw:remove(q.light)
            table.remove(self.points, i)
            return
        end
    end
end

function Lighting:update(dt, world)
    local px, py = world.player:getCenter()
    self.playerLight:setPosition(px, py)

    for i = #self.flashes, 1, -1 do
        local f = self.flashes[i]
        f.t = f.t - dt
        if f.t <= 0 then
            self.lw:remove(f.light)
            table.remove(self.flashes, i)
        end
    end

    -- crates move, doors open
    for e, body in pairs(self.tracked) do
        if e.toRemove then
            self.lw:remove(body)
            self.tracked[e] = nil
        else
            body:setPosition(e.x + e.width / 2, e.y + e.height / 2)
        end
    end

    -- torch flicker: noise-driven range wobble, each torch out of phase
    local t = love.timer.getTime() * TUNE.lighting.torchFlickerSpeed
    for _, torch in ipairs(self.torches) do
        local n = love.math.noise(t + torch.phase) - 0.5
        torch.light:setRange(TUNE.lighting.torchRange * (1 + n * TUNE.lighting.torchFlickerDepth))
    end

    -- persistent points flicker like torches
    for _, p in ipairs(self.points) do
        local n = love.math.noise(t + p.phase) - 0.5
        p.light:setRange(p.baseRange * (1 + n * TUNE.lighting.torchFlickerDepth))
    end

    self.lw:update(dt)
end

-- Re-pin the light buffers to the logical size (called after a graphics apply)
function Lighting:resize(w, h)
    self.lw:refreshScreenSize(w, h)
end

-- Screen-space translation (camera + shake), applied at draw time
function Lighting:setView(camX, camY, scale)
    self.lw:setTranslation(-camX * scale, -camY * scale, scale)
end

-- cb draws the scene in world coordinates; light_world applies the transform
function Lighting:draw(cb)
    self.lw:draw(cb)
end

return Lighting
