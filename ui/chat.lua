-- Minecraft-style chat console: bottom-left, game keeps running while typing.
-- T opens it (gated by TUNE.dev.enabled in playing.lua), Esc or Enter close
-- it. Commands need a leading slash; a bare line just echoes into the log
-- like a chat message. Recent lines linger and fade like Minecraft chat;
-- while open the full recent log shows solid.
--
-- The input line is a real text field: caret, arrow keys, word jumps, shift
-- selection, Cmd/Ctrl + C/V/X/A. The mouse can select inside the input line
-- or inside any visible log line (double-click grabs the whole line), so old
-- output can be copied back out.
--
-- Tab cycles the suggestion list, up/down walk sent history. Commands mutate
-- the live run through the world global; always read it at run time
-- (U-reload replaces it).

local Theme = require('ui.theme')
local Gun = require('hand_items.gun')
local DroppedGun = require('entities.dropped_gun')
local Enemy = require('entities.enemy')

local MAXLEN = 64          -- longest real command is ~20 chars
local DOUBLECLICK = 0.35   -- secs between clicks that count as a double click

local Chat = {}
Chat.open = false
Chat.buffer = ''
Chat.caret = 0        -- number of chars to the left of the caret
Chat.anchor = nil     -- selection anchor in the input line (nil = no selection)
Chat.scrollX = 0      -- px the input text is shifted left to keep the caret visible
Chat.log = {}         -- { text, err, age }
Chat.history = {}     -- sent lines, newest last
Chat.histIndex = nil  -- nil = typing a fresh line
Chat.suggestions = {}
Chat.selIndex = 1
Chat.tabList = nil    -- frozen suggestion list while cycling with Tab
Chat.blink = 0
Chat.swallowFrame = false -- the opening keystroke's textinput lands same frame
Chat.logSel = nil     -- { e = log entry, text, a, b } mouse selection over the log
Chat.lineRects = {}   -- per-log-line hit rects, rebuilt every draw
Chat.inputRect = nil
Chat.drag = nil       -- what the held mouse button is selecting in
Chat.lastClick = { t = -1, target = nil }

-- Post a line to the chat log (public: game events can use this too).
-- kind: true/'err' = red, 'warn' = yellow, nil = white
function Chat.post(text, kind)
    table.insert(Chat.log, { text = text, err = kind == true or kind == 'err',
                             warn = kind == 'warn', age = 0 })
    if #Chat.log > TUNE.chat.maxLog then table.remove(Chat.log, 1) end
end

local function killAllZombies()
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' then
            if e.growlSrc then e.growlSrc:stop() end -- no orphaned growls
            e.toRemove = true
        end
    end
end

local zombieFactories = {
    slow_zombie = function(x, y, w) return Enemy:newSlow(x, y, w) end,
    normal_zombie = function(x, y, w) return Enemy:newNormal(x, y, w) end,
    fast_zombie = function(x, y, w) return Enemy:newFast(x, y, w) end,
}

local commandNames = { 'money', 'give', 'god', 'heal', 'ammo',
                       'wave', 'spawn', 'powerup', 'help', 'clear' }

-- run(arg) -> log text, isError
local commands = {
    money = { cheat = true, run = function(arg)
        local n = tonumber(arg or '') or 1000
        local p = world.player
        local before = p.money
        p:addMoney(n)
        return ('%+d -> $%d'):format(p.money - before, p.money)
    end },
    give = { cheat = true, argKind = 'giveable', run = function(arg)
        local p = world.player
        if arg == 'grenade' then
            p:addThrowable('he')
            return 'grenades: ' .. p.grenades .. ' (pool ' .. (p.grenades + p.molotovs)
                .. '/' .. TUNE.throwables.maxCarry .. ')'
        elseif arg == 'molotov' then
            p:addThrowable('molotov')
            return 'molotovs: ' .. p.molotovs .. ' (pool ' .. (p.grenades + p.molotovs)
                .. '/' .. TUNE.throwables.maxCarry .. ')'
        elseif arg == 'medkit' then
            p:addMedkit()
            return 'medkits: ' .. p.medkits
        end
        local gun = arg and Gun.newById(arg)
        if not gun then
            return 'usage: /give <usp|ak47|m4a1|shotgun|grenade|molotov|medkit>', true
        end
        if p.items[1] and p.items[2] then -- both gun slots taken: lands in front
            DroppedGun.dropNear(world, gun, p)
            return 'slots full, dropped ' .. gun.name
        end
        p:giveGun(gun)
        return 'gave ' .. gun.name
    end },
    god = { cheat = true, argKind = 'god', run = function(arg)
        if arg == 'off' then
            world.player.godMode = false
            return 'god mode OFF'
        elseif arg == nil or arg == 'on' then
            world.player.godMode = true
            return 'god mode ON (hold shift to fly, /god off to disable)'
        end
        return 'usage: /god [on|off]', true
    end },
    heal = { cheat = true, run = function()
        world.player.health = world.player.maxHealth
        return 'healed to ' .. world.player.maxHealth
    end },
    ammo = { cheat = true, run = function()
        for i = 1, 2 do
            local gun = world.player.items[i]
            if gun then gun:refill() end
        end
        return 'ammo refilled'
    end },
    wave = { cheat = true, argKind = 'wave', run = function(arg)
        local n
        if arg == 'skip' then n = world.waves.wave + 1
        else n = tonumber(arg or '') end
        if not n or n < 0 or n % 1 ~= 0 then
            return 'usage: /wave skip | /wave <n>  (0 = empty sandbox)', true
        end
        killAllZombies()
        world.waves:startWave(n)
        return 'wave ' .. n .. (n == 0 and ' (sandbox, no zombies)' or '')
    end },
    spawn = { cheat = true, argKind = 'zombie', run = function(arg, arg2)
        local factory = arg and zombieFactories[arg]
        local count = arg2 and tonumber(arg2) or 1
        if not factory or count % 1 ~= 0 or count < 1 then
            return 'usage: /spawn <slow_zombie|normal_zombie|fast_zombie> [count]', true
        end
        count = math.min(count, TUNE.chat.maxSpawn)
        local t = TUNE.zombies[arg:gsub('_zombie$', '')]
        local p = world.player
        local cx, cy = p:getCenter()
        local off = TUNE.droppedGun.dropOffset * (p.facingLeft and -1 or 1)
        for i = 1, count do
            -- past the first, scatter them so a batch doesn't stack on one spot
            local jx = (i > 1) and love.math.random(-48, 48) or 0
            local jy = (i > 1) and love.math.random(-48, 48) or 0
            local x = math.max(0, math.min(cx + off + jx - t.size/2, world.mapW - t.size))
            local y = math.max(0, math.min(cy + jy - t.size/2, world.mapH - t.size))
            world:addEntity(factory(x, y, world.waves.wave))
        end
        return 'spawned ' .. count .. 'x ' .. arg
    end },
    powerup = { cheat = true, argKind = 'powerup', run = function(arg)
        if not (arg and TUNE.powerups.weights[arg]) then
            return 'usage: /powerup <nuke|maxammo|instakill|freeze|doublepoints|'
                .. 'firesale|carpenter>', true
        end
        local Powerup = require('entities.powerup')
        local p = world.player
        local cx, cy = p:getCenter()
        local off = TUNE.droppedGun.dropOffset * (p.facingLeft and -1 or 1)
        world:addEntity(Powerup:new(cx + off, cy, arg))
        return 'dropped ' .. arg
    end },
    help = { run = function()
        local out = {}
        for _, n in ipairs(commandNames) do table.insert(out, '/' .. n) end
        return table.concat(out, ' ')
    end },
    clear = { run = function()
        Chat.log = {}
        Chat.logSel = nil
        return 'chat cleared'
    end },
}

-- Hidden footage mode: absent from commandNames, so /help and the
-- suggestion popup never reveal it. Molotov kills in a fixed tick count,
-- longer burn, HUD + closed-chat overlay hidden (see tune.recording).
-- Flags the run as cheated directly — no yellow warning line on screen.
commands.recording = { run = function()
    world.recordingMode = not world.recordingMode
    world.cheated = true
    if world.recordingMode then
        Chat.log = {} -- clean frame for the clip
        Chat.logSel = nil
        return 'recording ON (molotov: fixed-tick kills, long burn, HUD off)'
    end
    return 'recording OFF'
end }
commands.recoding = commands.recording -- typo-friendly alias

local argOptions = {
    giveable = { 'usp', 'ak47', 'm4a1', 'shotgun', 'grenade', 'molotov', 'medkit' },
    zombie = { 'slow_zombie', 'normal_zombie', 'fast_zombie' },
    wave = { 'skip' },
    god = { 'on', 'off' },
    powerup = { 'nuke', 'maxammo', 'instakill', 'freeze', 'doublepoints',
                'firesale', 'carpenter' },
}

-- Prefix filter over the token being typed. Commands are slash-only, so
-- nothing is suggested until the line starts with '/'.
local function computeSuggestions(buffer)
    local out = {}
    if buffer:sub(1, 1) ~= '/' then return out end
    local body = buffer:sub(2)
    local cmd, rest = body:match('^(%S+)%s+(.*)$')
    if not cmd then
        for _, name in ipairs(commandNames) do
            if name:sub(1, #body) == body then
                table.insert(out, '/' .. name)
            end
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
    Chat.tabList = nil -- editing invalidates a Tab cycle
end

-- ---------------------------------------------------------------- text edit

local function selRange()
    if not Chat.anchor or Chat.anchor == Chat.caret then return nil end
    local a, b = Chat.anchor, Chat.caret
    if a > b then a, b = b, a end
    return a, b
end

local function selText()
    local a, b = selRange()
    if not a then return nil end
    return Chat.buffer:sub(a + 1, b)
end

local function deleteSelection()
    local a, b = selRange()
    if not a then return false end
    Chat.buffer = Chat.buffer:sub(1, a) .. Chat.buffer:sub(b + 1)
    Chat.caret = a
    Chat.anchor = nil
    return true
end

local function insertText(text)
    text = text:gsub('[\r\n\t]', ' ')
    deleteSelection()
    local room = MAXLEN - #Chat.buffer
    if room <= 0 then return end
    text = text:sub(1, room)
    Chat.buffer = Chat.buffer:sub(1, Chat.caret) .. text .. Chat.buffer:sub(Chat.caret + 1)
    Chat.caret = Chat.caret + #text
    Chat.histIndex = nil
end

local function moveCaret(pos, keepSel)
    if keepSel then
        Chat.anchor = Chat.anchor or Chat.caret
    else
        Chat.anchor = nil
    end
    Chat.caret = math.max(0, math.min(pos, #Chat.buffer))
end

local function wordLeft(i)
    while i > 0 and Chat.buffer:sub(i, i) == ' ' do i = i - 1 end
    while i > 0 and Chat.buffer:sub(i, i) ~= ' ' do i = i - 1 end
    return i
end

local function wordRight(i)
    local n = #Chat.buffer
    while i < n and Chat.buffer:sub(i + 1, i + 1) == ' ' do i = i + 1 end
    while i < n and Chat.buffer:sub(i + 1, i + 1) ~= ' ' do i = i + 1 end
    return i
end

-- Cmd on macOS, Ctrl on Windows/Linux — both mean "text shortcut" here
local function cmdDown()
    return love.keyboard.isDown('lgui', 'rgui', 'lctrl', 'rctrl')
end
local function shiftDown() return love.keyboard.isDown('lshift', 'rshift') end
local function altDown()   return love.keyboard.isDown('lalt', 'ralt') end

-- The log selection wins if there is one, then the input selection, then the
-- whole input line (so a bare Cmd+C copies what you typed)
local function copySelection()
    local t
    local s = Chat.logSel
    if s then
        local a, b = math.min(s.a, s.b), math.max(s.a, s.b)
        if a ~= b then t = s.text:sub(a + 1, b) end
    end
    t = t or selText() or Chat.buffer
    if t ~= '' then love.system.setClipboardText(t) end
end

-- ------------------------------------------------------------------- open

function Chat.openChat()
    Chat.open = true
    Chat.buffer = ''    -- opens empty; type '/' to command
    Chat.caret = 0
    Chat.anchor = nil
    Chat.scrollX = 0
    Chat.histIndex = nil
    Chat.logSel = nil
    Chat.drag = nil
    Chat.blink = 0
    Chat.swallowFrame = true
    refreshSuggestions()
    love.keyboard.setKeyRepeat(true)
    -- window-mode churn (fullscreen toggles) can leave SDL's text input off;
    -- re-arm it so textinput events are guaranteed while the console is up
    love.keyboard.setTextInput(true)
end

function Chat.close()
    if not Chat.open then return end
    Chat.open = false
    Chat.buffer = ''
    Chat.caret = 0
    Chat.anchor = nil
    Chat.logSel = nil
    Chat.drag = nil
    Chat.lineRects = {}
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
    -- No cmdDown() gate here: love.keyboard.isDown modifier state goes stale
    -- when Cmd+Tab steals the release (macOS keeps lgui "down"), which used
    -- to silently kill all typing. Shortcut echoes are swallowed per-frame
    -- by the clipboard branches in keypressed instead.
    if not Chat.open or Chat.swallowFrame then return end
    insertText(t:lower())
    refreshSuggestions()
end

-- ---------------------------------------------------------------- commands

local function runLine(line)
    table.insert(Chat.history, line)
    if #Chat.history > TUNE.chat.maxLog then table.remove(Chat.history, 1) end

    Chat.post('> ' .. line)
    local body = line:match('^/(.*)$')
    if not body then return end -- no slash: plain chat line, echoed above
    local cmd, a1, a2 = body:match('^(%S+)%s*(%S*)%s*(%S*)')
    if not cmd then return end
    local c = commands[cmd]
    if c then
        local out, isErr = c.run(a1 ~= '' and a1 or nil, a2 ~= '' and a2 or nil)
        Chat.post(out, isErr)
        -- first cheat that actually ran: flag the run, records won't save
        if c.cheat and not isErr and not world.cheated then
            world.cheated = true
            Chat.post('cheats used: kills & wave record not saved this run', 'warn')
        end
    else
        Chat.post('unknown command: ' .. cmd .. ' (try /help)', true)
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
    Chat.caret = #Chat.buffer
    Chat.anchor = nil
    refreshSuggestions()
end

-- Replace the token being typed with a suggestion
local function applyCompletion(sel)
    local cmd = Chat.buffer:match('^(/?%S+)%s') -- keep the command, slash or not
    Chat.buffer = cmd and (cmd .. ' ' .. sel) or (sel .. ' ')
    Chat.caret = #Chat.buffer
    Chat.anchor = nil
end

function Chat.keypressed(key)
    local cmd, shift, alt = cmdDown(), shiftDown(), altDown()

    -- clipboard / select-all; platforms that also echo the shortcut as a
    -- textinput event land it this same frame, so swallow the frame
    if cmd and key == 'c' then
        copySelection()
        Chat.swallowFrame = true
        return
    end
    if cmd and key == 'v' then
        insertText((love.system.getClipboardText() or ''):lower())
        refreshSuggestions()
        Chat.swallowFrame = true
        return
    end
    if cmd and key == 'x' then
        copySelection()
        if deleteSelection() then refreshSuggestions() end
        Chat.swallowFrame = true
        return
    end
    if cmd and key == 'a' then
        Chat.anchor, Chat.caret = 0, #Chat.buffer
        Chat.logSel = nil
        Chat.swallowFrame = true
        return
    end

    if key == 'escape' then
        Chat.close()

    elseif key == 'backspace' then
        if not deleteSelection() then
            local to = cmd and 0 or (alt and wordLeft(Chat.caret) or Chat.caret - 1)
            to = math.max(0, to)
            Chat.buffer = Chat.buffer:sub(1, to) .. Chat.buffer:sub(Chat.caret + 1)
            Chat.caret = to
        end
        Chat.histIndex = nil
        refreshSuggestions()

    elseif key == 'delete' then
        if not deleteSelection() then
            local to = cmd and #Chat.buffer or (alt and wordRight(Chat.caret) or Chat.caret + 1)
            Chat.buffer = Chat.buffer:sub(1, Chat.caret) .. Chat.buffer:sub(to + 1)
        end
        Chat.histIndex = nil
        refreshSuggestions()

    elseif key == 'return' or key == 'kpenter' then
        local line = Chat.buffer:match('^%s*(.-)%s*$')
        if line ~= '' and line ~= '/' then runLine(line) end
        Chat.close()

    elseif key == 'tab' then
        -- first Tab freezes the match list, further Tabs walk it
        if Chat.tabList and #Chat.tabList > 1 then
            Chat.selIndex = Chat.selIndex % #Chat.tabList + 1
        elseif #Chat.suggestions > 0 then
            Chat.tabList = Chat.suggestions
            Chat.selIndex = 1
        end
        local list = Chat.tabList
        if list and list[Chat.selIndex] then
            applyCompletion(list[Chat.selIndex])
            Chat.suggestions = list -- keep the popup showing every match
        end

    elseif key == 'left' or key == 'right' then
        local d = (key == 'left') and -1 or 1
        local pos
        local a, b = selRange()
        if cmd then
            pos = (d < 0) and 0 or #Chat.buffer
        elseif alt then
            pos = (d < 0) and wordLeft(Chat.caret) or wordRight(Chat.caret)
        elseif a and not shift then
            pos = (d < 0) and a or b -- collapse the selection to its edge
        else
            pos = Chat.caret + d
        end
        moveCaret(pos, shift)

    elseif key == 'home' then
        moveCaret(0, shift)
    elseif key == 'end' then
        moveCaret(#Chat.buffer, shift)

    elseif key == 'up' or key == 'down' then
        moveHistory((key == 'up') and -1 or 1)
    end
end

-- ------------------------------------------------------------------- mouse

-- Char index in `text` nearest to pixel x (originX = x of the first char)
local function indexAt(text, px, originX)
    local f = Theme.fonts.hint
    local best, bestD = 0, math.huge
    for i = 0, #text do
        local d = math.abs(originX + f:getWidth(text:sub(1, i)) - px)
        if d < bestD then best, bestD = i, d end
    end
    return best
end

local function inRect(r, x, y)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function Chat.mousepressed(x, y, btn)
    if not Chat.open or btn ~= 1 then return false end
    local now = love.timer.getTime()
    local dbl = (now - Chat.lastClick.t) < DOUBLECLICK

    local r = Chat.inputRect
    if inRect(r, x, y) then
        local i = indexAt(Chat.buffer, x, r.textX)
        if dbl and Chat.lastClick.target == 'input' then
            Chat.anchor, Chat.caret = 0, #Chat.buffer
        else
            Chat.caret, Chat.anchor = i, i
        end
        Chat.logSel, Chat.drag = nil, 'input'
        Chat.lastClick = { t = now, target = 'input' }
        return true
    end

    for _, lr in ipairs(Chat.lineRects) do
        if inRect(lr, x, y) then
            local i = indexAt(lr.text, x, lr.x)
            if dbl and Chat.lastClick.target == lr.e then
                Chat.logSel = { e = lr.e, text = lr.text, a = 0, b = #lr.text }
            else
                Chat.logSel = { e = lr.e, text = lr.text, a = i, b = i }
            end
            Chat.anchor, Chat.drag = nil, lr
            Chat.lastClick = { t = now, target = lr.e }
            return true
        end
    end

    Chat.logSel, Chat.drag = nil, nil
    Chat.lastClick = { t = now, target = nil }
    return true -- clicks belong to the console while it is open
end

function Chat.mousemoved(x, y)
    if not Chat.open or not Chat.drag then return end
    if Chat.drag == 'input' then
        local r = Chat.inputRect
        if r then Chat.caret = indexAt(Chat.buffer, x, r.textX) end
    elseif Chat.logSel then
        Chat.logSel.b = indexAt(Chat.drag.text, x, Chat.drag.x)
    end
end

function Chat.mousereleased()
    Chat.drag = nil
end

-- -------------------------------------------------------------------- draw

local function selBounds(f, text, a, b, originX)
    local lo, hi = math.min(a, b), math.max(a, b)
    if lo == hi then return nil end
    local x1 = originX + f:getWidth(text:sub(1, lo))
    local x2 = originX + f:getWidth(text:sub(1, hi))
    return x1, x2 - x1
end

function Chat.draw()
    -- footage mode: while the console is closed nothing chat-related draws
    -- (command echoes would linger over the clip otherwise)
    if not Chat.open and world and world.recordingMode then return end

    local f = Theme.fonts.hint
    love.graphics.setFont(f)
    local lineH = f:getHeight() + 8
    local x = 12
    local inputY = SCREENHEIGHT - 148

    Chat.lineRects = {}

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
        local w = f:getWidth(e.text)
        love.graphics.setColor(0, 0, 0, 0.45 * alpha)
        love.graphics.rectangle('fill', x - 4, y - 3, w + 8, lineH)

        if Chat.open then
            table.insert(Chat.lineRects,
                { e = e, text = e.text, x = x, y = y - 3, w = w + 8, h = lineH })
            local s = Chat.logSel
            if s and s.e == e then
                local sx, sw = selBounds(f, e.text, s.a, s.b, x)
                if sx then
                    love.graphics.setColor(0.3, 0.5, 1, 0.5)
                    love.graphics.rectangle('fill', sx, y - 3, sw, lineH)
                end
            end
        end

        if e.err then love.graphics.setColor(1, 0.45, 0.45, alpha)
        elseif e.warn then love.graphics.setColor(1, 0.85, 0.3, alpha)
        else love.graphics.setColor(1, 1, 1, alpha) end
        love.graphics.print(e.text, x, y)

        y = y - lineH
        shown = shown + 1
        if shown >= TUNE.chat.maxVisible or y < 40 then break end
    end

    if Chat.open then
        local boxW = math.floor(SCREENWIDTH * 0.4)
        local prefix = '> '
        local pw = f:getWidth(prefix)
        local innerW = boxW - 8 - pw

        -- horizontal scroll: keep the caret inside the box
        local caretW = f:getWidth(Chat.buffer:sub(1, Chat.caret))
        if caretW - Chat.scrollX > innerW then Chat.scrollX = caretW - innerW end
        if caretW - Chat.scrollX < 0 then Chat.scrollX = caretW end
        Chat.scrollX = math.max(0, math.min(Chat.scrollX,
            math.max(0, f:getWidth(Chat.buffer) - innerW)))
        local textX = x + pw - Chat.scrollX

        Chat.inputRect = { x = x - 4, y = inputY - 3, w = boxW, h = lineH, textX = textX }

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x - 4, inputY - 3, boxW, lineH)

        -- clip everything inside the box so a long line can't spill out
        love.graphics.setScissor(x - 4, inputY - 3, boxW, lineH)
        if Chat.anchor then
            local sx, sw = selBounds(f, Chat.buffer, Chat.anchor, Chat.caret, textX)
            if sx then
                love.graphics.setColor(0.3, 0.5, 1, 0.5)
                love.graphics.rectangle('fill', sx, inputY - 3, sw, lineH)
            end
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(prefix, x, inputY)
        love.graphics.print(Chat.buffer, textX, inputY)
        if Chat.blink % 1 < 0.5 then
            love.graphics.rectangle('fill', textX + caretW, inputY, 2, f:getHeight())
        end
        love.graphics.setScissor()

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
                if i == Chat.selIndex and Chat.tabList then
                    love.graphics.setColor(1, 0.9, 0.3)
                else
                    love.graphics.setColor(0.6, 0.6, 0.6)
                end
                love.graphics.print(s, x + 4, top + (i - 1) * lineH + 3)
            end
        end
    else
        Chat.inputRect = nil
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
end

return Chat
