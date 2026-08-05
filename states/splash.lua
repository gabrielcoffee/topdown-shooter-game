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

function splash:enter()
    self.t = 0
    self.phase = 'in' -- in -> name -> presents -> out -> type -> (menu)
    self.typed = 0    -- letters of the title shown so far
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
        local title = Theme.gameTitle
        local target = math.min(#title, math.floor(self.t / S.typeInterval))
        while self.typed < target do
            self.typed = self.typed + 1
            local ch = title:sub(self.typed, self.typed)
            if ch ~= ' ' then Audio.play('dry_fire', S.typeGain) end
        end
        if self.typed >= #title and self.t >= #title * S.typeInterval + S.typeHold then
            self.phase = 'done'
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
        local c = Theme.colors.textDim

        local f = Theme.fonts.item -- normal text size, not the big title face
        love.graphics.setFont(f)
        love.graphics.setColor(c[1], c[2], c[3], a)
        local main = 'COFFEEBREAK'
        love.graphics.print(main, cx - f:getWidth(main) / 2, SCREENHEIGHT / 2 - 60)

        local fh = Theme.fonts.hint
        love.graphics.setFont(fh)
        local sub = 'G A M E S'
        love.graphics.setColor(c[1], c[2], c[3], a * 0.8)
        love.graphics.print(sub, cx - fh:getWidth(sub) / 2, SCREENHEIGHT / 2 - 24)

        -- presents: joins after the name has sat for a moment
        if self.phase == 'presents' or self.phase == 'out' then
            local pa = a
            if self.phase == 'presents' then
                pa = Theme.stepAlpha(self.t / S.presentsIn)
            end
            local msg = 'presents:'
            love.graphics.setColor(c[1], c[2], c[3], pa * 0.9)
            love.graphics.print(msg, cx - fh:getWidth(msg) / 2, SCREENHEIGHT / 2 + 40)
        end
    elseif self.phase == 'type' or self.phase == 'done' then
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
