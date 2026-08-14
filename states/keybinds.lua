-- Controls remap screen (Options -> CONTROLS). Minecraft-style: click a row,
-- it listens for the next key or mouse button, Esc cancels the capture.
-- Clashing binds show amber on every action that shares the key; a clash is
-- allowed to persist so a half-finished remap isn't rejected.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Save = require('core.save')
local Particles = require('ui.particles')
local Keybinds = require('core.keybinds')

local keybinds = {}
keybinds.overlay = true
keybinds.fxMode = 'overlay'

local PER_COLUMN = 9

function keybinds:enter()
    self.capturing = nil -- action name currently listening for a key
    local items = {}

    for i, action in ipairs(Keybinds.actions) do
        local col = i <= PER_COLUMN and 1 or 2
        local row = i <= PER_COLUMN and i or (i - PER_COLUMN)
        table.insert(items, {
            label = 'keys.' .. action, type = 'keybind',
            col = col, row = row,
            value = function() return Keybinds.label(action) end,
            capturing = function() return self.capturing == action end,
            conflict = function() return self.conflicts[action] == true end,
            activate = function() self.capturing = action end,
        })
    end

    -- centred rows under both columns
    table.insert(items, {
        label = 'keys.reset', type = 'action', row = PER_COLUMN + 2,
        activate = function()
            Keybinds.reset()
            self.conflicts = Keybinds.conflicts()
            Save.saveSettings(SETTINGS)
        end,
    })
    table.insert(items, {
        label = 'options.back', type = 'action', row = PER_COLUMN + 3,
        activate = function() State.pop() end,
    })

    -- 9 rows of binds + a blank row + reset + back has to clear the hint line
    -- at the bottom, so the column starts a little above the options menu's y
    self.list = MenuList:new(items, 285)
    self.conflicts = Keybinds.conflicts()
end

-- Finish a capture: bind the key, drop out of listening, persist.
function keybinds:bind(key)
    if Keybinds.set(self.capturing, key) then
        self.conflicts = Keybinds.conflicts()
        Save.saveSettings(SETTINGS)
    end
    self.capturing = nil
end

function keybinds:update(dt)
    self.list:update(dt)
    Particles.update(dt)
end

function keybinds:draw()
    Theme.drawBackground()
    Particles.drawFog()
    Theme.drawTitle(T('keys.title'), 150)
    self.list:draw()

    -- hint line: what to press, and a warning while anything clashes
    local fh = Theme.fonts.hint
    love.graphics.setFont(fh)
    local hasClash = next(self.conflicts) ~= nil
    local msg = self.capturing and T('keys.press_any')
        or (hasClash and T('keys.clash') or T('keys.hint'))
    local c = (hasClash and not self.capturing) and Theme.colors.conflict
        or Theme.colors.textDim
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.print(msg, SCREENWIDTH / 2 - fh:getWidth(msg) / 2, SCREENHEIGHT - 45)
    love.graphics.setColor(1, 1, 1)
end

function keybinds:keypressed(key)
    if self.capturing then
        if key == 'escape' then self.capturing = nil else self:bind(key) end
        return
    end
    if key == 'escape' then
        State.pop()
    else
        self.list:keypressed(key)
    end
end

function keybinds:mousepressed(x, y, btn)
    if self.capturing then
        self:bind('mouse' .. btn)
        return
    end
    self.list:mousepressed(x, y, btn)
end

function keybinds:mousemoved(x, y)
    if self.capturing then return end -- a listening row keeps the selection
    self.list:mousemoved(x, y)
end

function keybinds:mousereleased(x, y, btn)
    self.list:mousereleased(x, y, btn)
end

return keybinds
