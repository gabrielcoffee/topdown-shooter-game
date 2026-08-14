-- Small single-line text field for the multiplayer screens (player name,
-- direct IP). Deliberately not ui/chat.lua: that is a 700-line console with
-- selection, history and clipboard, and none of that belongs in a name box.
--
-- A field filters keystrokes as they arrive, so an illegal character never
-- appears on screen in the first place.

local Theme = require('ui.theme')

local TextField = {}
TextField.__index = TextField

-- opts: { value, maxLen, filter = fn(char) -> bool, placeholder }
function TextField:new(opts)
    opts = opts or {}
    return setmetatable({
        value = opts.value or '',
        maxLen = opts.maxLen or 20,
        filter = opts.filter,
        placeholder = opts.placeholder,
        caretT = 0,
        active = false,
    }, TextField)
end

function TextField:focus()
    self.active = true
    self.caretT = 0
    love.keyboard.setKeyRepeat(true) -- holding backspace should keep deleting
end

function TextField:blur()
    self.active = false
    love.keyboard.setKeyRepeat(false)
end

function TextField:set(v) self.value = v or '' end
function TextField:get() return self.value end

function TextField:update(dt)
    if self.active then self.caretT = self.caretT + dt end
end

function TextField:textinput(t)
    if not self.active then return end
    if #self.value >= self.maxLen then return end
    if self.filter and not self.filter(t) then return end
    self.value = self.value .. t
    self.caretT = 0
end

-- Returns 'commit' / 'cancel' when the field is done, nil while still editing
function TextField:keypressed(key)
    if not self.active then return nil end
    if key == 'backspace' then
        self.value = self.value:sub(1, -2)
        self.caretT = 0
    elseif key == 'return' or key == 'kpenter' then
        return 'commit'
    elseif key == 'escape' then
        return 'cancel'
    end
    return nil
end

-- Draws a boxed field. `bad` outlines it in the conflict colour, for a name
-- that has not passed validation yet.
function TextField:draw(x, y, w, bad)
    local f = Theme.fonts.item
    local h = f:getHeight() + 16
    love.graphics.setFont(f)

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle('fill', x, y, w, h, 4, 4)

    local edge = bad and Theme.colors.conflict
        or (self.active and Theme.colors.blood or Theme.colors.textDim)
    love.graphics.setColor(edge[1], edge[2], edge[3])
    love.graphics.setLineWidth(2)
    love.graphics.rectangle('line', x, y, w, h, 4, 4)
    love.graphics.setLineWidth(1)

    local text = self.value
    local c = Theme.colors.text
    if text == '' and not self.active and self.placeholder then
        text = self.placeholder
        c = Theme.colors.textDim
    end
    love.graphics.setColor(c[1], c[2], c[3])

    -- long values scroll so the caret end stays visible
    local pad = 10
    local tw = f:getWidth(text)
    local offset = math.max(0, tw - (w - pad * 2))
    love.graphics.push()
    love.graphics.translate(-offset, 0)
    love.graphics.print(text, x + pad, y + 8)

    if self.active and math.floor(self.caretT * 2) % 2 == 0 then
        local cx = x + pad + tw + 1
        love.graphics.setColor(Theme.colors.blood)
        love.graphics.rectangle('fill', cx, y + 8, 2, f:getHeight())
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
    return h
end

return TextField
