-- Gameover overlay: red flash on death, the death scene stays
-- frozen underneath, embers drift over. Entering deletes the run save.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Fx = require('ui.fx')
local Particles = require('ui.particles')
local flux = require('lib.flux')

local gameover = {}
gameover.overlay = true
gameover.fxMode = 'overlay'

function gameover:enter()
    Save.deleteRun()

    Fx.flash(0.55, 0.02, 0.02, 0.35)

    self.titleY = -160
    flux.to(self, TUNE.fx.titleSlamTime, { titleY = 320 }):ease('quartin')

    self.list = MenuList:new({
        {
            label = 'gameover.restart', type = 'action',
            activate = function() State.fadeTo('playing') end,
        },
        {
            label = 'gameover.quit', type = 'action',
            activate = function() State.fadeTo('menu') end,
        },
    }, 560)
end

function gameover:update(dt)
    self.list:update(dt)
    Particles.update(dt)
end

function gameover:draw()
    Theme.drawDim(0.78)
    love.graphics.setColor(0.35, 0, 0, 0.18) -- blood tint over the dim
    love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
    love.graphics.setColor(1, 1, 1)

    Theme.drawTitle(T('gameover.title'), self.titleY)
    self.list:draw()
    Particles.drawEmbers()
end

function gameover:keypressed(key)
    self.list:keypressed(key)
end

function gameover:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function gameover:mousemoved(x, y) self.list:mousemoved(x, y) end
function gameover:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return gameover
