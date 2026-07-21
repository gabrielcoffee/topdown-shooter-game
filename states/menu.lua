-- Main menu: dark arcade splash. Continue only appears when a run save exists.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')

local menu = {}

function menu:enter()
    local items = {}

    if Save.runExists() then
        table.insert(items, {
            label = 'menu.continue', type = 'action',
            activate = function()
                State.switch('playing', { run = Save.loadRun() })
            end,
        })
    end

    table.insert(items, {
        label = 'menu.new_game', type = 'action',
        activate = function() State.switch('playing') end,
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
end

function menu:update(dt)
    self.list:update(dt)
end

function menu:draw()
    Theme.drawBackground()
    Theme.drawVignette()

    Theme.drawTitle(Theme.gameTitle, 190)
    Theme.drawHint(T('menu.subtitle'), 270, Theme.colors.bloodDim)

    self.list:draw()

    Theme.drawHint(T('menu.hint'), SCREENHEIGHT - 60)
    Theme.drawScanlines()
end

function menu:keypressed(key)
    self.list:keypressed(key)
end

function menu:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function menu:mousemoved(x, y) self.list:mousemoved(x, y) end
function menu:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return menu
