-- Menu look & feel: pixel fonts, colors, vignette, title.
-- Everything here draws in native resolution (1280x960), like the HUD.

local Theme = {}

Theme.gameTitle = 'DEADWAVE' -- shown on the main menu; change freely

Theme.fonts = {
    title = love.graphics.newFont('assets/fonts/PressStart2P-Regular.ttf', 48),
    item  = love.graphics.newFont('assets/fonts/PressStart2P-Regular.ttf', 20),
    hint  = love.graphics.newFont('assets/fonts/PressStart2P-Regular.ttf', 12),
    hud   = love.graphics.newFont('assets/fonts/PressStart2P-Regular.ttf', 14),
}

Theme.colors = {
    blood    = {0.78, 0.08, 0.10},
    nightmare = {0.62, 0.14, 0.80}, -- purple wave banner on nightmare waves
    bloodDim = {0.45, 0.06, 0.08},
    text     = {0.85, 0.82, 0.78},
    textDim  = {0.45, 0.43, 0.40},
    bg       = {0.04, 0.04, 0.05},
    barBack  = {0.16, 0.15, 0.16},
}

-- Radial vignette mesh: transparent inner ring -> dark outer ring, built once
local vignette
local function buildVignette()
    local cx, cy = SCREENWIDTH / 2, SCREENHEIGHT / 2
    local rIn = math.min(cx, cy) * 0.55
    local rOut = math.sqrt(cx * cx + cy * cy) * 1.05
    local seg = 48
    local verts = {}
    for i = 0, seg do
        local a = (i / seg) * math.pi * 2
        local ca, sa = math.cos(a), math.sin(a)
        -- triangle strip: inner (alpha 0), outer (dark)
        table.insert(verts, {cx + ca * rIn, cy + sa * rIn, 0, 0, 0, 0, 0, 0})
        table.insert(verts, {cx + ca * rOut, cy + sa * rOut, 0, 0, 0, 0, 0, 0.85})
    end
    vignette = love.graphics.newMesh(verts, 'strip', 'static')
end

function Theme.drawVignette()
    if not vignette then buildVignette() end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(vignette)
end

-- Faint CRT scanlines over the whole screen
function Theme.drawScanlines()
    love.graphics.setColor(0, 0, 0, 0.12)
    for y = 0, SCREENHEIGHT, 4 do
        love.graphics.rectangle('fill', 0, y, SCREENWIDTH, 1)
    end
    love.graphics.setColor(1, 1, 1)
end

function Theme.drawBackground()
    local c = Theme.colors.bg
    love.graphics.clear(c[1], c[2], c[3])
end

-- Big blood-red title with a hard drop shadow, centered at y
function Theme.drawTitle(text, y, color, alpha)
    local f = Theme.fonts.title
    love.graphics.setFont(f)
    local x = SCREENWIDTH / 2 - f:getWidth(text) / 2
    alpha = alpha or 1

    love.graphics.setColor(0, 0, 0, 0.9 * alpha)
    love.graphics.print(text, x + 5, y + 5)

    local c = color or Theme.colors.blood
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.print(text, x, y)
    love.graphics.setColor(1, 1, 1)
end

-- Small centered helper text (controls hint, subtitle)
function Theme.drawHint(text, y, color)
    local f = Theme.fonts.hint
    love.graphics.setFont(f)
    local c = color or Theme.colors.textDim
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.print(text, SCREENWIDTH / 2 - f:getWidth(text) / 2, y)
    love.graphics.setColor(1, 1, 1)
end

-- Dim the frame below an overlay state
function Theme.drawDim(alpha)
    love.graphics.setColor(0, 0, 0, alpha or 0.75)
    love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
    love.graphics.setColor(1, 1, 1)
end

return Theme
