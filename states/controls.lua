-- Pre-run controls splash: keyboard keys + mouse drawn in the menu theme.
-- Menu fades here instead of straight into the run; any key / click starts
-- the run (after a short arm delay so the menu click can't skip it), ESC
-- goes back. Restart from the death screen skips this on purpose.

local State = require('core.state')
local Theme = require('ui.theme')
local Audio = require('core.audio')
local Keybinds = require('core.keybinds')

local controls = {}
controls.fxMode = 'menu'

function controls:enter(opts)
    self.opts = opts
    self.t = 0
end

function controls:update(dt)
    self.t = self.t + dt
end

-- One keycap: drop shadow, dark face, light border, centered letter.
-- Widens past the requested w when a rebound key has a long name ('L SHIFT')
-- so the label never spills over the border.
local function drawKey(cx, cy, w, h, label)
    w = math.max(w, Theme.fonts.hud:getWidth(label) + 24)
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

    -- Movement cluster (left) -- labels come from the live binds, so a
    -- remapped layout shows the player's own keys, not hardcoded WASD
    local key, gap = 64, 10
    drawKey(340, 320, key, key, Keybinds.label('move_up'))
    drawKey(340 - key - gap, 394, key, key, Keybinds.label('move_left'))
    drawKey(340, 394, key, key, Keybinds.label('move_down'))
    drawKey(340 + key + gap, 394, key, key, Keybinds.label('move_right'))
    actionLabel(T('controls.move'), 480, 358)

    -- Sprint under the cluster, left-aligned with the left-move key
    drawKey(266 - key / 2 + 85, 505, 170, 56, Keybinds.label('sprint'))
    actionLabel(T('controls.sprint'), 480, 505)

    -- Mouse (right) + color-coded legend. Shooting rebound off the mouse
    -- names the key instead, so the drawing can't lie about it.
    drawMouse(900, 290, 120, 185)
    local shootLabel = T('controls.shoot')
    if Keybinds.get('shoot') ~= 'mouse1' then
        shootLabel = shootLabel .. ' [' .. Keybinds.label('shoot') .. ']'
    end
    legendRow(shootLabel, Theme.colors.blood, 810, 315)
    legendRow(T('controls.weapon'), Theme.colors.nightmare, 810, 360)

    -- Extras row: Q, T, and (browser only) P -- a tab keeps Escape for itself,
    -- so P is the only pause key that reaches the game there
    local f = Theme.fonts.hud
    local kw, kGap, gGap, y = 48, 18, 90, 700
    local row = { { Keybinds.label('quickknife'), T('controls.knife') } }
    -- chat only opens when the dev console is on, which the browser build
    -- turns off -- listing a key that does nothing there is worse than no key
    if TUNE.dev and TUNE.dev.enabled then
        table.insert(row, { Keybinds.label('chat'), T('controls.chat') })
    end
    if WEB then table.insert(row, { 'P', T('controls.pause') }) end

    local total = 0
    for i, e in ipairs(row) do
        -- caps grow with a rebound key's name, so the row has to measure the
        -- cap it will actually draw or long names overlap the next entry
        e.kw = math.max(kw, f:getWidth(e[1]) + 24)
        e.w = e.kw + kGap + f:getWidth(e[2])
        total = total + e.w + (i > 1 and gGap or 0)
    end
    local x = (SCREENWIDTH - total) / 2
    for _, e in ipairs(row) do
        drawKey(x + e.kw / 2, y, e.kw, kw, e[1])
        actionLabel(e[2], x + e.kw + kGap, y)
        x = x + e.w + gGap
    end

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
