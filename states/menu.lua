-- Main menu: texts over the fog haze, through the CRT chain (embers gone,
-- haze stays). Coming from the intro the typed title glides up into place;
-- the items NES-fade in at the bottom either way (same speed as the card).

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Particles = require('ui.particles')
local flux = require('lib.flux')
local Audio = require('core.audio')

local TITLE_Y = 190 -- the title's resting position

local menu = {}
menu.fxMode = 'menu'

function menu:enter(opts)
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
    -- LAN co-op is desktop-only: a browser tab cannot open a UDP socket, so
    -- love.js has no ENet and there is nothing to connect with
    if not WEB then
        table.insert(items, {
            label = 'menu.multiplayer', type = 'action',
            activate = function() State.fadeTo('multiplayer') end,
        })
    end
    table.insert(items, {
        label = 'menu.options', type = 'action',
        activate = function() State.push('options') end,
    })
    -- no QUIT in a browser tab: love.event.quit() there tears the game down
    -- and leaves a dead black canvas with no way back short of a page reload
    if not WEB then
        table.insert(items, {
            label = 'menu.quit', type = 'action',
            activate = function() love.event.quit() end,
        })
    end

    self.list = MenuList:new(items, 500)
    self.list.nesFade = true -- items fade in with the stepped intro fade

    self.time = 0
    if opts and opts.fromIntro then
        -- seamless handoff: the typed title starts where the intro drew it
        -- and glides up; the items wait until it has settled
        self.titleY = require('states.splash').titleY
        flux.to(self, TUNE.splash.titleGlide, { titleY = TITLE_Y }):ease('quartout')
        self.list.animT = -TUNE.splash.titleGlide
    else
        self.titleY = TITLE_Y
    end

    -- eerie occasional letter glitch on the title
    self.glitch = { wait = TUNE.menu.glitchGapMin, active = 0, idx = 1, char = nil }

    self.bestWave = Save.loadBest().wave -- 0 = never played, nothing shown

    -- music credit shows for a few seconds on every menu visit, then leaves
    self.creditT = 0
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
    -- credit clock only runs once the menu has started fading in
    if self.list.animT > 0 then
        self.creditT = self.creditT + dt
    end
end

function menu:draw()
    Theme.drawBackground()

    -- items, hint, record and the haze all fade in on the same stepped curve
    local ha = Theme.stepAlpha(math.max(0, math.min(1, self.list.animT / TUNE.menu.fadeInTime)))
    Particles.drawFog(ha) -- background haze (embers stay gone)

    -- slight neon flicker on the title
    local flicker = 0.86 + 0.14 * love.math.noise(self.time * 7)
    drawGlitchTitle(self, self.titleY, flicker)

    self.list:draw()
    local hc = Theme.colors.textDim
    local fh = Theme.fonts.hint
    love.graphics.setFont(fh)

    -- music credit, bottom center: shows for musicCreditTime secs per menu
    -- visit, fading out over the last musicCreditFade of that window
    local M = TUNE.menu
    local left = M.musicCreditTime - self.creditT
    if left > 0 then
        local a = ha * math.min(1, left / M.musicCreditFade)
        love.graphics.setColor(hc[1], hc[2], hc[3], a)
        local hint = T('menu.hint')
        love.graphics.print(hint, SCREENWIDTH / 2 - fh:getWidth(hint) / 2, SCREENHEIGHT - 60)
    end

    love.graphics.setColor(hc[1], hc[2], hc[3], ha)

    -- version, bottom right, always on
    local ver = Theme.version
    love.graphics.print(ver, SCREENWIDTH - fh:getWidth(ver) - 28, SCREENHEIGHT - 60)

    -- all-time wave record, top right (only once the player has played)
    if self.bestWave > 0 then
        local rec = T('gameover.record', self.bestWave)
        love.graphics.print(rec, SCREENWIDTH - fh:getWidth(rec) - 28, 28)
    end
    love.graphics.setColor(1, 1, 1)
end

function menu:keypressed(key)
    self.list:keypressed(key)
end

function menu:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function menu:mousemoved(x, y) self.list:mousemoved(x, y) end
function menu:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return menu
