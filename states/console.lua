-- Dev console overlay, opened with ` from gameplay (gated by TUNE.dev.enabled
-- in playing.lua). Commands mutate the live run through the world global —
-- always read it at run time, never cache it (U-reload replaces it).
-- Tab completes the highlighted suggestion, up/down move the highlight.

local State = require('core.state')
local Theme = require('ui.theme')
local Gun = require('hand_items.gun')
local DroppedGun = require('entities.dropped_gun')

local console = {}
console.overlay = true
console.fxMode = 'overlay'

local MAX_LOG = 8

local function killAllZombies()
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' then e.toRemove = true end
    end
end

-- run(arg) -> log text, isError
local commands = {
    money = { run = function(arg)
        local n = tonumber(arg or '') or 1000
        world.player.money = world.player.money + n
        return ('+$%d'):format(n)
    end },
    give = { argKind = 'gun', run = function(arg)
        local gun = arg and Gun.newById(arg)
        if not gun then return 'usage: give <usp|ak47|m4a1|sawedoff>', true end
        world.player:giveGun(gun)
        return 'gave ' .. gun.name
    end },
    drop = { argKind = 'gun', run = function(arg)
        local gun = arg and Gun.newById(arg)
        if not gun then return 'usage: drop <usp|ak47|m4a1|sawedoff>', true end
        local p = world.player
        local cx, cy = p:getCenter()
        local off = TUNE.droppedGun.dropOffset * (p.facingLeft and -1 or 1)
        local size = TUNE.tiles.size
        local x = math.max(0, math.min(cx + off - size/2, world.mapW - size))
        local y = math.max(0, math.min(cy - size/2, world.mapH - size))
        world:addEntity(DroppedGun:new(x, y, gun))
        return 'dropped ' .. gun.name
    end },
    god = { run = function()
        world.player.godMode = not world.player.godMode
        return 'god mode ' .. (world.player.godMode and 'ON' or 'OFF')
    end },
    heal = { run = function()
        world.player.health = world.player.maxHealth
        return 'healed to ' .. world.player.maxHealth
    end },
    ammo = { run = function()
        for i = 1, 2 do
            local gun = world.player.items[i]
            if gun then
                gun:cancelReload()
                gun.curClip = gun.maxClip
                gun.bulletsLeft = TUNE.guns[gun.id].reserve or gun.maxClip * 3
            end
        end
        return 'ammo refilled'
    end },
    wave = { argKind = 'wave', run = function(arg)
        local n
        if arg == 'skip' then n = world.waves.wave + 1
        else n = tonumber(arg or '') end
        if not n or n < 1 or n % 1 ~= 0 then
            return 'usage: wave skip | wave <n>', true
        end
        killAllZombies()
        world.waves:startWave(n)
        return 'wave ' .. n
    end },
}

local commandNames = { 'money', 'give', 'drop', 'god', 'heal', 'ammo', 'wave' }

local function computeSuggestions(buffer)
    local out = {}
    local cmd, rest = buffer:match('^(%S+)%s+(.*)$')
    if not cmd then
        for _, name in ipairs(commandNames) do
            if name:sub(1, #buffer) == buffer then table.insert(out, name) end
        end
    else
        local c = commands[cmd]
        local opts = c and (c.argKind == 'gun' and Gun.ids
            or c.argKind == 'wave' and { 'skip' }) or nil
        for _, o in ipairs(opts or {}) do
            if o:sub(1, #rest) == rest then table.insert(out, o) end
        end
    end
    return out
end

function console:enter()
    self.buffer = ''
    self.log = self.log or {} -- log survives close/reopen within the session
    self.blink = 0
    self:refreshSuggestions()
    love.keyboard.setKeyRepeat(true)
end

function console:exit()
    love.keyboard.setKeyRepeat(false) -- menus must not inherit key repeat
end

function console:update(dt)
    self.blink = self.blink + dt
end

function console:refreshSuggestions()
    self.suggestions = computeSuggestions(self.buffer)
    self.selIndex = 1
end

function console:textinput(t)
    if t == '`' or t == '~' then return end -- the opening keystroke leaks here
    self.buffer = self.buffer .. t:lower()
    self:refreshSuggestions()
end

local function pushLog(self, text, isErr)
    table.insert(self.log, { text = text, err = isErr })
    if #self.log > MAX_LOG then table.remove(self.log, 1) end
end

function console:keypressed(key)
    if key == '`' or key == 'escape' then
        State.pop()
    elseif key == 'backspace' then
        self.buffer = self.buffer:sub(1, -2)
        self:refreshSuggestions()
    elseif key == 'return' or key == 'kpenter' then
        local line = self.buffer:match('^%s*(.-)%s*$')
        if line ~= '' then
            local cmd, arg = line:match('^(%S+)%s*(%S*)')
            pushLog(self, '> ' .. line)
            local c = commands[cmd]
            if c then
                pushLog(self, c.run(arg ~= '' and arg or nil))
            else
                pushLog(self, 'unknown command: ' .. cmd, true)
            end
        end
        self.buffer = ''
        self:refreshSuggestions()
    elseif key == 'tab' then
        local sel = self.suggestions[self.selIndex]
        if sel then
            local cmd = self.buffer:match('^(%S+)%s')
            self.buffer = cmd and (cmd .. ' ' .. sel) or (sel .. ' ')
            self:refreshSuggestions()
        end
    elseif key == 'up' then
        self:moveSel(-1)
    elseif key == 'down' then
        self:moveSel(1)
    end
end

function console:moveSel(d)
    local n = #self.suggestions
    if n == 0 then return end
    self.selIndex = (self.selIndex - 1 + d) % n + 1
end

function console:draw()
    Theme.drawDim(0.5)

    local w, h = SCREENWIDTH, 320
    love.graphics.setColor(0.05, 0.05, 0.08, 0.88)
    love.graphics.rectangle('fill', 0, 0, w, h)
    love.graphics.setColor(0.75, 0.5, 0.9)
    love.graphics.line(0, h, w, h)

    love.graphics.setFont(Theme.fonts.hud)
    local lineH = 26

    -- prompt line at the panel bottom, log stacked above it (newest lowest)
    local y = h - lineH - 14
    local caret = (self.blink % 1 < 0.5) and '_' or ''
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('> ' .. self.buffer .. caret, 16, y)

    for i = #self.log, 1, -1 do
        y = y - lineH
        if y < 8 then break end
        local entry = self.log[i]
        if entry.err then love.graphics.setColor(1, 0.4, 0.4)
        else love.graphics.setColor(0.65, 0.85, 0.65) end
        love.graphics.print(entry.text, 16, y)
    end

    -- suggestion list under the panel, selected row highlighted
    local sy = h + 12
    for i, s in ipairs(self.suggestions) do
        if i == self.selIndex then
            love.graphics.setColor(1, 0.9, 0.3)
            love.graphics.print('> ' .. s, 24, sy)
        else
            love.graphics.setColor(0.55, 0.55, 0.55)
            love.graphics.print('  ' .. s, 24, sy)
        end
        sy = sy + lineH
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
end

return console
