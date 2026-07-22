-- Minecraft-style chat console: bottom-left, game keeps running while typing.
-- T / ` / Enter open it (gated by TUNE.dev.enabled in playing.lua), Esc or
-- Enter close it. Recent lines linger and fade like Minecraft chat; while
-- open the full recent log shows solid. Tab completes the highlighted
-- suggestion, up/down move the highlight — or walk sent history when
-- nothing is being suggested. Commands mutate the live run through the
-- world global; always read it at run time (U-reload replaces it).

local Theme = require('ui.theme')
local Gun = require('hand_items.gun')
local DroppedGun = require('entities.dropped_gun')
local Enemy = require('entities.enemy')

local Chat = {}
Chat.open = false
Chat.buffer = ''
Chat.log = {}         -- { text, err, age }
Chat.history = {}     -- sent lines, newest last
Chat.histIndex = nil  -- nil = typing a fresh line
Chat.suggestions = {}
Chat.selIndex = 1
Chat.blink = 0
Chat.swallowFrame = false -- the opening keystroke's textinput lands same frame

-- Post a line to the chat log (public: game events can use this too)
function Chat.post(text, isErr)
    table.insert(Chat.log, { text = text, err = isErr, age = 0 })
    if #Chat.log > TUNE.chat.maxLog then table.remove(Chat.log, 1) end
end

local function killAllZombies()
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' then e.toRemove = true end
    end
end

-- Spot dropOffset px in front of the player, clamped inside the map
local function spotNearPlayer(size)
    local p = world.player
    local cx, cy = p:getCenter()
    local off = TUNE.droppedGun.dropOffset * (p.facingLeft and -1 or 1)
    local x = math.max(0, math.min(cx + off - size/2, world.mapW - size))
    local y = math.max(0, math.min(cy - size/2, world.mapH - size))
    return x, y
end

local zombieFactories = {
    slow = function(x, y, w) return Enemy:newSlow(x, y, w) end,
    fast = function(x, y, w) return Enemy:newFast(x, y, w) end,
    runner = function(x, y, w) return Enemy:newRunner(x, y, w) end,
}

local commandNames = { 'money', 'give', 'drop', 'god', 'heal', 'ammo',
                       'wave', 'spawn', 'help', 'clear' }

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
        local x, y = spotNearPlayer(TUNE.tiles.size)
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
    spawn = { argKind = 'zombie', run = function(arg)
        local factory = arg and zombieFactories[arg]
        if not factory then return 'usage: spawn <slow|fast|runner>', true end
        local t = TUNE.zombies[arg]
        local x, y = spotNearPlayer(t.size)
        world:addEntity(factory(x, y, world.waves.wave))
        return 'spawned ' .. arg .. ' zombie'
    end },
    help = { run = function()
        return table.concat(commandNames, '  ')
    end },
    clear = { run = function()
        Chat.log = {}
        return 'chat cleared'
    end },
}

local argOptions = {
    gun = Gun.ids,
    zombie = { 'slow', 'fast', 'runner' },
    wave = { 'skip' },
}

-- Prefix filter; empty buffer suggests nothing (Minecraft-style, `help` lists)
local function computeSuggestions(buffer)
    local out = {}
    if buffer == '' then return out end
    local cmd, rest = buffer:match('^(%S+)%s+(.*)$')
    if not cmd then
        for _, name in ipairs(commandNames) do
            if name:sub(1, #buffer) == buffer then table.insert(out, name) end
        end
    else
        local c = commands[cmd]
        for _, o in ipairs(c and argOptions[c.argKind] or {}) do
            if o:sub(1, #rest) == rest then table.insert(out, o) end
        end
    end
    return out
end

local function refreshSuggestions()
    Chat.suggestions = computeSuggestions(Chat.buffer)
    Chat.selIndex = 1
end

function Chat.openChat()
    Chat.open = true
    Chat.buffer = ''
    Chat.histIndex = nil
    Chat.blink = 0
    Chat.swallowFrame = true
    refreshSuggestions()
    love.keyboard.setKeyRepeat(true)
end

function Chat.close()
    if not Chat.open then return end
    Chat.open = false
    Chat.buffer = ''
    love.keyboard.setKeyRepeat(false) -- menus must not inherit key repeat
end

function Chat.update(dt)
    Chat.swallowFrame = false
    Chat.blink = Chat.blink + dt
    for _, e in ipairs(Chat.log) do
        e.age = e.age + dt
    end
end

function Chat.textinput(t)
    if not Chat.open or Chat.swallowFrame then return end
    Chat.buffer = Chat.buffer .. t:lower()
    Chat.histIndex = nil
    refreshSuggestions()
end

local function runLine(line)
    table.insert(Chat.history, line)
    if #Chat.history > TUNE.chat.maxLog then table.remove(Chat.history, 1) end

    local cmd, arg = line:match('^(%S+)%s*(%S*)')
    Chat.post('> ' .. line)
    local c = commands[cmd]
    if c then
        Chat.post(c.run(arg ~= '' and arg or nil))
    else
        Chat.post('unknown command: ' .. cmd .. ' (try help)', true)
    end
end

local function moveHistory(d)
    local n = #Chat.history
    if n == 0 then return end
    if not Chat.histIndex then
        if d > 0 then return end -- down on a fresh line does nothing
        Chat.histIndex = n
    else
        Chat.histIndex = Chat.histIndex + d
    end
    if Chat.histIndex > n then
        Chat.histIndex = nil
        Chat.buffer = ''
    else
        Chat.histIndex = math.max(1, Chat.histIndex)
        Chat.buffer = Chat.history[Chat.histIndex]
    end
    refreshSuggestions()
end

function Chat.keypressed(key)
    if key == 'escape' then
        Chat.close()
    elseif key == 'backspace' then
        Chat.buffer = Chat.buffer:sub(1, -2)
        Chat.histIndex = nil
        refreshSuggestions()
    elseif key == 'return' or key == 'kpenter' then
        local line = Chat.buffer:match('^%s*(.-)%s*$')
        if line ~= '' then runLine(line) end
        Chat.close()
    elseif key == 'tab' then
        local sel = Chat.suggestions[Chat.selIndex]
        if sel then
            local cmd = Chat.buffer:match('^(%S+)%s')
            Chat.buffer = cmd and (cmd .. ' ' .. sel) or (sel .. ' ')
            refreshSuggestions()
        end
    elseif key == 'up' or key == 'down' then
        local d = (key == 'up') and -1 or 1
        if #Chat.suggestions > 0 then
            local n = #Chat.suggestions
            Chat.selIndex = (Chat.selIndex - 1 + d) % n + 1
        else
            moveHistory(d)
        end
    end
end

function Chat.draw()
    local f = Theme.fonts.hint
    love.graphics.setFont(f)
    local lineH = f:getHeight() + 8
    local x = 12
    local inputY = SCREENHEIGHT - 148

    -- log stacks up from the input line, newest at the bottom
    local y = inputY - lineH
    local shown = 0
    for i = #Chat.log, 1, -1 do
        local e = Chat.log[i]
        local alpha = 1
        if not Chat.open then
            alpha = math.min(1, (TUNE.chat.showTime - e.age) / TUNE.chat.fadeTime)
            if alpha <= 0 then break end -- everything older has faded too
        end
        love.graphics.setColor(0, 0, 0, 0.45 * alpha)
        love.graphics.rectangle('fill', x - 4, y - 3, f:getWidth(e.text) + 8, lineH)
        if e.err then love.graphics.setColor(1, 0.45, 0.45, alpha)
        else love.graphics.setColor(1, 1, 1, alpha) end
        love.graphics.print(e.text, x, y)

        y = y - lineH
        shown = shown + 1
        if shown >= TUNE.chat.maxVisible or y < 40 then break end
    end

    if Chat.open then
        -- input line
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x - 4, inputY - 3,
            math.floor(SCREENWIDTH * 0.4), lineH)
        local caret = (Chat.blink % 1 < 0.5) and '_' or ''
        love.graphics.setColor(1, 1, 1)
        love.graphics.print('> ' .. Chat.buffer .. caret, x, inputY)

        -- suggestion popup right above the input line (over the log, like MC)
        local n = #Chat.suggestions
        if n > 0 then
            local w = 0
            for _, s in ipairs(Chat.suggestions) do
                w = math.max(w, f:getWidth(s))
            end
            local top = inputY - 3 - n * lineH
            love.graphics.setColor(0, 0, 0, 0.85)
            love.graphics.rectangle('fill', x - 4, top, w + 16, n * lineH)
            for i, s in ipairs(Chat.suggestions) do
                if i == Chat.selIndex then
                    love.graphics.setColor(1, 0.9, 0.3)
                else
                    love.graphics.setColor(0.6, 0.6, 0.6)
                end
                love.graphics.print(s, x + 4, top + (i - 1) * lineH + 3)
            end
        end
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
end

return Chat
