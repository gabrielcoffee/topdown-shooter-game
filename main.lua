_G.TUNE = require('tune')

-- browser build? folds TUNE.web over TUNE, and gates the handful of things a
-- tab cannot do (quit, boot fullscreen, dev console, streaming audio)
local Web = require('core.web')
_G.WEB = Web.enabled
Web.applyTune(TUNE)

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
    require('core.keybinds').init(SETTINGS) -- before any state can read input
    Audio.setVolumes(SETTINGS.master, SETTINGS.sfx, SETTINGS.music)
    Audio.startMusic() -- menu music runs for the whole session, only fades
    i18n.setLanguage(SETTINGS.language)
    Screen.apply(SETTINGS) -- sets logical globals, window mode, letterbox

    State.switch('splash') -- studio card first; it fades into the menu

    for _, a in ipairs(arg or {}) do -- love.js loaders may not set arg at all
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
        elseif a == 'autotest_mp' then
            State.switch('menu')
            State.push('multiplayer')
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_lobby' then
            -- stand up a real host so the lobby has a live roster to draw
            State.switch('menu')
            require('net.session').startHost()
            State.push('lobby')
            _G._autotest = { frames = 0 }
        elseif a == 'lanhost' or a == 'lanjoin' then
            -- two-process LAN check; see tools/lantest.sh
            function love.errorhandler(msg)
                io.stderr:write('CRASH: ' .. tostring(msg) .. '\n')
                os.exit(1)
            end
            local Lantest = require('core.lantest')
            if a == 'lanhost' then
                Lantest.host(tonumber(arg[3]) or 20)
            else
                Lantest.join(arg[3] or '127.0.0.1', 20)
            end
        elseif a == 'selftest' then
            -- scripted gameplay checks driven through the input struct;
            -- writes results to stderr and exits with a status code
            function love.errorhandler(msg)
                io.stderr:write('CRASH: ' .. tostring(msg) .. '\n')
                os.exit(1)
            end
            require('core.selftest').run()
        elseif a == 'autotest_downed' then
            -- co-op down/revive is unreachable solo, so stand up a second
            -- player next to the first, put ours on the floor, and hold the
            -- teammate's E so the revive bar is mid-fill in the shot
            State.switch('playing')
            local p = world.player
            local mate = world:addPlayer(p.x + 26, p.y)
            world.multiplayer = true
            p:goDown(world)
            p.bleed = TUNE.revive.bleedOutTime * 0.55
            mate.input.interact = true
            _G._autotest = { frames = 0, holdRevive = mate }
        elseif a == 'autotest_keys' then
            State.switch('menu')
            State.push('options')
            State.push('keybinds')
            _G._autotest = { frames = 0 }
        elseif a == 'autotest_splash' then
            -- splash is the boot state; just screenshot it mid-fade-in
            _G._autotest = { frames = 0 }
        elseif a:match('^win%d+x%d+$') then
            -- force a window size for a screenshot test: `love . autotest
            -- win1280x700`. Short and odd-shaped windows are exactly what
            -- used to leave part of the canvas uncovered.
            SETTINGS.fullscreen = false
            SETTINGS.resolution = a:match('^win(%d+x%d+)$')
            Screen.apply(SETTINGS)
        elseif a:match('^shot%d+$') and _G._autotest then
            -- autotest addon: screenshot at this frame instead of 90
            _G._autotest.shotFrame = tonumber(a:match('%d+'))
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
            -- the sizes that have to agree, or something goes uncovered
            io.stderr:write('PROBE ' .. Screen.debugSizes() .. '\n')
            _G._fps = { t = 0, n = 0 }
        end
    end
end

function love.update(dt)
    -- a window drag / load hitch delivers one huge dt; clamp it so bullets,
    -- movement and timers never integrate a step bigger than a 30fps frame
    dt = math.min(dt, 1/30)
    flux.update(dt)
    Screen.update(dt) -- deferred rebuild after a window drag settles
    Fx.update(dt)
    Audio.update(dt) -- music fade + pause duck run in every state
    -- LAN session ticks globally: the lobby has to keep syncing while the
    -- pause menu or options sit on top of it (desktop only, see menu.lua)
    if not WEB then require('net.session').update(dt) end
    State.update(dt)
    if _autotest then
        _autotest.frames = _autotest.frames + 1
        -- Input.poll only fills the LOCAL player's struct, so a scripted
        -- teammate's held button has to be re-armed every frame
        if _autotest.holdRevive then _autotest.holdRevive.input.interact = true end
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
        local shotFrame = _autotest.shotFrame or 90
        if _autotest.frames == shotFrame then
            love.graphics.captureScreenshot('autotest.png')
        elseif _autotest.frames > shotFrame + 3 then
            love.event.quit()
        end
    end
    if _fps then
        _fps.t = _fps.t + dt; _fps.n = _fps.n + 1
        if _fps.t >= 1 then
            -- draw calls and canvas switches matter more than pixels in the
            -- browser: every GL call crosses the wasm/JS boundary
            local st = love.graphics.getStats()
            io.stderr:write(('FPS %d frametime %.2fms draws %d canvasswitches %d shaderswitches %d\n')
                :format(love.timer.getFPS(), 1000/love.timer.getFPS(),
                        st.drawcalls, st.canvasswitches, st.shaderswitches))
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

-- A drag delivers one of these per frame. Screen keeps the blit rect (and so
-- the mouse mapping) correct immediately and defers reallocating the canvas,
-- shader chain and light buffers until the drag settles.
function love.resize(w, h)
    Screen.resized(w, h)
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
    -- a LAN client's world belongs to the host; saving it would hand back a
    -- run it cannot continue on its own
    if require('net.replication').isClient() then return end
    if world and not world.gameOver and world.player and world.player.health > 0 then
        for _, s in ipairs(State.stack) do
            if s == require('states.playing') then
                Save.saveRun(world:serialize())
                break
            end
        end
    end
end
