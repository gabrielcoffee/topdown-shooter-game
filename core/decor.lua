-- Scenery layer: grass/rocks/bushes scattered over the ground, plus the wall
-- torches. Drawn between the tiles and the entities, inside the lighting pass.
--
-- Placement is derived from the tile coords with the same sin-hash the tile
-- variants use, so a map always grows the exact same field — nothing to store,
-- nothing to save, no drift between sessions. Everything scattered is baked
-- into ONE static mesh in world coords and goes out in a single draw call.
--
-- WIND (how 2D games fake foliage, e.g. Stardew/Terraria grass):
-- each vertex carries a bend weight = how far it sits above the plant's stem
-- base, so the bottom rows stay planted in the dirt and the tip travels the
-- most. Sprites are cut into horizontal slices so the bend curves instead of
-- shearing. On top of a constant low sway, a gust wave sweeps the world in +x
-- so a field ripples in sequence rather than wobbling in unison.

local Assets = require('core.assets')

local Decor = {}
Decor.__index = Decor

local SEGMENTS_BIG = 8   -- horizontal slices for a 32px prop
local SEGMENTS_SMALL = 4 -- ... for a 16px prop

local shader = love.graphics.newShader([[
    attribute vec2 WindData; // x = bend weight 0..1, y = per-prop phase
    attribute vec4 UVBounds; // this sprite's cell, inset to texel centers

    varying vec4 vBounds;

    uniform float t;
    uniform vec4 sway;     // amp px, speed, gust amp px, gust speed
    uniform float gustWave; // gust travel across world x (lower = wider wave)

    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vBounds = UVBounds;
        float w = WindData.x;
        if (w > 0.0) {
            float ph = WindData.y + vertex_position.x * 0.035
                                  + vertex_position.y * 0.02;
            float s = sin(t * sway.y + ph) * 0.65
                    + sin(t * sway.y * 1.73 + ph * 1.7) * 0.35;
            float g = max(sin(t * sway.w - vertex_position.x * gustWave), 0.0);
            g = g * g * g; // gusts stay rare and sharp instead of metronomic
            float bend = s * sway.x + g * sway.z * (0.75 + 0.25 * s);
            vertex_position.x += bend * w;
            vertex_position.y += abs(bend) * w * 0.15; // tip arcs down as it leans
        }
        return transform_projection * vertex_position;
    }
]], [[
    varying vec4 vBounds;

    // bending moves vertices by fractions of a pixel, so a sample at the very
    // edge can land on the next cell of the atlas — clamp it back in
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
        return Texel(tex, clamp(uv, vBounds.xy, vBounds.zw)) * color;
    }
]])

local VERTEX_FORMAT = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexTexCoord', 'float', 2 },
    { 'WindData', 'float', 2 },
    { 'UVBounds', 'float', 4 },
}

-- Stable pseudo-random in [0,1) per tile + salt (same hash as the tile variants)
local function hash(col, row, salt)
    return (math.sin(col * 127.1 + row * 311.7 + salt * 74.7) * 43758.5453) % 1
end

local function pick(list, r)
    return list[math.min(#list, math.floor(r * #list) + 1)]
end

-- bend weight at a height above the sprite's bottom: 0 through the stem, then
-- eased up to 1 at the tip. stiffness > 1 keeps the lower half nearly rigid.
local function bendWeight(above, h, stem, stiffness)
    local span = h - stem
    if span <= 0 then return 0 end
    local f = (above - stem) / span
    if f <= 0 then return 0 end
    return f ^ stiffness
end

function Decor.new(map, scenery)
    local self = setmetatable({}, Decor)
    self.scenery = scenery
    self.torches = {}
    self.mesh = nil

    local ts = map.tileSize
    local cfg = TUNE.props

    -- torches: floor tiles with a torch mounted on the wall beside them. The
    -- art hangs on the left edge, so mirror it when the wall is on the right.
    if scenery.torch then
        for row = 1, map.rows do
            for col = 1, map.cols do
                if map.tileTypes[map.grid[row][col]] == 'torch' then
                    local function blocked(c)
                        if c < 1 or c > map.cols then return true end
                        local t = map.tileTypes[map.grid[row][c]]
                        return t == 'solid' or t == 'void'
                    end
                    table.insert(self.torches, {
                        x = (col - 1) * ts,
                        y = (row - 1) * ts,
                        flip = (not blocked(col - 1)) and blocked(col + 1),
                        phase = hash(col, row, 9) * 100,
                    })
                end
            end
        end
    end

    -- scatter pass: collect first so props can be depth-sorted before baking
    local props = {}
    if #scenery.props > 0 then
        local bushes, grass, rocks = {}, {}, {}
        for _, p in ipairs(scenery.props) do
            local bucket = (p.kind == 'bush' and bushes)
                or (p.kind == 'grass' and grass) or rocks
            bucket[#bucket + 1] = p
        end

        for row = 1, map.rows do
            for col = 1, map.cols do
                local t = map.tileTypes[map.grid[row][col]] or 'ground'
                if t == 'ground' or t == 'torch' then
                    local tx, ty = (col - 1) * ts, (row - 1) * ts

                    if #bushes > 0 and hash(col, row, 1) < cfg.bushChance then
                        local p = pick(bushes, hash(col, row, 2))
                        props[#props + 1] = {
                            def = p,
                            x = tx + (hash(col, row, 3) - 0.5) * (ts - p.w + 12),
                            y = ty + (hash(col, row, 4) - 0.5) * (ts - p.h + 12),
                            phase = hash(col, row, 5) * 6.28,
                        }
                    else
                        -- up to 3 small props per tile, each rolled on its own
                        for slot = 1, 3 do
                            if hash(col, row, 10 + slot) < cfg.density then
                                local kindRoll = hash(col, row, 20 + slot)
                                local bucket = (kindRoll < cfg.rockShare)
                                    and rocks or grass
                                if #bucket == 0 then
                                    bucket = (#grass > 0) and grass or rocks
                                end
                                if #bucket > 0 then
                                    local p = pick(bucket, hash(col, row, 30 + slot))
                                    props[#props + 1] = {
                                        def = p,
                                        x = tx + hash(col, row, 40 + slot) * (ts - p.w),
                                        y = ty + hash(col, row, 50 + slot) * (ts - p.h),
                                        phase = hash(col, row, 60 + slot) * 6.28,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #props > 0 then
        -- lower props drawn last so they overlap the ones behind them
        table.sort(props, function(a, b)
            local ay, by = a.y + a.def.h, b.y + b.def.h
            if ay == by then return a.x < b.x end
            return ay < by
        end)
        self.mesh = self:bake(props)
    end

    return self
end

-- One static mesh for every scattered prop: each sprite becomes a stack of
-- horizontal slices, quantized to the sheet's texel centers so nearest-neighbor
-- sampling can't bleed a neighboring cell in once the wind moves vertices.
function Decor:bake(props)
    local img = Assets.spritesheet
    local iw, ih = img:getDimensions()
    local stiffness = TUNE.props.wind.stiffness

    local verts = {}
    local n = 0

    for _, prop in ipairs(props) do
        local d = prop.def
        local segs = d.wind and (d.h >= 32 and SEGMENTS_BIG or SEGMENTS_SMALL) or 1
        local u0, u1 = d.x / iw, (d.x + d.w) / iw
        local px, py = prop.x, prop.y
        -- cell inset to texel centers: the clamp range for the pixel shader
        local bx0, by0 = (d.x + 0.5) / iw, (d.y + 0.5) / ih
        local bx1, by1 = (d.x + d.w - 0.5) / iw, (d.y + d.h - 0.5) / ih

        local function vertex(x, y, u, v, w)
            n = n + 1
            verts[n] = { x, y, u, v, w, prop.phase, bx0, by0, bx1, by1 }
        end

        for i = 0, segs - 1 do
            local f0, f1 = i / segs, (i + 1) / segs
            local y0, y1 = py + d.h * f0, py + d.h * f1
            local v0 = (d.y + d.h * f0) / ih
            local v1 = (d.y + d.h * f1) / ih
            local w0, w1 = 0, 0
            if d.wind then
                w0 = bendWeight(d.h * (1 - f0), d.h, d.stem, stiffness)
                w1 = bendWeight(d.h * (1 - f1), d.h, d.stem, stiffness)
            end

            vertex(px,       y0, u0, v0, w0)
            vertex(px + d.w, y0, u1, v0, w0)
            vertex(px + d.w, y1, u1, v1, w1)

            vertex(px,       y0, u0, v0, w0)
            vertex(px + d.w, y1, u1, v1, w1)
            vertex(px,       y1, u0, v1, w1)
        end
    end

    local mesh = love.graphics.newMesh(VERTEX_FORMAT, verts, 'triangles', 'static')
    mesh:setTexture(img)
    return mesh
end

function Decor:draw()
    local t = love.timer.getTime()

    if self.mesh then
        local w = TUNE.props.wind
        local prev = love.graphics.getShader()
        love.graphics.setShader(shader)
        shader:send('t', t)
        shader:send('sway', { w.amp, w.speed, w.gustAmp, w.gustSpeed })
        shader:send('gustWave', w.gustWave)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(self.mesh)
        love.graphics.setShader(prev)
    end

    -- torches pulse with their flame instead of sitting flat
    local torch = self.scenery.torch
    if torch then
        local ft = t * TUNE.lighting.torchFlickerSpeed
        for _, e in ipairs(self.torches) do
            local b = 1 + (love.math.noise(ft + e.phase) - 0.5) * TUNE.props.torchPulse
            love.graphics.setColor(b, b, b)
            if e.flip then
                love.graphics.draw(Assets.spritesheet, torch, e.x + 32, e.y, 0, -1, 1)
            else
                love.graphics.draw(Assets.spritesheet, torch, e.x, e.y)
            end
        end
        love.graphics.setColor(1, 1, 1)
    end
end

return Decor
