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
    i18n.setLanguage(SETTINGS.language)
    Screen.apply(SETTINGS) -- sets logical globals, window mode, letterbox

    State.switch('menu')

    for _, a in ipairs(arg) do
        if a == 'fpsprobe' then
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
    flux.update(dt)
    Fx.update(dt)
    State.update(dt)
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
