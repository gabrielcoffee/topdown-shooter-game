-- LAN server browser. Hosts on the network announce themselves once a second
-- (net/discovery.lua) and show up here without anyone typing an address;
-- Direct IP stays as the fallback for a network that blocks broadcast.

local State = require('core.state')
local Theme = require('ui.theme')
local MenuList = require('ui.menu_list')
local Particles = require('ui.particles')
local TextField = require('ui.textfield')
local Discovery = require('net.discovery')
local Session = require('net.session')
local Name = require('core.name')

local multiplayer = {}
multiplayer.fxMode = 'menu'

-- which text field, if any, currently owns the keyboard
local EDIT_NONE, EDIT_NAME, EDIT_IP = nil, 'name', 'ip'

function multiplayer:enter()
    self.editing = EDIT_NONE
    self.status = nil
    self.listSignature = nil
    Session.errorKey = nil

    self.nameField = TextField:new({
        value = Name.get(), maxLen = Name.MAX, filter = Name.allowedChar,
    })
    self.ipField = TextField:new({
        value = '', maxLen = 21, placeholder = '192.168.1.10',
        filter = function(c) return c:match('^[%d%.:]$') ~= nil end,
    })

    Discovery.startBrowsing()
    self:rebuild()
end

function multiplayer:exit()
    -- the lobby keeps browsing off; leaving the screen entirely stops it
    if Session.state == 'offline' then Discovery.stopBrowsing() end
    if self.nameField then self.nameField:blur() end
    if self.ipField then self.ipField:blur() end
end

-- A stable string describing the current list, so the menu is only rebuilt
-- when something actually changed rather than every frame
local function signatureOf(list)
    local parts = {}
    for _, g in ipairs(list) do
        parts[#parts + 1] = ('%s|%s|%d|%s'):format(g.hostId, g.name, g.players, g.state)
    end
    return table.concat(parts, ';')
end

function multiplayer:join(game)
    local ok, err = Session.join(game.ip, game.port)
    if ok then
        State.push('lobby')
    else
        self.status = tostring(err)
    end
end

function multiplayer:rebuild()
    local games = Discovery.list()
    self.games = games
    self.listSignature = signatureOf(games)

    local items = {}

    if #games == 0 then
        items[#items + 1] = {
            label = 'net.searching', type = 'action',
            enabled = function() return false end,
            activate = function() end,
        }
    end
    for _, g in ipairs(games) do
        local game = g
        items[#items + 1] = {
            type = 'action',
            text = function()
                return ('%s   %d/%d   %s'):format(
                    game.name, game.players, game.maxPlayers,
                    game.state == 'playing' and T('net.in_progress') or T('net.in_lobby'))
            end,
            enabled = function() return game.players < game.maxPlayers end,
            activate = function() self:join(game) end,
        }
    end

    -- the action rows sit under the list with a fixed gap, rather than at a
    -- fixed row: pinning them low left a dead band on screen whenever fewer
    -- than a few games were listed
    local footer = math.max(4, #items + 2)
    items[#items + 1] = { label = 'net.host_game', type = 'action', row = footer,
        activate = function()
            local ok, err = Session.startHost()
            if ok then State.push('lobby') else self.status = tostring(err) end
        end }
    items[#items + 1] = { label = 'net.direct_ip', type = 'action', row = footer + 1,
        activate = function()
            self.editing = EDIT_IP
            self.ipField:focus()
        end }
    items[#items + 1] = { label = 'net.change_name', type = 'action', row = footer + 2,
        activate = function()
            self.editing = EDIT_NAME
            self.nameField:focus()
        end }
    items[#items + 1] = { label = 'options.back', type = 'action', row = footer + 3,
        activate = function() State.fadeTo('menu') end }

    local keep = self.list and self.list.selected or 1
    self.list = MenuList:new(items, 300)
    self.list.selected = math.max(1, math.min(keep, #items))
    self.list.animT = 10 -- rebuilt lists must not replay the slide-in

    -- never leave the cursor parked on a row that cannot be activated (the
    -- "searching..." placeholder, or a game that just filled up)
    local sel = items[self.list.selected]
    if sel and sel.enabled and not sel.enabled() then
        for i, it in ipairs(items) do
            if not it.enabled or it.enabled() then self.list.selected = i break end
        end
    end
end

function multiplayer:update(dt)
    -- Session/Discovery are pumped once globally from love.update; pumping
    -- again here would double the beacon rate and the timeout clocks
    Particles.update(dt)
    self.list:update(dt)
    self.nameField:update(dt)
    self.ipField:update(dt)

    if not self.editing then
        local sig = signatureOf(Discovery.list())
        if sig ~= self.listSignature then self:rebuild() end
    end

    if Session.errorKey then
        self.status = T(Session.errorKey)
        Session.errorKey = nil
    end
end

function multiplayer:draw()
    Theme.drawBackground()
    Particles.drawFog()
    Theme.drawTitle(T('net.title'), 130)

    local fh = Theme.fonts.hint
    love.graphics.setFont(fh)
    local dim = Theme.colors.textDim

    -- who you are, top right of the list
    local who = T('net.playing_as', Name.get())
    love.graphics.setColor(dim[1], dim[2], dim[3])
    love.graphics.print(who, SCREENWIDTH / 2 - fh:getWidth(who) / 2, 235)
    love.graphics.setColor(1, 1, 1)

    self.list:draw()

    if self.status then
        local c = Theme.colors.conflict
        love.graphics.setFont(fh)
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.print(self.status,
            SCREENWIDTH / 2 - fh:getWidth(self.status) / 2, SCREENHEIGHT - 90)
        love.graphics.setColor(1, 1, 1)
    end

    -- modal field over everything else
    if self.editing then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)

        local isName = self.editing == EDIT_NAME
        local field = isName and self.nameField or self.ipField
        local title = isName and T('net.enter_name') or T('net.enter_ip')
        Theme.drawTitle(title, 340)

        local w = 520
        local bad = isName and not Name.valid(field:get())
        field:draw(SCREENWIDTH / 2 - w / 2, 460, w, bad)

        local hint = T('net.field_hint')
        love.graphics.setFont(fh)
        local hc = bad and Theme.colors.conflict or dim
        if bad and field:get() ~= '' then
            local _, err = Name.validate(field:get())
            hint = T(err)
        end
        love.graphics.setColor(hc[1], hc[2], hc[3])
        love.graphics.print(hint, SCREENWIDTH / 2 - fh:getWidth(hint) / 2, 540)
        love.graphics.setColor(1, 1, 1)
    end
end

function multiplayer:commitField()
    if self.editing == EDIT_NAME then
        local ok = Name.set(self.nameField:get())
        if not ok then return false end -- keep editing until it is legal
        self.nameField:blur()
        self.editing = EDIT_NONE
        return true
    end

    local addr = self.ipField:get()
    local ip, port = addr:match('^([^:]+):(%d+)$')
    ip = ip or addr
    if ip == '' then return false end
    self.ipField:blur()
    self.editing = EDIT_NONE
    local ok, err = Session.join(ip, tonumber(port) or TUNE.net.gamePort)
    if ok then State.push('lobby') else self.status = tostring(err) end
    return true
end

function multiplayer:keypressed(key)
    if self.editing then
        local field = self.editing == EDIT_NAME and self.nameField or self.ipField
        local result = field:keypressed(key)
        if result == 'commit' then
            self:commitField()
        elseif result == 'cancel' then
            field:blur()
            if self.editing == EDIT_NAME then self.nameField:set(Name.get()) end
            self.editing = EDIT_NONE
        end
        return
    end

    if key == 'escape' then
        State.fadeTo('menu')
    else
        self.list:keypressed(key)
    end
end

function multiplayer:textinput(t)
    if self.editing then
        local field = self.editing == EDIT_NAME and self.nameField or self.ipField
        field:textinput(t)
    end
end

function multiplayer:mousepressed(x, y, btn)
    if self.editing then return end
    self.list:mousepressed(x, y, btn)
end

function multiplayer:mousemoved(x, y)
    if self.editing then return end
    self.list:mousemoved(x, y)
end

function multiplayer:mousereleased(x, y, btn)
    if self.editing then return end
    self.list:mousereleased(x, y, btn)
end

return multiplayer
