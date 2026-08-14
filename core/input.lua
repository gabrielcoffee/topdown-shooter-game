-- The one input struct Player:update reads. Solo and host fill it from the
-- keyboard; in multiplayer a client fills its own copy, sends it, and the
-- host fills each remote player's copy from the packet. Player code never
-- learns which of the three it is.
--
-- Fields are RAW held state, not gated: the player's own lockedInputs pass
-- (buttons still held after a hole fall) needs to see a button that is
-- physically down even while the chat has focus, so `typing` travels as its
-- own flag instead of being folded into the booleans.

local Keybinds = require('core.keybinds')

local Input = {}

-- Held-button fields, in the order they pack onto the wire later
Input.buttons = {
    'up', 'down', 'left', 'right', 'sprint',
    'shoot', 'reload', 'interact', 'drop', 'quickknife',
    'slot1', 'slot2', 'slot3', 'slot4', 'slot5',
}

-- Which action drives which field
local ACTION = {
    up = 'move_up', down = 'move_down', left = 'move_left', right = 'move_right',
    sprint = 'sprint', shoot = 'shoot', reload = 'reload', interact = 'interact',
    drop = 'drop', quickknife = 'quickknife',
    slot1 = 'slot1', slot2 = 'slot2', slot3 = 'slot3',
    slot4 = 'slot4', slot5 = 'slot5',
}

function Input.new()
    local inp = { seq = 0, aimX = 0, aimY = 0, typing = false }
    for _, b in ipairs(Input.buttons) do inp[b] = false end
    return inp
end

-- Fill `inp` from the local keyboard/mouse. camX/camY put the cursor into
-- world space, which is what the host needs — it has no idea where this
-- player's camera is looking.
function Input.poll(inp, camX, camY, typing)
    for _, b in ipairs(Input.buttons) do
        inp[b] = Keybinds.isDown(ACTION[b])
    end

    local mx, my = require('ui.screen').mouse()
    inp.aimX = mx / SCALE + camX
    inp.aimY = my / SCALE + camY
    inp.typing = typing and true or false
    inp.seq = inp.seq + 1
    return inp
end

-- Everything released: what a downed player, or a player whose window just
-- lost focus, feeds into Player:update.
function Input.clear(inp)
    for _, b in ipairs(Input.buttons) do inp[b] = false end
    inp.typing = false
    return inp
end

return Input
