-- Graphics options overlay (opened from Options). Unlike the rest of the
-- settings, graphics changes are staged in `pending` and only take effect when
-- the player hits APPLY — window mode changes are disruptive, so we batch them.
-- Back discards anything not yet applied.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Screen = require('ui.screen')
local Particles = require('ui.particles')

local graphics = {}
graphics.overlay = true
graphics.fxMode = 'overlay'

local FIELDS = { 'resolution', 'fullscreen', 'crtInGame' }

-- true when the staged settings differ from what's currently live
local function dirty(self)
    for _, f in ipairs(FIELDS) do
        if self.pending[f] ~= SETTINGS[f] then return true end
    end
    return false
end

local function onOff(v) return v and T('options.on') or T('options.off') end

function graphics:enter()
    -- snapshot the live graphics settings; edits happen on the copy
    self.pending = {}
    for _, f in ipairs(FIELDS) do self.pending[f] = SETTINGS[f] end

    local p = self.pending

    self.list = MenuList:new({
        {
            label = 'gfx.resolution', type = 'cycle',
            value = function()
                return p.fullscreen and T('gfx.native') or p.resolution
            end,
            cycle = function(dir) p.resolution = Screen.next(Screen.resolutions, p.resolution, dir) end,
        },
        {
            label = 'gfx.fullscreen', type = 'cycle',
            value = function() return onOff(p.fullscreen) end,
            cycle = function() p.fullscreen = not p.fullscreen end,
        },
        {
            label = 'gfx.crt_ingame', type = 'cycle',
            value = function() return onOff(p.crtInGame) end,
            cycle = function() p.crtInGame = not p.crtInGame end,
        },
        {
            label = 'gfx.apply', type = 'action',
            enabled = function() return dirty(self) end,
            activate = function()
                local prev = {}
                for _, f in ipairs(FIELDS) do prev[f] = SETTINGS[f] end
                -- crtInGame is a draw-time flag: applying it alone must not
                -- churn the window (setMode re-centers + flickers)
                local modeChanged = p.resolution ~= SETTINGS.resolution
                    or p.fullscreen ~= SETTINGS.fullscreen
                for _, f in ipairs(FIELDS) do SETTINGS[f] = p[f] end
                if modeChanged and not Screen.apply(SETTINGS) then
                    -- the window refused the mode: roll everything back
                    for _, f in ipairs(FIELDS) do SETTINGS[f], p[f] = prev[f], prev[f] end
                    Screen.apply(SETTINGS)
                end
                Save.saveSettings(SETTINGS)
            end,
        },
        {
            label = 'options.back', type = 'action',
            activate = function() State.pop() end,
        },
    }, 360)
end

function graphics:update(dt)
    self.list:update(dt)
    Particles.update(dt)
end

function graphics:draw()
    -- full menu backdrop: the page underneath must not show through
    Theme.drawBackground()
    Particles.drawFog()
    Theme.drawTitle(T('gfx.title'), 220)
    self.list:draw()
    if dirty(self) then
        Theme.drawHint(T('gfx.unapplied'), SCREENHEIGHT - 80)
    end
    Particles.drawEmbers()
end

function graphics:keypressed(key)
    if key == 'escape' then
        State.pop()
    else
        self.list:keypressed(key)
    end
end

function graphics:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function graphics:mousemoved(x, y) self.list:mousemoved(x, y) end
function graphics:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return graphics
