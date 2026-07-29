-- Options overlay, reachable from both the main menu and the pause menu.
-- Every change applies immediately and is persisted — no apply button.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Audio = require('core.audio')
local i18n = require('core.i18n')
local Particles = require('ui.particles')
local Crosshair = require('ui.crosshair')

local options = {}
options.overlay = true
options.fxMode = 'overlay'

-- volumes apply live on every tick; the disk write happens on key/mouse
-- release instead (a slider drag used to write settings.lua ~60x per second)
local function apply()
    Audio.setVolumes(SETTINGS.master, SETTINGS.sfx, SETTINGS.music)
end

local function volumeItem(labelKey, field)
    return {
        label = labelKey, type = 'slider',
        get = function() return SETTINGS[field] end,
        set = function(v)
            SETTINGS[field] = v
            apply()
        end,
    }
end

-- Brightness slider <-> ambient value: 0..1 maps onto [min, max] snapped to
-- brightnessStep (0.10 DARK, 0.12, ... 0.40 BRIGHT, Minecraft-style)
local function brightnessItem()
    local L = TUNE.lighting
    local span = L.brightnessMax - L.brightnessMin
    local steps = math.floor(span / L.brightnessStep + 0.5)
    return {
        label = 'options.brightness', type = 'slider',
        get = function()
            return (SETTINGS.brightness - L.brightnessMin) / span
        end,
        set = function(v)
            local i = math.floor(v * steps + 0.5)
            SETTINGS.brightness = L.brightnessMin + i * L.brightnessStep
            if world and world.lighting then -- live, also mid-run via pause
                world.lighting:setAmbient(SETTINGS.brightness)
            end
        end,
        format = function()
            local b = SETTINGS.brightness
            if b <= L.brightnessMin then return T('options.dark') end
            if b >= L.brightnessMax then return T('options.bright') end
            return math.floor((b - L.brightnessMin) / span * 100 + 0.5) .. '%'
        end,
    }
end

function options:enter()
    self.list = MenuList:new({
        volumeItem('options.master', 'master'),
        volumeItem('options.sfx', 'sfx'),
        volumeItem('options.music', 'music'),
        brightnessItem(),
        {
            label = 'options.language', type = 'cycle',
            value = function() return i18n.names[i18n.lang] end,
            cycle = function(dir)
                local code = i18n.nextLanguage(dir)
                i18n.setLanguage(code)
                SETTINGS.language = code
                Save.saveSettings(SETTINGS)
            end,
        },
        {
            label = 'options.cross_color', type = 'cycle',
            value = function() return Crosshair.colorById(SETTINGS.crossColor).name end,
            cycle = function(dir)
                SETTINGS.crossColor = Crosshair.nextColorId(SETTINGS.crossColor, dir)
                apply()
            end,
        },
        {
            label = 'options.cross_outline', type = 'cycle',
            value = function() return SETTINGS.crossOutline and T('options.on') or T('options.off') end,
            cycle = function()
                SETTINGS.crossOutline = not SETTINGS.crossOutline
                apply()
            end,
        },
        {
            label = 'options.graphics', type = 'action',
            activate = function() State.push('graphics') end,
        },
        {
            label = 'options.back', type = 'action',
            activate = function() State.pop() end,
        },
    }, 400)
end

function options:update(dt)
    self.list:update(dt)
    Particles.update(dt) -- keeps the menu background alive underneath
end

function options:draw()
    -- full menu backdrop: the page underneath must not show through
    Theme.drawBackground()
    Particles.drawFog()
    Theme.drawTitle(T('options.title'), 240)
    self.list:draw()
    Particles.drawEmbers()
end

function options:keypressed(key)
    if key == 'escape' then
        State.pop()
    else
        self.list:keypressed(key)
        if key == 'left' or key == 'right' or key == 'a' or key == 'd'
            or key == 'return' or key == 'kpenter' or key == 'space' then
            Save.saveSettings(SETTINGS) -- discrete edits persist as they happen
        end
    end
end

function options:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function options:mousemoved(x, y) self.list:mousemoved(x, y) end
function options:mousereleased(x, y, btn)
    self.list:mousereleased(x, y, btn)
    Save.saveSettings(SETTINGS) -- end of a drag/click: persist once
end

return options
