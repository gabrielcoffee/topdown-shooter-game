_G.TUNE = require('tune')
local World = require('core.world')

_G.SCALE = 2
_G.GAMESTATES = {
    gameplay = 1,
    menu = 2,
}

_G.font = love.graphics.newFont(18)
_G.smallFont = love.graphics.newFont(8) -- for labels drawn in scaled world space
love.graphics.setFont(font)
local gameState = GAMESTATES.menu

_G.world = nil

function love.load()
    love.mouse.setVisible(true)
    love.math.setRandomSeed(os.time())

    world = World:new()
end

function love.update(dt)

    if world.gameOver then
        if love.keyboard.isDown('r') then
            world = World:new()
        end
        return
    end

    world:update(dt)

    if love.keyboard.isDown('escape') then
        print('oi')
    end
end

_G.showHitboxes = false

function love.keypressed(key)
    if key == 'z' and not world.gameOver then
        world:spawnTestZombies()
    elseif key == 'h' then
        showHitboxes = not showHitboxes
    elseif key == 'u' then
        -- reload tune.lua and restart the run with the new values
        package.loaded['tune'] = nil
        TUNE = require('tune')
        world = World:new()
    end
end

function love.draw()
    world:draw()

    if world.gameOver then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)

        local title = 'YOU DIED'
        local hint = 'press R to restart'
        love.graphics.print(title, SCREENWIDTH/2 - font:getWidth(title)/2, SCREENHEIGHT/2 - 20)
        love.graphics.print(hint, SCREENWIDTH/2 - font:getWidth(hint)/2, SCREENHEIGHT/2 + 10)
    end
end