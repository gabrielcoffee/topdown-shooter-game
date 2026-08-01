-- Permanent ground decals: blood splats left where zombies get hurt and die.
-- Stamped into a SpriteBatch (one draw call however many there are) and kept
-- for the whole run. Never lands on a solid/void tile — blood stays on floor.
--
-- Art: four 16x16 cells on the spritesheet right after the lock, starting at
-- (256, 0). Until those cells are painted, procedural splats stand in, so the
-- feature works either way and the art takes over the moment it's exported.

local Assets = require('core.assets')

local Decals = {}
Decals.__index = Decals

local CELLS = { { 256, 0 }, { 272, 0 }, { 288, 0 }, { 304, 0 } }

-- Procedural stand-in: 4 dark-red splats (blob + satellite droplets)
local function fallbackSheet()
    local data = love.image.newImageData(64, 16)
    local rng = love.math.newRandomGenerator(7)
    for v = 0, 3 do
        local ox = v * 16
        local function blob(cx, cy, r, shade)
            for y = math.floor(cy - r), math.ceil(cy + r) do
                for x = math.floor(cx - r), math.ceil(cx + r) do
                    if x >= 0 and x <= 15 and y >= 0 and y <= 15 then
                        local dx, dy = x - cx, y - cy
                        if dx * dx + dy * dy <= r * r then
                            data:setPixel(ox + x, y, 0.45 * shade, 0.04, 0.04, 1)
                        end
                    end
                end
            end
        end
        blob(7 + rng:random(-1, 1), 7 + rng:random(-1, 1), 3.2 + rng:random() * 1.5, 1)
        for _ = 1, 4 + rng:random(3) do
            blob(rng:random(2, 13), rng:random(2, 13), 0.8 + rng:random() * 1.2,
                0.75 + rng:random() * 0.4)
        end
    end
    return love.graphics.newImage(data)
end

function Decals.new(map)
    local self = setmetatable({}, Decals)
    self.map = map

    -- sheet cells painted? use them; otherwise the procedural stand-in
    local data = love.image.newImageData('assets/spritesheet.png')
    local painted = true
    for _, c in ipairs(CELLS) do
        local any = false
        for y = c[2], c[2] + 15 do
            for x = c[1], c[1] + 15 do
                local _, _, _, a = data:getPixel(x, y)
                if a > 0 then any = true break end
            end
            if any then break end
        end
        if not any then painted = false break end
    end

    local image = Assets.spritesheet
    self.quads = {}
    if painted then
        for i, c in ipairs(CELLS) do
            self.quads[i] = love.graphics.newQuad(c[1], c[2], 16, 16, image)
        end
    else
        image = fallbackSheet()
        for i = 1, 4 do
            self.quads[i] = love.graphics.newQuad((i - 1) * 16, 0, 16, 16, image)
        end
    end

    self.max = TUNE.fx.decalMax
    self.batch = love.graphics.newSpriteBatch(image, self.max, 'static')
    self.ids = {}   -- ring buffer of batch ids; oldest overwritten when full
    self.next = 1
    return self
end

-- Stamp a splat centered on (x, y); skipped when the spot is wall/void
function Decals:add(x, y)
    if self.map:isSolidAt(x, y) then return end
    local quad = self.quads[love.math.random(#self.quads)]
    local sx = love.math.random() < 0.5 and -1 or 1 -- mirrored variants for free
    local sy = love.math.random() < 0.5 and -1 or 1
    local args = { quad, math.floor(x), math.floor(y), 0, sx, sy, 8, 8 }
    if self.ids[self.next] then
        self.batch:set(self.ids[self.next], unpack(args))
    else
        self.ids[self.next] = self.batch:add(unpack(args))
    end
    self.next = self.next % self.max + 1
end

function Decals:draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.batch)
end

return Decals
