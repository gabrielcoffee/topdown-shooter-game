-- Gameplay state: owns the world. Pause pushes on top (world freezes),
-- death pushes the gameover overlay. The dev chat (ui/chat.lua) lives here
-- and does NOT pause the world — the game keeps running while typing.

local State = require('core.state')
local World = require('core.world')
local Fx = require('ui.fx')
local Chat = require('ui.chat')
local Audio = require('core.audio')
local Input = require('core.input')

local playing = {}
playing.fxMode = 'game'

function playing:enter(opts)
    opts = opts or {}
    Chat.close()
    world = World:new(opts)
    if opts.run then
        -- a hand-edited or outdated run.lua must not crash Continue: dump the
        -- bad save and fall back to a fresh run
        local ok, err = pcall(world.restore, world, opts.run)
        if not ok then
            print('[save] bad run file, starting fresh: ' .. tostring(err))
            require('core.save').deleteRun()
            world = World:new(opts)
        end
    end
    -- run start: audio + image rise from black together; the wave banner
    -- waits out the same window (waves pregame hold)
    self.startFade = TUNE.start.fadeTime
    Audio.fadeIn(TUNE.start.fadeTime)
    Audio.playAmbience(world.ambience)
    Audio.setMusicTarget(0) -- menu music ducks out fast for gameplay
end

-- leaving the run: critical-health overlay + heartbeat must not follow us out
function playing:exit()
    Fx.setLowHealth(false)
    Fx.setBleedout(0)
    Audio.setLowHealth(false)
end

function playing:update(dt)
    -- OS cursor off in gameplay: the crosshair IS the cursor. Set every frame
    -- so popping back from pause/options (which show the cursor) restores it.
    -- The chat needs a real pointer to select text with, so it gets one back.
    love.mouse.setVisible(Chat.open)

    self.startFade = math.max(0, (self.startFade or 0) - dt)

    Chat.update(dt)
    -- local player's buttons + aim for this frame, read once here so
    -- Player:update never touches the keyboard directly (see core/input.lua)
    Input.poll(world.player.input, world.camX, world.camY, Chat.open)
    world:update(dt)

    -- Closing a browser tab never fires love.quit, so the desktop contract
    -- ("close the window mid-run, Continue picks it up") has to be a timer
    -- there instead. index.html flushes the save dir to IndexedDB.
    if WEB and not world.gameOver then
        self.autosave = (self.autosave or TUNE.autosaveInterval) - dt
        if self.autosave <= 0 then
            self.autosave = TUNE.autosaveInterval
            if world.player and world.player.health > 0 then
                require('core.save').saveRun(world:serialize())
            end
        end
    end

    if world.gameOver then
        Chat.close() -- key repeat off before the menu takes over
        State.push('gameover')
    end
end

function playing:draw()
    world:draw()
    Chat.draw()

    -- run-start fade from black, in step with the audio fade
    if self.startFade and self.startFade > 0 then
        love.graphics.setColor(0, 0, 0, self.startFade / TUNE.start.fadeTime)
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)
    end
end

function playing:textinput(t)
    Chat.textinput(t)
end

-- While the console is open the mouse belongs to it (text selection); the
-- player already ignores clicks whenever Chat.open.
function playing:mousepressed(x, y, btn)
    Chat.mousepressed(x, y, btn)
end

function playing:mousemoved(x, y)
    Chat.mousemoved(x, y)
end

function playing:mousereleased(x, y, btn)
    Chat.mousereleased(x, y, btn)
end

-- Wheel up = previous slot, wheel down = next (Minecraft direction)
function playing:wheelmoved(_, dy)
    if Chat.open or dy == 0 or world.gameOver then return end
    world.player:scrollSlot(dy > 0 and -1 or 1)
end

function playing:keypressed(key)
    if Chat.open then
        Chat.keypressed(key)
        return
    end

    -- P pauses as well as Escape, and is the only one that works in a browser:
    -- the tab owns Escape (it exits fullscreen) and never forwards it to us.
    if key == 'escape' or (WEB and key == 'p') then
        State.push('paused')
    elseif key == 't' and TUNE.dev and TUNE.dev.enabled then
        -- T is the only opener: Enter and ` were too easy to hit mid-wave,
        -- and they kill all gameplay input until Esc
        Chat.openChat()
    elseif key == 'h' then
        showHitboxes = not showHitboxes
    elseif key == 'u' then
        -- reload tune.lua and restart the run with the new values
        package.loaded['tune'] = nil
        TUNE = require('tune')
        require('core.web').applyTune(TUNE) -- reload must not restore desktop values
        Fx.refresh()
        require('core.gif').clearCache() -- edited gifs get re-decoded too
        world = World:new({})
        Audio.playAmbience(world.ambience)
    end
end

return playing
