-- Game state stack. States live in states/<name>.lua and expose any of:
-- enter(opts) / exit() / update(dt) / draw() / keypressed(key) /
-- mousepressed(x, y, btn) / mousemoved(x, y) / mousereleased(x, y, btn)
-- States with .overlay = true let the state below them draw first
-- (pause menu over the frozen world, options over whatever opened it).

local State = {}
State.stack = {}

local function resolve(s)
    if type(s) == 'string' then
        return require('states.' .. s)
    end
    return s
end

-- Replace the whole stack with one state
function State.switch(s, opts)
    for i = #State.stack, 1, -1 do
        local old = State.stack[i]
        if old.exit then old:exit() end
        State.stack[i] = nil
    end
    State.push(s, opts)
end

-- Push a state on top (the one below keeps drawing if this one is an overlay)
function State.push(s, opts)
    s = resolve(s)
    table.insert(State.stack, s)
    if s.enter then s:enter(opts) end
end

function State.pop()
    local s = table.remove(State.stack)
    if s and s.exit then s:exit() end
end

function State.current()
    return State.stack[#State.stack]
end

-- Fade to black, switch, fade back in. Input is blocked while fading.
local fade = nil

function State.fadeTo(target, opts)
    if fade then return end
    fade = { phase = 'out', t = 0, target = target, opts = opts }
end

function State.fading()
    return fade ~= nil
end

local function fadeAlpha()
    local dur = TUNE.fx.fadeTime
    local p = math.min(1, fade.t / dur)
    if fade.phase == 'out' then return p end
    return 1 - p
end

local function updateFade(dt)
    if not fade then return end
    fade.t = fade.t + dt
    if fade.t >= TUNE.fx.fadeTime then
        if fade.phase == 'out' then
            State.switch(fade.target, fade.opts)
            fade.phase = 'in'
            fade.t = 0
        else
            fade = nil
        end
    end
end

-- Only the top state updates (pausing freezes the world for free)
function State.update(dt)
    local s = State.current()
    if s and s.update then s:update(dt) end
    updateFade(dt)
end

-- Overlays draw the states below them first
function State.draw()
    local from = #State.stack
    while from > 1 and State.stack[from].overlay do
        from = from - 1
    end
    for i = from, #State.stack do
        local s = State.stack[i]
        if s.draw then s:draw() end
    end

    if fade then
        love.graphics.setColor(0, 0, 0, fadeAlpha())
        love.graphics.rectangle('fill', 0, 0, SCREENWIDTH, SCREENHEIGHT)
        love.graphics.setColor(1, 1, 1)
    end
end

function State.keypressed(key)
    if fade then return end
    local s = State.current()
    if s and s.keypressed then s:keypressed(key) end
end

function State.textinput(t)
    if fade then return end
    local s = State.current()
    if s and s.textinput then s:textinput(t) end
end

function State.mousepressed(x, y, btn)
    if fade then return end
    local s = State.current()
    if s and s.mousepressed then s:mousepressed(x, y, btn) end
end

function State.mousemoved(x, y)
    if fade then return end
    local s = State.current()
    if s and s.mousemoved then s:mousemoved(x, y) end
end

function State.mousereleased(x, y, btn)
    if fade then return end
    local s = State.current()
    if s and s.mousereleased then s:mousereleased(x, y, btn) end
end

return State
