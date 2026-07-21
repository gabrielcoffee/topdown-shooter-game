-- Post-processing (moonshine), screen shake and screen flash.
-- One shared shader chain: menus run the full CRT arcade look,
-- gameplay disables crt/scanlines/chromasep so mouse aim stays true.

local moonshine = require('lib.moonshine')

local Fx = {}

local chain
local mode = nil
local shake = 0
local flash = { t = 0, dur = 1, color = { 1, 1, 1 } }

function Fx.load()
    local e = moonshine.effects
    chain = moonshine(e.glow)
        .chain(e.chromasep)
        .chain(e.scanlines)
        .chain(e.crt)
        .chain(e.vignette)
        .chain(e.filmgrain)
    Fx.refresh()
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
    shake = shake * math.max(0, 1 - TUNE.fx.shakeDecay * dt)
    if shake < 0.05 then shake = 0 end
    flash.t = math.max(0, flash.t - dt)
end

function Fx.addShake(amount)
    shake = math.min(shake + (amount or 0), 24)
end

function Fx.shakeOffset()
    if shake == 0 then return 0, 0 end
    return (love.math.random() * 2 - 1) * shake,
           (love.math.random() * 2 - 1) * shake
end

function Fx.flash(r, g, b, dur)
    flash.color = { r, g, b }
    flash.dur = dur or 0.25
    flash.t = flash.dur
end

-- Drawn on top of the shader chain (flash stays undistorted)
function Fx.drawOverlays()
    if flash.t > 0 then
        local a = flash.t / flash.dur
        love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], a)
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)
    end
end

return Fx
