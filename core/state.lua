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

-- Only the top state updates (pausing freezes the world for free)
function State.update(dt)
    local s = State.current()
    if s and s.update then s:update(dt) end
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
end

function State.keypressed(key)
    local s = State.current()
    if s and s.keypressed then s:keypressed(key) end
end

function State.mousepressed(x, y, btn)
    local s = State.current()
    if s and s.mousepressed then s:mousepressed(x, y, btn) end
end

function State.mousemoved(x, y)
    local s = State.current()
    if s and s.mousemoved then s:mousemoved(x, y) end
end

function State.mousereleased(x, y, btn)
    local s = State.current()
    if s and s.mousereleased then s:mousereleased(x, y, btn) end
end

return State
