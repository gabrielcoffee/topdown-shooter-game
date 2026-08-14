-- Action -> key map. Every gameplay input read goes through here instead of
-- calling love.keyboard.isDown with a literal, so keys can be rebound
-- (states/keybinds.lua) and so core/input.lua can build the one input struct
-- the player reads (and, in multiplayer, the one that goes on the wire).
--
-- A binding is a key constant ('w', 'lshift') or a mouse button ('mouse1'..
-- 'mouse5'). Bindings live in settings.lua under SETTINGS.keybinds.

local Keybinds = {}

-- Listing order = the order the rebind screen draws them in.
Keybinds.actions = {
    'move_up', 'move_down', 'move_left', 'move_right', 'sprint',
    'shoot', 'reload', 'interact', 'drop', 'quickknife',
    'slot1', 'slot2', 'slot3', 'slot4', 'slot5',
    'chat', 'voice', 'scoreboard',
}

Keybinds.defaults = {
    move_up = 'w', move_down = 's', move_left = 'a', move_right = 'd',
    sprint = 'lshift',
    shoot = 'mouse1', reload = 'r', interact = 'e', drop = 'g',
    quickknife = 'q',
    slot1 = '1', slot2 = '2', slot3 = '3', slot4 = '4', slot5 = '5',
    chat = 't', voice = 'v', scoreboard = 'tab',
}

-- Escape always means "back out" (menus, pause, cancelling a rebind), so it
-- can never be captured as a binding.
Keybinds.reserved = { escape = true }

local map = {}

-- Fills any missing/invalid action from defaults, so a hand-edited or
-- outdated settings.lua can never leave an action unbound.
function Keybinds.init(settings)
    settings.keybinds = settings.keybinds or {}
    map = {}
    for _, action in ipairs(Keybinds.actions) do
        local k = settings.keybinds[action]
        if type(k) ~= 'string' or k == '' or Keybinds.reserved[k] then
            k = Keybinds.defaults[action]
        end
        map[action] = k
        settings.keybinds[action] = k
    end
end

function Keybinds.get(action)
    return map[action]
end

function Keybinds.set(action, key)
    if Keybinds.reserved[key] then return false end
    map[action] = key
    SETTINGS.keybinds = SETTINGS.keybinds or {}
    SETTINGS.keybinds[action] = key
    return true
end

function Keybinds.reset()
    for _, action in ipairs(Keybinds.actions) do
        Keybinds.set(action, Keybinds.defaults[action])
    end
end

local function mouseButton(key)
    return key and tonumber(key:match('^mouse(%d)$'))
end

-- Is this action's key held right now? Mouse bindings route to love.mouse.
function Keybinds.isDown(action)
    local key = map[action]
    if not key then return false end
    local btn = mouseButton(key)
    if btn then return love.mouse.isDown(btn) end
    return love.keyboard.isDown(key)
end

-- Does a raw key/mouse event match this action? (for keypressed-style edges)
function Keybinds.matches(action, key)
    return map[action] == key
end

-- Actions bound to the same key, as a set of action names. The rebind screen
-- draws these red. Conflicts are allowed to persist (Minecraft does the same)
-- so a mid-rebind state isn't rejected.
function Keybinds.conflicts()
    local byKey, bad = {}, {}
    for _, action in ipairs(Keybinds.actions) do
        local k = map[action]
        if byKey[k] then
            bad[action] = true
            bad[byKey[k]] = true
        else
            byKey[k] = action
        end
    end
    return bad
end

-- Human-readable key name for the rebind screen and the controls splash.
-- PressStart2P has no lowercase-friendly glyph set here, so everything is
-- uppercased the way the rest of the menu text is.
local PRETTY = {
    lshift = 'L SHIFT', rshift = 'R SHIFT',
    lctrl = 'L CTRL', rctrl = 'R CTRL',
    lalt = 'L ALT', ralt = 'R ALT',
    lgui = 'L CMD', rgui = 'R CMD',
    space = 'SPACE', tab = 'TAB', capslock = 'CAPS',
    ['return'] = 'ENTER', kpenter = 'KP ENTER', backspace = 'BKSP',
    up = 'UP', down = 'DOWN', left = 'LEFT', right = 'RIGHT',
    mouse1 = 'MOUSE L', mouse2 = 'MOUSE R', mouse3 = 'MOUSE M',
    mouse4 = 'MOUSE 4', mouse5 = 'MOUSE 5',
}

function Keybinds.keyLabel(key)
    if not key then return '---' end
    return PRETTY[key] or key:upper()
end

function Keybinds.label(action)
    return Keybinds.keyLabel(map[action])
end

return Keybinds
