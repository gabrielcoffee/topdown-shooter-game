local World = require('core.world')
local Menu = require('menu')

_G.SCALE = 2
_G.GAMESTATES = {
    gameplay = 1,
    menu = 2,
}

local gameState = GAMESTATES.menu

_G.world = nil

function love.load()
    love.mouse.setVisible(true)
    love.math.setRandomSeed(os.time())

    world = World:new()
end

function love.update(dt)

    world:update(dt)

    if love.keyboard.isDown('escape') then
        gameState = gameState == GAMESTATES.gameplay and GAMESTATES.menu or GAMESTATES.gameplay        
    end
end

function love.draw()

    world:draw()
end