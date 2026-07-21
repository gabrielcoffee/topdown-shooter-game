_G.TUNE = require('tune')
require('core.assets') -- sets the nearest-neighbor filter before fonts/images load

local State = require('core.state')
local Audio = require('core.audio')
local i18n = require('core.i18n')
local Save = require('core.save')
local Theme = require('ui.theme')
local Fx = require('ui.fx')
local Particles = require('ui.particles')
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

    State.switch('menu')
end

function love.update(dt)
    flux.update(dt)
    Fx.update(dt)
    State.update(dt)
end

function love.draw()
    Fx.setMode(State.current().fxMode or 'game')
    Fx.draw(State.draw)
    Fx.drawOverlays()
end

function love.keypressed(key)
    State.keypressed(key)
end

function love.mousepressed(x, y, btn)
    State.mousepressed(x, y, btn)
end

function love.mousemoved(x, y)
    State.mousemoved(x, y)
end

function love.mousereleased(x, y, btn)
    State.mousereleased(x, y, btn)
end
