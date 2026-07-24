-- Resolution / fullscreen scaler.
--
-- The whole game is drawn into a fixed-size *logical* canvas (SCREENWIDTH x
-- SCREENHEIGHT, 4:3). That canvas is blitted to the real window, scaled to fit
-- and centered, with black letterbox/pillarbox bars filling the remainder.
-- Window resolution and fullscreen only change the final blit — never the
-- layout, which stays pinned to the logical globals.
--
-- Only resolutions at least as tall as the logical canvas (960) are offered:
-- shorter windows leave the bottom of the canvas uncovered (light_world only
-- renders the scene as tall as the window), which read as a blue bar.

local Screen = {}

-- logical canvas size
local LOGICAL = { w = 1280, h = 960 }

-- windowed resolution presets (all >= 960 tall, so no uncovered blue bar)
Screen.resolutions = { '1920x1080', '2560x1440' }

local canvas
local rect = { x = 0, y = 0, scale = 1 }

local function parseRes(s)
    local w, h = tostring(s):match('(%d+)x(%d+)')
    return tonumber(w) or 1920, tonumber(h) or 1080
end

-- cycle helper for the graphics menu
function Screen.next(list, current, dir)
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i end end
    return list[((idx - 1 + dir) % #list) + 1]
end

-- Set the logical globals and (re)build the canvas.
function Screen.setLogical()
    SCREENWIDTH, SCREENHEIGHT = LOGICAL.w, LOGICAL.h
    canvas = love.graphics.newCanvas(LOGICAL.w, LOGICAL.h)
    canvas:setFilter('nearest', 'nearest')
end

-- Recompute the letterbox rect for the current window size.
function Screen.recompute()
    local ww, wh = love.graphics.getDimensions()
    local s = math.min(ww / SCREENWIDTH, wh / SCREENHEIGHT)
    rect.scale = s
    rect.x = math.floor((ww - SCREENWIDTH * s) / 2)
    rect.y = math.floor((wh - SCREENHEIGHT * s) / 2)
end

-- Apply a full graphics settings table: resolution, fullscreen.
-- Rebuilds the canvas, moonshine chain, and every SCREENWIDTH-derived asset.
function Screen.apply(settings)
    Screen.setLogical()

    local flags = {
        fullscreen = settings.fullscreen or false,
        fullscreentype = 'desktop',
        resizable = true,
        vsync = 1,
        highdpi = false,
        display = 2,
    }
    local w, h
    if settings.fullscreen then
        w, h = love.window.getDesktopDimensions(flags.display)
    else
        w, h = parseRes(settings.resolution)
    end
    love.window.setMode(w, h, flags)
    Screen.recompute()

    -- rebuild everything baked against the (possibly new) logical size
    require('ui.fx').resize(SCREENWIDTH, SCREENHEIGHT)
    require('core.assets').rebakeBg()
    require('ui.particles').load()

    -- keep a live run's light buffers pinned to the logical size (never the
    -- window) so fullscreen doesn't render light passes at native res = lag
    if world and world.lighting then
        world.lighting:resize(SCREENWIDTH, SCREENHEIGHT)
    end
end

-- Bind the logical canvas as the render target.
function Screen.attach()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
end

-- Blit the logical canvas to the window, scaled + centered, bars in black.
function Screen.present()
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, rect.x, rect.y, 0, rect.scale, rect.scale)
end

-- Window pixel coords -> logical canvas coords (for aim + menu clicks).
function Screen.toGame(x, y)
    return (x - rect.x) / rect.scale, (y - rect.y) / rect.scale
end

-- Current mouse position already mapped into logical space.
function Screen.mouse()
    return Screen.toGame(love.mouse.getPosition())
end

return Screen
