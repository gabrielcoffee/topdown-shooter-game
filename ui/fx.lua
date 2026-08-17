-- Post-processing (moonshine) and screen flash.
-- One shared shader chain: menus run the full CRT arcade look,
-- gameplay disables crt/scanlines/chromasep so mouse aim stays true.

local moonshine = require('lib.moonshine')

local Fx = {}

local chain
local mode = nil
local flash = { t = 0, dur = 1, color = { 1, 1, 1 } }
local dmg = { t = 0 }  -- damage vignette timer
local dmgImage           -- radial red-rim gradient, built once

-- Small radial gradient (transparent core -> red rim), scaled to the screen
-- at draw time. Linear filter so the upscale stays smooth.
local function makeDamageVignette()
    local w, h = 320, 240
    local data = love.image.newImageData(w, h)
    local cx, cy = w / 2, h / 2
    local maxD = math.sqrt(cx * cx + cy * cy)
    data:mapPixel(function(x, y)
        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / maxD
        local a = math.max(0, d - 0.45) / 0.55 -- rim starts at 45% out
        return 0.75, 0.04, 0.04, a * a
    end)
    dmgImage = love.graphics.newImage(data)
    dmgImage:setFilter('linear', 'linear')
end

function Fx.load()
    local e = moonshine.effects
    chain = moonshine(e.glow)
        .chain(e.chromasep)
        .chain(e.scanlines)
        .chain(e.crt)
        .chain(e.vignette)
        .chain(e.filmgrain)
    makeDamageVignette()
    Fx.refresh()
end

-- Resize the shader chain's internal buffers to the logical canvas size, so the
-- CRT/scanline look scales with the game canvas, not the OS window.
function Fx.resize(w, h)
    if chain and chain.resize then chain.resize(w, h) end
    mode = nil -- force setMode to re-apply after a resize
end

-- (Re)apply tune values — called on load and on the U hot-reload
function Fx.refresh()
    local t = TUNE.fx
    chain.parameters = {
        glow = { strength = t.glowStrength, min_luma = t.glowMinLuma },
        chromasep = { radius = t.chromaRadius, angle = 0 },
        scanlines = { opacity = t.scanlineOpacity, thickness = 0.4 },
        crt = { distortionFactor = { t.crtDistortion, t.crtDistortion + 0.005 } },
        vignette = { opacity = t.vignetteOpacity },
        filmgrain = { opacity = t.grainOpacity },
    }
    mode = nil -- force setMode to re-apply
end

-- 'menu'    = full CRT arcade incl. glow (pure menu screens)
-- 'overlay' = CRT without glow (menus over the lit world; glow blooms
--             the light pool into a white wash and murders the framerate)
-- 'game'    = vignette + grain only, aim stays undistorted
function Fx.setMode(m)
    if m == mode then return end
    mode = m
    if m == 'menu' then
        chain.enable('crt', 'scanlines', 'chromasep', 'glow')
    elseif m == 'overlay' then
        chain.enable('crt', 'scanlines', 'chromasep')
        chain.disable('glow')
    else
        chain.disable('crt', 'scanlines', 'chromasep', 'glow')
    end
end

Fx.bypass = false -- dev switch: skip the whole shader chain

function Fx.draw(fn)
    if Fx.bypass then fn() return end
    chain.draw(fn)
end

function Fx.update(dt)
    flash.t = math.max(0, flash.t - dt)
    dmg.t = math.max(0, dmg.t - dt)
end

function Fx.flash(r, g, b, dur)
    flash.color = { r, g, b }
    flash.dur = dur or 0.25
    flash.t = flash.dur
end

-- Brief red rim around the screen edges when the player takes a hit
function Fx.damageVignette()
    dmg.t = TUNE.fx.damageVignetteTime
end

-- Critical health: constant red rim until healed (driven by World:update)
local lowHealth = false
function Fx.setLowHealth(on)
    lowHealth = on
end

-- Bleeding out on the floor in co-op: 0 = not down, 1 = about to die. Driven
-- by World:update from the bleed clock, and independent of the two above so
-- the strongest source wins rather than them fighting.
local bleedout = 0
function Fx.setBleedout(k)
    bleedout = k or 0
end

-- Drawn on top of the shader chain (flash stays undistorted)
function Fx.drawOverlays()
    -- red rim: constant floor while at critical health, hit pulse on top
    local a = lowHealth and TUNE.fx.lowHealthVignetteOpacity or 0
    if bleedout > 0 then a = math.max(a, bleedout) end
    if dmg.t > 0 then
        a = math.max(a, (dmg.t / TUNE.fx.damageVignetteTime) * TUNE.fx.damageVignetteOpacity)
    end
    if a > 0 and dmgImage then
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(dmgImage, 0, 0, 0,
            SCREENWIDTH / dmgImage:getWidth(), SCREENHEIGHT / dmgImage:getHeight())
        love.graphics.setColor(1, 1, 1)
    end
    if flash.t > 0 then
        local a = flash.t / flash.dur
        love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], a)
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)
    end
end

return Fx
