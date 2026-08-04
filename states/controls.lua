-- Pre-run controls splash: keyboard keys + mouse drawn in the menu theme.
-- Menu fades here instead of straight into the run; any key / click starts
-- the run (after a short arm delay so the menu click can't skip it), ESC
-- goes back. Restart from the death screen skips this on purpose.

local State = require('core.state')
local Theme = require('ui.theme')
local Audio = require('core.audio')

local controls = {}
controls.fxMode = 'menu'

function controls:enter(opts)
    self.opts = opts
    self.t = 0
end

function controls:update(dt)
    self.t = self.t + dt
end

-- One keycap: drop shadow, dark face, light border, centered letter
local function drawKey(cx, cy, w, h, label)
    local x, y = cx - w / 2, cy - h / 2
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle('fill', x + 4, y + 5, w, h, 6, 6)
    love.graphics.setColor(0.11, 0.11, 0.13)
    love.graphics.rectangle('fill', x, y, w, h, 6, 6)
    local c = Theme.colors.text
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.rectangle('line', x, y, w, h, 6, 6)
    local f = Theme.fonts.hud
    love.graphics.setFont(f)
    love.graphics.print(label, math.floor(cx - f:getWidth(label) / 2),
        math.floor(cy - f:getHeight() / 2))
end

-- Mouse: outlined body, button pads inside. Left pad and wheel are color-coded
-- to the legend drawn next to it (blood = shoot, purple = switch weapon).
local function drawMouse(cx, top, w, h)
    local x = cx - w / 2
    local r = w * 0.42
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle('fill', x + 4, top + 5, w, h, r, r)
    love.graphics.setColor(0.11, 0.11, 0.13)
    love.graphics.rectangle('fill', x, top, w, h, r, r)
    local c = Theme.colors.text
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.rectangle('line', x, top, w, h, r, r)

    -- pads inset enough to clear the body's rounded top corners
    local inset, padTop, btnH = 18, top + 16, h * 0.26
    local padW = w / 2 - inset - 8
    local blood = Theme.colors.blood
    love.graphics.setColor(blood[1], blood[2], blood[3])
    love.graphics.rectangle('fill', x + inset, padTop, padW, btnH, 8, 8)
    love.graphics.setColor(0.22, 0.21, 0.22)
    love.graphics.rectangle('fill', cx + 8, padTop, padW, btnH, 8, 8)
    local wheel = Theme.colors.nightmare
    love.graphics.setColor(wheel[1], wheel[2], wheel[3])
    love.graphics.rectangle('fill', cx - 6, padTop + 4, 12, btnH + 8, 6, 6)
end

-- Right-aligned legend row: color swatch + action label, ending at rightX
local function legendRow(str, color, rightX, y)
    local f = Theme.fonts.hud
    love.graphics.setFont(f)
    local tw = f:getWidth(str)
    love.graphics.setColor(color[1], color[2], color[3])
    love.graphics.rectangle('fill', rightX - tw - 26, y + 1, 12, 12)
    local c = Theme.colors.text
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.print(str, rightX - tw, y)
end

-- Plain action label to the right of a key/cluster
local function actionLabel(str, x, y)
    local f = Theme.fonts.hud
    love.graphics.setFont(f)
    local c = Theme.colors.text
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.print(str, x, math.floor(y - f:getHeight() / 2))
end

function controls:draw()
    Theme.drawBackground()
    love.graphics.setLineWidth(2)

    Theme.drawTitle(T('controls.title'), 90)

    -- WASD cluster (left)
    local key, gap = 64, 10
    drawKey(340, 320, key, key, 'W')
    drawKey(340 - key - gap, 394, key, key, 'A')
    drawKey(340, 394, key, key, 'S')
    drawKey(340 + key + gap, 394, key, key, 'D')
    actionLabel(T('controls.move'), 480, 358)

    -- SHIFT under the cluster, left-aligned with A
    drawKey(266 - key / 2 + 85, 505, 170, 56, 'SHIFT')
    actionLabel(T('controls.sprint'), 480, 505)

    -- Mouse (right) + color-coded legend
    drawMouse(900, 290, 120, 185)
    legendRow(T('controls.shoot'), Theme.colors.blood, 810, 315)
    legendRow(T('controls.weapon'), Theme.colors.nightmare, 810, 360)

    -- Extras row: Q and T
    local f = Theme.fonts.hud
    local kw, kGap, gGap, y = 48, 18, 90, 700
    local w1 = kw + kGap + f:getWidth(T('controls.knife'))
    local w2 = kw + kGap + f:getWidth(T('controls.chat'))
    local x = (SCREENWIDTH - (w1 + gGap + w2)) / 2
    drawKey(x + kw / 2, y, kw, kw, 'Q')
    actionLabel(T('controls.knife'), x + kw + kGap, y)
    drawKey(x + w1 + gGap + kw / 2, y, kw, kw, 'T')
    actionLabel(T('controls.chat'), x + w1 + gGap + kw + kGap, y)

    -- Pulsing start prompt
    local fi = Theme.fonts.item
    love.graphics.setFont(fi)
    local msg = T('controls.start')
    local a = 0.55 + 0.45 * math.sin(self.t * 4)
    local b = Theme.colors.blood
    love.graphics.setColor(b[1], b[2], b[3], a)
    love.graphics.print(msg, SCREENWIDTH / 2 - fi:getWidth(msg) / 2, 850)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

local function beginRun(self)
    if self.t < TUNE.controlsScreen.minShowTime then return end
    if State.fading() then return end
    Audio.play(TUNE.start.sound, TUNE.start.soundGain, true)
    State.fadeTo('playing', self.opts)
end

function controls:keypressed(key)
    if key == 'escape' then
        if not State.fading() then State.fadeTo('menu') end
        return
    end
    beginRun(self)
end

function controls:mousepressed() beginRun(self) end
function controls:wheelmoved() beginRun(self) end

return controls
