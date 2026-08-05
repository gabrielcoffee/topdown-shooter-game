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
end

function menu:update(dt)
    self.time = self.time + dt
    self.list:update(dt)
    Particles.update(dt)
end

function menu:draw()
    Theme.drawBackground()

    Particles.drawFog()

    -- slight neon flicker on the title
    local flicker = 0.86 + 0.14 * love.math.noise(self.time * 7)
    Theme.drawTitle(Theme.gameTitle, self.titleY, nil, flicker, Theme.fonts.gameTitle)

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
