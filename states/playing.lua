-- Gameplay state: owns the world. Pause pushes on top (world freezes),
-- death pushes the gameover overlay.

local State = require('core.state')
local World = require('core.world')
local Fx = require('ui.fx')

local playing = {}
playing.fxMode = 'game'

function playing:enter(opts)
    opts = opts or {}
    world = World:new()
    if opts.run then
        world:restore(opts.run)
    end
end

function playing:update(dt)
    world:update(dt)

    if world.gameOver then
        State.push('gameover')
    end
end

function playing:draw()
    world:draw()
end

function playing:keypressed(key)
    if key == 'escape' then
        State.push('paused')
    elseif key == '`' and TUNE.dev and TUNE.dev.enabled then
        State.push('console')
    elseif key == 'h' then
        showHitboxes = not showHitboxes
    elseif key == 'u' then
        -- reload tune.lua and restart the run with the new values
        package.loaded['tune'] = nil
        TUNE = require('tune')
        Fx.refresh()
        world = World:new()
    end
end

return playing
