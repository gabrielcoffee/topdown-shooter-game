-- Intro sequence, NES-style stepped fades throughout (Theme.stepAlpha):
--   1. COFFEEBREAK / GAMES card (normal-size font, dimmed white) fades in
--   2. after holdName secs, "presents:" fades in underneath
--   3. card fades out
--   4. CHAMBER 9 types itself letter by letter, a click per letter
--   5. menu takes over: the typed title glides to the top, items fade in
-- Any key/click during the card jumps to the typing; during the typing it
-- jumps straight to the menu.

local State = require('core.state')
local Theme = require('ui.theme')
local Audio = require('core.audio')

local splash = {}
splash.fxMode = 'menu'

-- Real typewriter key (CC0, freesound #380138 by yottasounds); each letter
-- plays a pitch-jittered clone.
local clickBase
local function playClick(self)
    if clickBase == false then return end -- looked once, not there
    if not clickBase then
        -- resolvePath, not the raw path: the web build ships everything as ogg
        local path = Audio.resolvePath('assets/sounds/effects/typewriter_key.mp3')
        clickBase = path and love.audio.newSource(path, 'static') or false
        if not clickBase then return end
    end
    local src = clickBase:clone()
    src:setPitch(0.94 + love.math.random() * 0.12)
    src:setVolume(Audio.master * Audio.sfx * TUNE.splash.typeGain)
    src:play()
    table.insert(self.clicks, src) -- held so GC can't cut a click short
end

function splash:enter()
    self.t = 0
    self.phase = 'in' -- in -> name -> presents -> out -> type -> (menu)
    self.typed = 0    -- letters of the title shown so far
    self.clicks = {}
end

function splash:update(dt)
    local S = TUNE.splash
    self.t = self.t + dt
    if self.phase == 'in' and self.t >= S.fadeIn then
        self.phase, self.t = 'name', 0
    elseif self.phase == 'name' and self.t >= S.holdName then
        self.phase, self.t = 'presents', 0
    elseif self.phase == 'presents' and self.t >= S.presentsIn + S.holdPresents then
        self.phase, self.t = 'out', 0
    elseif self.phase == 'out' and self.t >= S.fadeOut then
        self.phase, self.t = 'type', 0
    elseif self.phase == 'type' then
        for i = #self.clicks, 1, -1 do
            if not self.clicks[i]:isPlaying() then table.remove(self.clicks, i) end
        end
        local title = Theme.gameTitle
        local target = math.min(#title, math.floor(self.t / S.typeInterval))
        while self.typed < target do
            self.typed = self.typed + 1
            local ch = title:sub(self.typed, self.typed)
            if ch ~= ' ' then playClick(self) end
        end
        if self.typed >= #title and self.t >= #title * S.typeInterval + S.typeHold then
            self.phase = 'done'
            -- direct switch, no black fade: title + haze carry straight over
            State.switch('menu', { fromIntro = true })
        end
    end
end

local function skip(self)
    if self.phase == 'type' then
        self.phase = 'done'
        State.switch('menu') -- straight in: title already at the top
    elseif self.phase ~= 'done' then
        self.phase, self.t = 'type', 0
    end
end

function splash:keypressed() skip(self) end
function splash:mousepressed() skip(self) end

-- The typed title draws at this y; the menu starts its title here and
-- glides it up, so the handoff is seamless.
splash.titleY = SCREENHEIGHT / 2 - 60

function splash:draw()
    love.graphics.clear(0, 0, 0)
    local S = TUNE.splash
    local cx = SCREENWIDTH / 2

    if self.phase == 'in' or self.phase == 'name'
        or self.phase == 'presents' or self.phase == 'out' then
        local a = 1
        if self.phase == 'in' then a = Theme.stepAlpha(self.t / S.fadeIn) end
        if self.phase == 'out' then a = Theme.stepAlpha(1 - self.t / S.fadeOut) end

        -- two tight centered lines, white; presents: right after them
        local f = Theme.fonts.item
        love.graphics.setFont(f)
        love.graphics.setColor(1, 1, 1, a)
        local main = 'COFFEEBREAK'
        love.graphics.print(main, cx - f:getWidth(main) / 2, SCREENHEIGHT / 2 - 46)
        local sub = 'GAMES'
        love.graphics.print(sub, cx - f:getWidth(sub) / 2, SCREENHEIGHT / 2 - 14)

        if self.phase == 'presents' or self.phase == 'out' then
            local pa = a
            if self.phase == 'presents' then
                pa = Theme.stepAlpha(self.t / S.presentsIn)
            end
            local msg = 'presents:'
            love.graphics.setColor(1, 1, 1, pa * 0.9)
            love.graphics.print(msg, cx - f:getWidth(msg) / 2, SCREENHEIGHT / 2 + 34)
        end
    elseif self.phase == 'type' or self.phase == 'done' then
        -- typing happens on pure black; the haze fades in with the menu items
        local f = Theme.fonts.title
        love.graphics.setFont(f)
        local title = Theme.gameTitle
        local x = cx - f:getWidth(title) / 2 -- fixed left edge: types rightward
        local shown = title:sub(1, self.typed)
        local b = Theme.colors.blood
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.print(shown, x + 5, splash.titleY + 5)
        love.graphics.setColor(b[1], b[2], b[3])
        love.graphics.print(shown, x, splash.titleY)
    end

    love.graphics.setColor(1, 1, 1)
end

return splash
