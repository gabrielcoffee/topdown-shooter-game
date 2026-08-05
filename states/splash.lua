-- Studio card at launch: COFFEEBREAK GAMES in white on black. Slow fade in,
-- hold, fade out, then the menu fades in. Any key or click skips straight
-- to the fade-out. Timings in TUNE.splash.

local State = require('core.state')
local Theme = require('ui.theme')

local splash = {}
splash.fxMode = 'menu'

function splash:enter()
    self.t = 0
    self.phase = 'in' -- in -> hold -> out -> done
end

local function alphaFor(self)
    local S = TUNE.splash
    if self.phase == 'in' then return math.min(1, self.t / S.fadeIn) end
    if self.phase == 'hold' then return 1 end
    return 1 - math.min(1, self.t / S.fadeOut)
end

function splash:update(dt)
    local S = TUNE.splash
    self.t = self.t + dt
    if self.phase == 'in' and self.t >= S.fadeIn then
        self.phase, self.t = 'hold', 0
    elseif self.phase == 'hold' and self.t >= S.hold then
        self.phase, self.t = 'out', 0
    elseif self.phase == 'out' and self.t >= S.fadeOut then
        self.phase = 'done'
        State.fadeTo('menu')
    end
end

local function skip(self)
    if self.phase == 'in' or self.phase == 'hold' then
        self.phase, self.t = 'out', 0
    end
end

function splash:keypressed() skip(self) end
function splash:mousepressed() skip(self) end

function splash:draw()
    love.graphics.clear(0, 0, 0)
    local a = alphaFor(self)
    if self.phase == 'done' then a = 0 end

    local f = Theme.fonts.title
    love.graphics.setFont(f)
    love.graphics.setColor(1, 1, 1, a)
    local main = 'COFFEEBREAK'
    love.graphics.print(main, SCREENWIDTH / 2 - f:getWidth(main) / 2,
        SCREENHEIGHT / 2 - 80)

    local fi = Theme.fonts.item
    love.graphics.setFont(fi)
    local sub = 'G A M E S'
    love.graphics.setColor(1, 1, 1, a * 0.85)
    love.graphics.print(sub, SCREENWIDTH / 2 - fi:getWidth(sub) / 2,
        SCREENHEIGHT / 2 - 8)

    love.graphics.setColor(1, 1, 1)
end

return splash
