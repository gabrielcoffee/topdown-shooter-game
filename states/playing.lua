-- Gameplay state: owns the world. Pause pushes on top (world freezes),
-- death pushes the gameover overlay. The dev chat (ui/chat.lua) lives here
-- and does NOT pause the world — the game keeps running while typing.

local State = require('core.state')
local World = require('core.world')
local Fx = require('ui.fx')
local Chat = require('ui.chat')

local playing = {}
playing.fxMode = 'game'

function playing:enter(opts)
    opts = opts or {}
    Chat.close()
    world = World:new()
    if opts.run then
        world:restore(opts.run)
    end
end

function playing:update(dt)
    -- OS cursor off in gameplay: the crosshair IS the cursor. Set every frame
    -- so popping back from pause/options (which show the cursor) restores it.
    love.mouse.setVisible(false)

    Chat.update(dt)
    world:update(dt)

    if world.gameOver then
        Chat.close() -- key repeat off before the menu takes over
        State.push('gameover')
    end
end

function playing:draw()
    world:draw()
    Chat.draw()
end

function playing:textinput(t)
    Chat.textinput(t)
end

function playing:keypressed(key)
    if Chat.open then
        Chat.keypressed(key)
        return
    end

    if key == 'escape' then
        State.push('paused')
    elseif (key == 't' or key == '`' or key == 'return')
        and TUNE.dev and TUNE.dev.enabled then
        Chat.openChat()
    elseif key == 'h' then
        showHitboxes = not showHitboxes
    elseif key == 'u' then
        -- reload tune.lua and restart the run with the new values
        package.loaded['tune'] = nil
        TUNE = require('tune')
        Fx.refresh()
        require('core.gif').clearCache() -- edited gifs get re-decoded too
        world = World:new()
    end
end

return playing
