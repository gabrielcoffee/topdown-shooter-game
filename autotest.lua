-- TEMPORARY dev-only harness (AUTOTEST=1 love .). Not part of the game.
local State = require('core.state')
local Fx = require('ui.fx')

local M = { t = 0, i = 1 }

local function key(k) love.keypressed(k) end
local function shot(name) love.graphics.captureScreenshot(name .. '.png') end

local steps = {
    {1.5, function()
        print('embers alive:', require('ui.particles').emberCount())
        shot('shot_menu')
    end},
    {1.7, function() Fx.bypass = true end},
    {1.8, function() shot('shot_menu_raw') end},
    {1.9, function() Fx.bypass = false end},
    {2.2, function() print('DONE'); love.event.quit() end},
}

function M.update(dt)
    love.mousemoved, love.mousepressed, love.mousereleased = nil, nil, nil
    M.t = M.t + dt
    while steps[M.i] and M.t >= steps[M.i][1] do
        local ok, err = pcall(steps[M.i][2])
        if not ok then print('AUTOTEST ERR', err) end
        M.i = M.i + 1
    end
end

return M
