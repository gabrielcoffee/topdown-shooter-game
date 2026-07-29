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
    love.mouse.setVisible(true)
    Save.deleteRun()

    -- run stats vs the all-time record (world is still frozen underneath)
    self.score = math.floor(world.player.earnedTotal or 0)
    self.kills = world.kills or 0
    local best = Save.loadBest()
    self.newRecord = self.score > best.score
    self.best = math.max(best.score, self.score)
    if self.newRecord or self.kills > best.kills then
        Save.saveBest({ score = self.best, kills = math.max(best.kills, self.kills) })
    end

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

    -- run stats: score / record / kills, record goes gold on a new best
    local function centered(text, y, r, g, b)
        love.graphics.setColor(r, g, b)
        love.graphics.print(text, SCREENWIDTH / 2 - font:getWidth(text) / 2, y)
    end
    centered(T('gameover.score', self.score), 430, 1, 1, 1)
    if self.newRecord then
        centered(T('gameover.newrecord'), 466, 1, 0.85, 0.3)
    else
        centered(T('gameover.record', self.best), 466, 1, 0.85, 0.3)
    end
    centered(T('gameover.kills', self.kills), 502, 0.8, 0.8, 0.8)
    love.graphics.setColor(1, 1, 1)

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
