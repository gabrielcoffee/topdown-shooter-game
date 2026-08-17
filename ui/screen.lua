-- Resolution / fullscreen scaler.
--
-- The game draws into a *logical* canvas that is then blitted to the window.
-- The canvas is 960 tall, ALWAYS, and its width follows the window's aspect
-- ratio. Since canvas aspect == window aspect, the blit fills the window
-- exactly and there are no bars at all on any normal display.
--
-- Height is what stays fixed, not width, because the map is authored to it:
-- SCALE is 2, so 960 logical px = 480 world px = exactly the height of the
-- shortest LDtk rooms (Room_0 is 640x480, Room_4 is 1280x480). Grow the view
-- vertically and World:cameraFor starts centering those rooms and showing the
-- nothing outside them. Growing horizontally is safe: wide windows simply see
-- further left and right in the rooms wide enough to allow it, and World:draw
-- masks whatever falls outside the current room.
--
-- Aspects outside 4:3..21:9 are clamped, so a freakishly tall or wide window
-- gets ordinary black bars rather than a broken view.

local Screen = {}

-- logical canvas: fixed height, width derived from the window
local LOGICAL_H = 960
local MIN_ASPECT = 4 / 3
local MAX_ASPECT = 21 / 9

-- Windowed presets. "native" tracks the desktop, which is what a laptop
-- actually wants; the rest are common window sizes. Any of them can be
-- dragged to any other size afterwards — nothing here is a supported-list.
Screen.resolutions = { 'native', '1280x960', '1600x900', '1920x1080', '2560x1440' }

-- A live drag delivers a resize event per frame. The blit rect is updated on
-- every one of them (cheap, and aim would drift otherwise), but reallocating
-- the canvas, the shader chain and the light buffers waits until the drag
-- settles.
local REBUILD_DELAY = 0.15
local pendingRebuild = nil

local canvas
local rect = { x = 0, y = 0, scale = 1 }

local function parseRes(s)
    if tostring(s) == 'native' then
        local dw, dh = love.window.getDesktopDimensions(
            select(3, love.window.getPosition()) or 1)
        -- leave room for the menu bar / taskbar, or the window opens clipped
        return dw, math.floor(dh * 0.92)
    end
    local w, h = tostring(s):match('(%d+)x(%d+)')
    return tonumber(w) or 1920, tonumber(h) or 1080
end

-- cycle helper for the graphics menu
function Screen.next(list, current, dir)
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i end end
    return list[((idx - 1 + dir) % #list) + 1]
end

-- Logical canvas size for a given window size. Width is rounded to an even
-- number so SCALE (2) divides it without leaving a half-pixel column.
function Screen.logicalFor(ww, wh)
    local aspect = math.max(MIN_ASPECT, math.min(ww / wh, MAX_ASPECT))
    return math.floor(LOGICAL_H * aspect / 2 + 0.5) * 2, LOGICAL_H
end

-- Set the logical globals and (re)build the canvas. Returns true if the size
-- actually changed, so callers can skip the expensive downstream rebuilds.
function Screen.setLogical(ww, wh)
    ww = ww or love.graphics.getWidth()
    wh = wh or love.graphics.getHeight()
    local w, h = Screen.logicalFor(ww, wh)
    if canvas and SCREENWIDTH == w and SCREENHEIGHT == h then return false end
    SCREENWIDTH, SCREENHEIGHT = w, h
    canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter('nearest', 'nearest')
    return true
end

-- Recompute the blit rect for the current window size. Cheap; safe every frame.
function Screen.recompute()
    local ww, wh = love.graphics.getDimensions()
    local s = math.min(ww / SCREENWIDTH, wh / SCREENHEIGHT)
    rect.scale = s
    rect.x = math.floor((ww - SCREENWIDTH * s) / 2)
    rect.y = math.floor((wh - SCREENHEIGHT * s) / 2)
end

-- Everything baked against the logical size. Called after the logical size
-- changes, and never during a drag.
local function rebuildDerived()
    require('ui.fx').resize(SCREENWIDTH, SCREENHEIGHT)
    require('core.assets').rebakeBg()
    require('ui.particles').load()

    -- keep a live run's light buffers pinned to the logical size (never the
    -- window) so fullscreen doesn't render light passes at native res = lag
    if world and world.lighting then
        world.lighting:resize(SCREENWIDTH, SCREENHEIGHT)
    end
end

-- love.resize: keep the rect honest now, schedule the heavy work for later.
function Screen.resized(ww, wh)
    Screen.recompute()
    pendingRebuild = REBUILD_DELAY
end

-- Ticked from love.update; fires the deferred rebuild once the drag settles.
function Screen.update(dt)
    if not pendingRebuild then return end
    pendingRebuild = pendingRebuild - dt
    if pendingRebuild > 0 then return end
    pendingRebuild = nil
    if Screen.setLogical() then rebuildDerived() end
    Screen.recompute()
end

-- Apply a full graphics settings table: resolution, fullscreen.
-- Rebuilds the canvas, moonshine chain, and every SCREENWIDTH-derived asset.
function Screen.apply(settings)
    -- stay on whatever display the window currently lives on — a hardcoded
    -- index yanks the window to that monitor on every apply (and only worked
    -- on single-display machines because LOVE clamps out-of-range indexes)
    local curDisplay = select(3, love.window.getPosition()) or 1

    -- Browsers only grant fullscreen from inside a user gesture, so a saved
    -- fullscreen=true applied during love.load is rejected and leaves the
    -- window in a mismatched mode. itch.io's own fullscreen button is the
    -- supported route in a tab.
    local wantFullscreen = settings.fullscreen and not WEB

    local flags = {
        fullscreen = wantFullscreen or false,
        fullscreentype = 'desktop',
        resizable = true,
        -- a floor, not a supported size: below this the HUD font stops being
        -- readable once the canvas is scaled down to fit
        minwidth = 960,
        minheight = 600,
        vsync = 1,
        highdpi = false,
        display = curDisplay,
    }
    local w, h
    if WEB then
        -- the canvas element IS the window; sizing it to the logical canvas
        -- means no letterbox bars and a 1:1 blit. index.html then scales the
        -- element with CSS to whatever the itch.io embed gives us.
        w, h = Screen.logicalFor(4, 3) -- browser build stays 4:3
    elseif wantFullscreen then
        w, h = love.window.getDesktopDimensions(curDisplay)
    else
        w, h = parseRes(settings.resolution)
    end
    local ok = love.window.setMode(w, h, flags)

    -- from the real window, not the requested size: a window manager is free
    -- to hand back something smaller than it was asked for, and on a laptop
    -- it usually does
    Screen.setLogical()
    Screen.recompute()
    rebuildDerived()
    pendingRebuild = nil

    return ok -- callers can roll back if the window refused the mode
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

-- For the fpsprobe diagnostic: what the window, the canvas and the light
-- buffers each think their size is. A mismatch is what a blue band was.
function Screen.debugSizes()
    local lw = world and world.lighting and world.lighting.lw
    return ('window=%dx%d logical=%dx%d blit=%.3f@%d,%d light=%s'):format(
        love.graphics.getWidth(), love.graphics.getHeight(),
        SCREENWIDTH, SCREENHEIGHT, rect.scale, rect.x, rect.y,
        lw and ('%dx%d'):format(lw.w or -1, lw.h or -1) or 'none')
end

return Screen
