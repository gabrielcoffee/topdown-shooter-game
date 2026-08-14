-- Pre-run lobby: who is in, who is ready, and the settings the host owns.
-- The host presses START; clients toggle READY and wait. Latecomers can also
-- join a run already in progress, in which case they skip this screen
-- entirely (net/session.lua admits them straight to 'playing').

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Particles = require('ui.particles')
local Session = require('net.session')
local Discovery = require('net.discovery')

local lobby = {}
lobby.fxMode = 'menu'

local SLOT_TOP = 300
local SLOT_H = 54

function lobby:enter()
    self.status = nil
    self.ready = Session.isHost() -- the host counts as ready to itself

    -- the run begins for everyone the moment START lands
    Session.onStart = function()
        State.fadeTo('playing', { multiplayer = true })
    end

    local items = {}
    if Session.isHost() then
        items[#items + 1] = {
            label = 'net.voice_mode', type = 'cycle',
            value = function()
                return Session.voiceMode == 'proximity'
                    and T('net.voice_proximity') or T('net.voice_global')
            end,
            cycle = function()
                Session.setVoiceMode(
                    Session.voiceMode == 'proximity' and 'global' or 'proximity')
            end,
        }
        items[#items + 1] = {
            label = 'net.start_run', type = 'action',
            activate = function() Session.startRun() end,
        }
    else
        items[#items + 1] = {
            type = 'action',
            text = function()
                return self.ready and T('net.unready') or T('net.ready')
            end,
            activate = function()
                self.ready = not self.ready
                Session.setReady(self.ready)
            end,
        }
    end
    items[#items + 1] = {
        label = 'net.leave', type = 'action',
        activate = function() self:leave() end,
    }

    -- under the four slot boxes, which end around y=480
    self.list = MenuList:new(items, 540)
end

function lobby:leave()
    Session.onStart = nil
    Session.leave()
    State.fadeTo('multiplayer')
end

function lobby:exit()
    Session.onStart = nil
end

function lobby:update(dt)
    -- pumped globally from love.update, see states/multiplayer.lua
    Particles.update(dt)
    self.list:update(dt)

    -- host vanished, or we were rejected
    if Session.state == 'offline' then
        self.status = Session.errorKey and T(Session.errorKey) or nil
        Session.errorKey = nil
        if not State.fading() then State.fadeTo('multiplayer') end
    end
end

function lobby:draw()
    Theme.drawBackground()
    Particles.drawFog()
    Theme.drawTitle(T('net.lobby_title'), 130)

    local f = Theme.fonts.item
    local fh = Theme.fonts.hint
    local roster = Session.roster()

    -- four fixed slots, so an empty seat reads as a seat rather than as nothing
    for i = 1, TUNE.net.maxPlayers do
        local p = roster[i]
        local y = 215 + (i - 1) * SLOT_H
        local w, x = 620, SCREENWIDTH / 2 - 310

        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle('fill', x, y, w, SLOT_H - 8, 4, 4)

        local edge = p and Theme.colors.textDim or Theme.colors.barBack
        love.graphics.setColor(edge[1], edge[2], edge[3])
        love.graphics.rectangle('line', x, y, w, SLOT_H - 8, 4, 4)

        love.graphics.setFont(f)
        if p then
            local c = Theme.colors.text
            love.graphics.setColor(c[1], c[2], c[3])
            love.graphics.print(p.name, x + 16, y + 10)

            love.graphics.setFont(fh)
            if p.isHost then
                local hc = Theme.colors.nightmare
                love.graphics.setColor(hc[1], hc[2], hc[3])
                love.graphics.print(T('net.host_tag'), x + 16 + f:getWidth(p.name) + 18, y + 16)
            end
            local tag = p.ready and T('net.ready_tag') or T('net.waiting_tag')
            local tc = p.ready and Theme.colors.blood or Theme.colors.textDim
            love.graphics.setColor(tc[1], tc[2], tc[3])
            love.graphics.print(tag, x + w - 16 - fh:getWidth(tag), y + 16)
        else
            love.graphics.setFont(fh)
            local c = Theme.colors.barBack
            love.graphics.setColor(c[1], c[2], c[3])
            love.graphics.print(T('net.empty_slot'), x + 16, y + 16)
        end
    end
    love.graphics.setColor(1, 1, 1)

    self.list:draw()

    -- the host needs to know the address to read out on a network where
    -- broadcast is blocked
    love.graphics.setFont(fh)
    local dim = Theme.colors.textDim
    love.graphics.setColor(dim[1], dim[2], dim[3])
    if Session.isHost() then
        local ip = Discovery.localIP()
        if ip then
            local line = T('net.your_ip', ip .. ':' .. TUNE.net.gamePort)
            love.graphics.print(line, SCREENWIDTH / 2 - fh:getWidth(line) / 2, SCREENHEIGHT - 110)
        end
    end
    love.graphics.setColor(1, 1, 1)

    if self.status then
        local c = Theme.colors.conflict
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.print(self.status,
            SCREENWIDTH / 2 - fh:getWidth(self.status) / 2, SCREENHEIGHT - 80)
        love.graphics.setColor(1, 1, 1)
    end
end

function lobby:keypressed(key)
    if key == 'escape' then
        self:leave()
    else
        self.list:keypressed(key)
    end
end

function lobby:mousepressed(x, y, btn) self.list:mousepressed(x, y, btn) end
function lobby:mousemoved(x, y) self.list:mousemoved(x, y) end
function lobby:mousereleased(x, y, btn) self.list:mousereleased(x, y, btn) end

return lobby
