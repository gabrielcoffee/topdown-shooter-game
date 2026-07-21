-- Dynamic lighting wrapper around light_world.lua.
-- One instance per World run: ambient darkness, a light on the player,
-- and short-lived flash lights (muzzle flashes, explosions later).

local LightWorld = require('lib.light_world')

local Lighting = {}
Lighting.__index = Lighting

function Lighting.new()
    local self = setmetatable({}, Lighting)

    local a = TUNE.lighting.ambient
    self.lw = LightWorld({ ambient = { a, a, a } })
    self.lw:setShadowBlur(0) -- no shadow bodies yet; blur passes just cost FPS

    -- warm light following the player (intensity via color scale, full 1.0 blinds)
    local b = TUNE.lighting.playerBright
    self.playerLight = self.lw:newLight(0, 0, b, b * 0.88, b * 0.68, TUNE.lighting.playerRange)

    self.flashes = {} -- { light = <light>, t = secs left }
    return self
end

-- Short-lived point light (muzzle flash, blast). x/y in world coords.
function Lighting:flash(x, y, r, g, b, range, time)
    local light = self.lw:newLight(x, y, r, g, b, range)
    table.insert(self.flashes, { light = light, t = time })
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

    self.lw:update(dt)
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
