-- Hold TAB in a LAN run: who is here, how they are doing, who is talking.
--
-- Drawn as an overlay from states/playing rather than as a pushed state,
-- because the world must keep running underneath it. Holding a key that
-- paused a co-op game would be a way to grief one.
--
-- Everything on it comes from the replicated player bodies, so it reads the
-- same on every machine without a message of its own.

local Color = require('core.color')
local Session = require('net.session')
local Voice = require('net.voice')

local Scoreboard = {}

local ROW_H = 30
local PAD = 16

-- one column per thing worth knowing, laid out from a single width table so
-- the header and the rows can never drift apart
-- state is the widest because it carries the longest string in any language
-- ("OUT THIS WAVE" / "FUERA ESTA OLEADA"), and it sits left of a
-- right-aligned number, so an overrun collides rather than just looking tight
local COLS = {
    { key = 'name',  w = 200, align = 'left' },
    { key = 'state', w = 250, align = 'left' },
    { key = 'score', w = 130, align = 'right' },
    { key = 'money', w = 120, align = 'right' },
}

local function totalWidth()
    local w = PAD * 2
    for _, c in ipairs(COLS) do w = w + c.w end
    return w
end

-- What this player is doing, in two words, most urgent first.
local function stateOf(p)
    if p.dead then return T('score.dead'), { 0.55, 0.55, 0.55 } end
    if p.downed then return T('score.downed'), { 1, 0.3, 0.3 } end
    if p.health <= TUNE.player.lowHealthThreshold then
        return T('score.hurt', math.floor(p.health)), { 1, 0.65, 0.2 }
    end
    return T('score.alive', math.floor(p.health)), { 0.7, 0.9, 0.7 }
end

function Scoreboard.visible()
    if _G._autotest and _G._autotest.holdScoreboard then return true end
    return require('core.keybinds').isDown('scoreboard')
        and Session.active()
        and not require('ui.chat').open
end

function Scoreboard.draw(world)
    if not world or not world.players then return end

    -- sort by score, highest first, so the board answers "who is winning"
    -- without anyone reading four numbers
    local rows = {}
    for _, p in ipairs(world.players) do rows[#rows + 1] = p end
    table.sort(rows, function(a, b)
        if (a.earnedTotal or 0) == (b.earnedTotal or 0) then
            return (a.netSlot or 0) < (b.netSlot or 0)
        end
        return (a.earnedTotal or 0) > (b.earnedTotal or 0)
    end)

    local w = totalWidth()
    local h = PAD * 2 + ROW_H * (#rows + 1)
    local x = math.floor((SCREENWIDTH - w) / 2)
    local y = math.floor(SCREENHEIGHT / 2 - h / 2) - 60

    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle('fill', x, y, w, h, 4, 4)
    love.graphics.setColor(0.8, 0.15, 0.15, 0.9)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)

    local function cell(col, cx, cy, text, color)
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
        local tw = font:getWidth(text)
        local tx = (col.align == 'right') and (cx + col.w - tw) or cx
        love.graphics.print(text, math.floor(tx), math.floor(cy))
    end

    -- header
    local hx, hy = x + PAD, y + PAD
    local head = { name = T('score.player'), state = T('score.state'),
                   score = T('score.score'), money = T('score.money') }
    for _, c in ipairs(COLS) do
        cell(c, hx, hy, head[c.key], { 0.6, 0.6, 0.6 })
        hx = hx + c.w
    end

    for i, p in ipairs(rows) do
        local ry = y + PAD + ROW_H * i
        local rx = x + PAD
        local slot = p.netSlot or i
        local name = p.netName or T('score.unknown')
        -- our own row in the game's red, everyone else's in white
        local nameColor = (p == world.player) and { 1, 0.35, 0.35 } or { 1, 1, 1 }
        local stateText, stateColor = stateOf(p)

        -- talking indicator sits in front of the name, where a chat client
        -- would put it
        if Voice.isSpeaking(slot) then
            love.graphics.setColor(0.4, 1, 0.4)
            love.graphics.print('>', rx - 12, math.floor(ry))
        end

        for _, c in ipairs(COLS) do
            local text, color
            if c.key == 'name' then
                text, color = name, nameColor
            elseif c.key == 'state' then
                text, color = stateText, stateColor
            elseif c.key == 'score' then
                text, color = T('hud.money', math.floor(p.earnedTotal or 0)), { 1, 0.85, 0.3 }
            else
                text, color = T('hud.money', math.floor(p.money or 0)), { 0.8, 0.8, 0.8 }
            end
            cell(c, rx, ry, text, color)
            rx = rx + c.w
        end
    end

    -- footer: wave and total kills, which are the run's numbers rather than
    -- any one player's
    local foot = T('score.footer', world.waves.wave or 1, world.kills or 0)
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print(foot,
        math.floor(SCREENWIDTH / 2 - font:getWidth(foot) / 2), y + h + 12)
    love.graphics.setColor(Color.white())
end

return Scoreboard
