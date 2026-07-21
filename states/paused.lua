-- Pause overlay: the frozen world stays visible, dimmed, underneath.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')

local paused = {}
paused.overlay = true
paused.fxMode = 'overlay'

function paused:enter()
    self.list = MenuList:new({
        {
            label = 'pause.resume', type = 'action',
            activate = function() State.pop() end,
        },
        {
            label = 'pause.options', type = 'action',
            activate = function() State.push('options') end,
        },
        {
            label = 'pause.save_quit', type = 'action',
            activate = function()
                Save.saveRun(world:serialize())
                State.fadeTo('menu')
            end,
        },
        {
            label = 'pause.quit', type = 'action',
            activate = function() State.fadeTo('menu') end,
        },
    }, 440)
end

function paused:update(dt)
    self.list:update(dt)
end

function paused:draw()
    Theme.drawDim(0.72)
    Theme.drawTitle(T('pause.title'), 280)
    self.list:draw()
end

function paused:keypressed(key)
    if key == 'escape' then
        State.pop()
    else
        self.list:keypressed(key)
    end
end

function paused:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function paused:mousemoved(x, y) self.list:mousemoved(x, y) end
function paused:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return paused
