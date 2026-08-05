-- Main menu: dark arcade splash. Title slams down, menu items stagger in,
-- embers and fog drift through, the whole frame goes through the CRT chain.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Fx = require('ui.fx')
local Particles = require('ui.particles')
local flux = require('lib.flux')
local Audio = require('core.audio')

local menu = {}
menu.fxMode = 'menu'

function menu:enter()
    Audio.stopAmbience()
    Audio.cancelFade() -- a run that died mid-fade must not mute menu clicks
    Audio.setMusicTarget(1) -- music fades back in (slow)
    local items = {}

    if Save.runExists() then
        table.insert(items, {
            label = 'menu.continue', type = 'action',
            activate = function()
                State.fadeTo('controls', { run = Save.loadRun() })
            end,
        })
    end

    table.insert(items, {
        label = 'menu.new_game', type = 'action',
        activate = function()
            State.fadeTo('controls')
        end,
    })
    table.insert(items, {
        label = 'menu.options', type = 'action',
        activate = function() State.push('options') end,
    })
    table.insert(items, {
        label = 'menu.quit', type = 'action',
        activate = function() love.event.quit() end,
    })

    self.list = MenuList:new(items, 500)

    -- title slams down from above
    self.titleY = -160
    self.time = 0
    flux.to(self, TUNE.fx.titleSlamTime, { titleY = 190 }):ease('quartin')

    -- eerie occasional letter glitch on the title
    self.glitch = { wait = TUNE.menu.glitchGapMin, active = 0, idx = 1, char = nil }
end

local GLITCH_POOL = '#%@!$&0139XZ?/'

local function updateGlitch(self, dt)
    local G, M = self.glitch, TUNE.menu
    if G.active > 0 then
        G.active = G.active - dt
        return
    end
    G.wait = G.wait - dt
    if G.wait > 0 then return end
    G.wait = M.glitchGapMin + love.math.random() * (M.glitchGapMax - M.glitchGapMin)
    G.active = M.glitchTime
    repeat -- never pick the space
        G.idx = love.math.random(#Theme.gameTitle)
    until Theme.gameTitle:sub(G.idx, G.idx) ~= ' '
    G.char = nil
    if love.math.random() < M.glitchSwapChance then
        local i = love.math.random(#GLITCH_POOL)
        G.char = GLITCH_POOL:sub(i, i)
    end
end

-- Per-letter title draw (PressStart2P is monospace, so layout stays put):
-- the glitched letter jitters, may show a wrong glyph, gets a pale ghost.
local function drawGlitchTitle(self, y, alpha)
    local f = Theme.fonts.title
    love.graphics.setFont(f)
    local text = Theme.gameTitle
    local x = SCREENWIDTH / 2 - f:getWidth(text) / 2
    local G, c = self.glitch, Theme.colors.blood
    for i = 1, #text do
        local ch = text:sub(i, i)
        local dx, dy = 0, 0
        local glitching = G.active > 0 and i == G.idx
        if glitching then
            local amp = TUNE.menu.glitchAmp
            dx = (love.math.random() * 2 - 1) * amp
            dy = (love.math.random() * 2 - 1) * amp
            if G.char then ch = G.char end
        end
        love.graphics.setColor(0, 0, 0, 0.9 * alpha)
        love.graphics.print(ch, x + dx + 5, y + dy + 5)
        if glitching then -- pale split ghost behind the torn letter
            love.graphics.setColor(0.9, 0.9, 0.95, 0.35 * alpha)
            love.graphics.print(ch, x - dx, y + dy + 2)
        end
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.print(ch, x + dx, y + dy)
        x = x + f:getWidth(text:sub(i, i))
    end
    love.graphics.setColor(1, 1, 1)
end

function menu:update(dt)
    self.time = self.time + dt
    self.list:update(dt)
    Particles.update(dt)
    updateGlitch(self, dt)
end

function menu:draw()
    Theme.drawBackground()

    Particles.drawFog()

    -- slight neon flicker on the title
    local flicker = 0.86 + 0.14 * love.math.noise(self.time * 7)
    drawGlitchTitle(self, self.titleY, flicker)

    self.list:draw()
    Theme.drawHint(T('menu.hint'), SCREENHEIGHT - 60)

    Particles.drawEmbers()
end

function menu:keypressed(key)
    self.list:keypressed(key)
end

function menu:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function menu:mousemoved(x, y) self.list:mousemoved(x, y) end
function menu:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return menu
