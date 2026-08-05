_G.TUNE = require('tune')
require('core.assets') -- sets the nearest-neighbor filter before fonts/images load

local State = require('core.state')
local Audio = require('core.audio')
local i18n = require('core.i18n')
local Save = require('core.save')
local Theme = require('ui.theme')
local Fx = require('ui.fx')
local Particles = require('ui.particles')
local Screen = require('ui.screen')
local flux = require('lib.flux')

_G.SCALE = 2

_G.font = Theme.fonts.hud
_G.smallFont = love.graphics.newFont('assets/fonts/PressStart2P-Regular.ttf', 8) -- labels in scaled world space
love.graphics.setFont(font)

_G.world = nil
_G.showHitboxes = false

function love.load()
    love.mouse.setVisible(true)
    love.math.setRandomSeed(os.time())

    Audio.load()
    Fx.load()
    Particles.load()
    _G.SETTINGS = Save.loadSettings()
    Audio.setVolumes(SETTINGS.master, SETTINGS.sfx, SETTINGS.music)
    Audio.startMusic() -- menu music runs for the whole session, only fades
    i18n.setLanguage(SETTINGS.language)
    Screen.apply(SETTINGS) -- sets logical globals, window mode, letterbox

    State.switch('splash') -- studio card first; it fades into the menu

    for _, a in ipairs(arg) do
        if a == 'autotest' then
            -- headless smoke test: jump into a run, hitboxes on, screenshot
            -- to the save dir after ~1.5s, then quit
            State.switch('playing')
            _G.showHitboxes = true
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_controls' then
            -- same screenshot/quit rhythm but on the controls splash
            State.switch('controls')
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_menu' then
            State.switch('menu')
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_options' then
            State.switch('menu')
            State.push('options')
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_splash' then
            -- splash is the boot state; just screenshot it mid-fade-in
            _G._autotest = { frames = 0 }
        elseif a == 'shotgun' then
            _G._autotest_shotgun = true
            function love.errorhandler(msg)
                io.stderr:write('CRASH: ' .. tostring(msg) .. '\n')
                os.exit(1)
            end
        elseif a == 'fpsprobe' then
            SETTINGS.fullscreen = true
            Screen.apply(SETTINGS)
            State.switch('playing')
            local pw, ph = love.graphics.getPixelDimensions()
            local m = { love.window.getMode() }
            io.stderr:write(('PROBE points=%dx%d pixels=%dx%d dpi=%.2f refresh=%s display=%s\n')
                :format(love.graphics.getWidth(), love.graphics.getHeight(), pw, ph,
                love.graphics.getDPIScale(), tostring(m[3] and m[3].refreshrate), tostring(m[3] and m[3].display)))
            _G._fps = { t = 0, n = 0 }
        end
    end
end

function love.update(dt)
    -- a window drag / load hitch delivers one huge dt; clamp it so bullets,
    -- movement and timers never integrate a step bigger than a 30fps frame
    dt = math.min(dt, 1/30)
    flux.update(dt)
    Fx.update(dt)
    Audio.update(dt) -- music fade + pause duck run in every state
    State.update(dt)
    if _autotest then
        _autotest.frames = _autotest.frames + 1
        if _autotest_shotgun and _autotest.frames == 30 then
            local Gun = require('hand_items.gun')
            world.player:giveGun(Gun.newById('shotgun'))
        elseif _autotest_shotgun and _autotest.frames >= 60 then
            local held = world.player.items[world.player.itemIndex]
            if held and held.curClip == 7 then
                held:fire(true)
                if held.curClip < 7 then
                    io.stderr:write(('SHOTGUN_TEST fired frame=%d\n'):format(_autotest.frames))
                end
            end
        end
        if _autotest.frames == 90 then
            love.graphics.captureScreenshot('autotest.png')
        elseif _autotest.frames > 93 then
            love.event.quit()
        end
    end
    if _fps then
        _fps.t = _fps.t + dt; _fps.n = _fps.n + 1
        if _fps.t >= 1 then
            io.stderr:write(('FPS %d frametime %.2fms\n'):format(love.timer.getFPS(), 1000/love.timer.getFPS()))
            _fps.t = 0; _fps.n = 0
        end
    end
end

function love.draw()
    Screen.attach()
    local mode = State.current().fxMode or 'game'
    -- optional CRT filter during gameplay (barrel-warps aim slightly — opt-in)
    if SETTINGS.crtInGame and mode == 'game' then mode = 'overlay' end
    Fx.setMode(mode)
    Fx.draw(State.draw)
    Fx.drawOverlays()
    Screen.present()
end

function love.resize()
    Screen.recompute()
end

function love.keypressed(key)
    State.keypressed(key)
end

function love.wheelmoved(dx, dy)
    State.wheelmoved(dx, dy)
end

function love.textinput(t)
    State.textinput(t)
end

-- Mouse events arrive in window pixels; map into logical canvas space so
-- clicks + aim line up regardless of resolution / fullscreen / letterbox.
function love.mousepressed(x, y, btn)
    local gx, gy = Screen.toGame(x, y)
    State.mousepressed(gx, gy, btn)
end

function love.mousemoved(x, y)
    local gx, gy = Screen.toGame(x, y)
    State.mousemoved(gx, gy)
end

function love.mousereleased(x, y, btn)
    local gx, gy = Screen.toGame(x, y)
    State.mousereleased(gx, gy, btn)
end

-- Closing the window mid-run saves it (Minecraft-style): the run resumes
-- from the exact same spot via Continue. Menus and the death screen don't
-- save (gameover already deleted the run file), and the scripted test modes
-- must not overwrite a real save.
function love.quit()
    if _autotest or _fps then return end
    if world and not world.gameOver and world.player and world.player.health > 0 then
        for _, s in ipairs(State.stack) do
            if s == require('states.playing') then
                Save.saveRun(world:serialize())
                break
            end
        end
    end
end
