-- Gameover overlay: the death scene stays frozen underneath, tinted red.
-- Entering deletes the run save — no continuing a dead run.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')

local gameover = {}
gameover.overlay = true

function gameover:enter()
    Save.deleteRun()

    self.list = MenuList:new({
        {
            label = 'gameover.restart', type = 'action',
            activate = function() State.switch('playing') end,
        },
        {
            label = 'gameover.quit', type = 'action',
            activate = function() State.switch('menu') end,
        },
    }, 560)
end

function gameover:update(dt)
    self.list:update(dt)
end

function gameover:draw()
    Theme.drawDim(0.78)
    love.graphics.setColor(0.35, 0, 0, 0.18) -- blood tint over the dim
    love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
    love.graphics.setColor(1, 1, 1)

    Theme.drawVignette()
    Theme.drawTitle(T('gameover.title'), 320)
    self.list:draw()
    Theme.drawScanlines()
end

function gameover:keypressed(key)
    self.list:keypressed(key)
end

function gameover:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function gameover:mousemoved(x, y) self.list:mousemoved(x, y) end
function gameover:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return gameover
