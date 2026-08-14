-- Reusable menu list. Keyboard (arrows/WASD + Enter, handled via
-- keypressed) and mouse (hover selects, click activates/drags) both work.
-- Item shapes:
--   { label = 'menu.new_game', type = 'action', activate = fn }
--   { label = 'options.master', type = 'slider', get = fn, set = fn }  -- 0..1
--   { label = 'options.language', type = 'cycle', value = fn, cycle = fn(dir) }
--   { label = 'keys.move_up', type = 'keybind', value = fn, activate = fn,
--     conflict = fn -> bool, capturing = fn -> bool }
-- An item may replace `label` with `text = fn -> string` when its caption is
-- built at runtime rather than translated (the LAN server list rows).
-- Layout: single centered column by default. Items may set col (1 = left
-- column, 2 = right column) + row for a two-column grid (options menu);
-- col-less items stay centered on their row.
-- Labels are i18n keys resolved with T() at draw time, so language
-- switches update every open menu instantly.

local Theme = require('ui.theme')
local Audio = require('core.audio')

local MenuList = {}
MenuList.__index = MenuList

-- Caption for an item: a runtime `text` function wins over the i18n key, so
-- rows like "Notch's game   2/4" can live in the same list as translated ones.
local function captionOf(item)
    if item.text then return item.text() end
    return T(item.label)
end

local SLIDER_W = 240
local SLIDER_H = 12
local COL_SLIDER_W = 190 -- narrower bar so a slider row fits half the screen
local PCT_W = 70         -- reserved width of the value text after the bar

function MenuList:new(items, y, spacing)
    local obj = {
        items = items,
        y = y,
        spacing = spacing or TUNE.menu.itemSpacing,
        selected = 1,
        dragging = false,
        animT = 0, -- staggered slide-in progress since the list appeared
    }
    setmetatable(obj, MenuList)
    return obj
end

-- Column center x + row y for an item
local function itemPos(self, i)
    local item = self.items[i]
    local cx = SCREENWIDTH / 2
    if item.col == 1 then
        cx = cx - TUNE.menu.colOffset
    elseif item.col == 2 then
        cx = cx + TUNE.menu.colOffset
    end
    return cx, self.y + ((item.row or i) - 1) * self.spacing
end

local function sliderRect(self, i)
    local item = self.items[i]
    local cx, yy = itemPos(self, i)
    local x = item.col and (cx + 8) or (SCREENWIDTH / 2 + 40)
    local w = item.col and COL_SLIDER_W or SLIDER_W
    local y = yy + Theme.fonts.item:getHeight() / 2 - SLIDER_H / 2
    return x, y, w, SLIDER_H
end

-- Keybind row geometry: where the label ends and where the key text starts
local function keybindX(self, i)
    local cx = itemPos(self, i)
    local item = self.items[i]
    if item.col then return cx - 8, cx + 8 end
    return SCREENWIDTH / 2 - 40, SCREENWIDTH / 2 + 40
end

-- Horizontal extent of the item's drawn content (label+bar+value for
-- sliders, the text itself otherwise). Hover and the > < selectors both
-- work off this, so the mouse targets the word, not the whole row.
local function itemBounds(self, i)
    local f = Theme.fonts.item
    local item = self.items[i]
    local cx = itemPos(self, i)
    if item.type == 'slider' then
        local labelW = f:getWidth(captionOf(item))
        local x, _, w = sliderRect(self, i)
        local labelRight = item.col and (cx - 8) or (SCREENWIDTH / 2 - 40)
        return labelRight - labelW, x + w + 16 + PCT_W
    end
    if item.type == 'keybind' then
        -- same split as a slider row: label right-aligned left of centre,
        -- key text starting right of it
        local labelW = f:getWidth(captionOf(item))
        local labelRight, keyX = keybindX(self, i)
        return labelRight - labelW,
               keyX + Theme.fonts.hint:getWidth(item.value())
    end
    local text = captionOf(item)
    if item.type == 'cycle' then text = text .. ': ' .. item.value() end
    local w = f:getWidth(text)
    return cx - w / 2, cx + w / 2
end

-- The word itself (plus a small pad), not a screen-wide band
local function itemHovered(self, i, mx, my)
    local x0, x1 = itemBounds(self, i)
    local _, yy = itemPos(self, i)
    local fh = Theme.fonts.item:getHeight()
    return mx >= x0 - 6 and mx <= x1 + 6 and my >= yy - 4 and my < yy + fh + 4
end

local function moveSelection(self, dir)
    self.selected = ((self.selected - 1 + dir) % #self.items) + 1
    Audio.play('shell1', 0.4)
end

local function adjust(self, dir)
    local item = self.items[self.selected]
    if item.type == 'slider' then
        item.set(math.max(0, math.min(1, item.get() + dir * 0.05)))
    elseif item.type == 'cycle' then
        item.cycle(dir)
        Audio.play('shell2', 0.5)
    end
end

local function activate(self)
    local item = self.items[self.selected]
    if item.enabled and not item.enabled() then return end
    if (item.type == 'action' or item.type == 'keybind') and item.activate then
        Audio.play('shell2', 0.5)
        item.activate()
    elseif item.type == 'cycle' then
        item.cycle(1)
        Audio.play('shell2', 0.5)
    end
end

function MenuList:keypressed(key)
    if key == 'up' or key == 'w' then
        moveSelection(self, -1)
    elseif key == 'down' or key == 's' then
        moveSelection(self, 1)
    elseif key == 'left' or key == 'a' then
        adjust(self, -1)
    elseif key == 'right' or key == 'd' then
        adjust(self, 1)
    elseif key == 'return' or key == 'kpenter' or key == 'space' then
        activate(self)
    end
end

function MenuList:mousemoved(x, y)
    if self.dragging then return end -- a drag in progress can't re-target
    for i = 1, #self.items do
        if itemHovered(self, i, x, y) and self.selected ~= i then
            self.selected = i
            Audio.play('shell1', 0.3)
        end
    end
end

local function setSliderFromMouse(self, i, mx)
    local x, _, w = sliderRect(self, i)
    local item = self.items[i]
    item.set(math.max(0, math.min(1, (mx - x) / w)))
end

function MenuList:mousepressed(x, y, btn)
    if btn ~= 1 then return end
    for i, item in ipairs(self.items) do
        if itemHovered(self, i, x, y) then
            self.selected = i
            if item.type == 'slider' then
                -- only clicks on the bar itself (small pad) grab it: a click
                -- on the label used to clamp to 0 and slam the volume to zero
                local sx, _, sw = sliderRect(self, i)
                if x >= sx - 8 and x <= sx + sw + 8 then
                    setSliderFromMouse(self, i, x)
                    self.dragging = true
                    self.dragIndex = i -- the drag stays on this row, whatever hovers
                end
            else
                activate(self)
            end
            return
        end
    end
end

function MenuList:mousereleased(_, _, btn)
    if btn == 1 then self.dragging = false end
end

function MenuList:update(dt)
    self.animT = self.animT + dt
    if self.dragging then
        if love.mouse.isDown(1) then
            local i = self.dragIndex or self.selected
            local item = self.items[i]
            if item and item.type == 'slider' then
                setSliderFromMouse(self, i, (require('ui.screen').mouse()))
            end
        else
            self.dragging = false
        end
    end
end

function MenuList:draw()
    local f = Theme.fonts.item
    love.graphics.setFont(f)

    for i, item in ipairs(self.items) do
        local cx, yy = itemPos(self, i)
        local isSel = (i == self.selected)
        local disabled = item.enabled and not item.enabled()
        local c = disabled and Theme.colors.barBack
            or (isSel and Theme.colors.blood or Theme.colors.text)

        -- entrance: NES-stepped group fade (main menu) or the classic
        -- staggered slide-in from the left (everything else)
        local a, slide
        if self.nesFade then
            a = Theme.stepAlpha(math.max(0, math.min(1, self.animT / TUNE.menu.fadeInTime)))
            slide = 0
        else
            local p = math.min(1, math.max(0,
                (self.animT - (i - 1) * TUNE.fx.itemStagger) / TUNE.fx.itemInTime))
            local ease = 1 - (1 - p) ^ 3
            a = ease
            slide = (1 - ease) * -70
        end

        love.graphics.push()
        love.graphics.translate(slide, 0)

        if item.type == 'slider' then
            -- label on the left, bar on the right
            love.graphics.setColor(c[1], c[2], c[3], a)
            local label = captionOf(item)
            local labelRight = item.col and (cx - 8) or (SCREENWIDTH / 2 - 40)
            love.graphics.print(label, labelRight - f:getWidth(label), yy)

            local x, y, w, h = sliderRect(self, i)
            local bb = Theme.colors.barBack
            love.graphics.setColor(bb[1], bb[2], bb[3], a)
            love.graphics.rectangle('fill', x, y, w, h)
            local fillC = isSel and Theme.colors.blood or Theme.colors.textDim
            love.graphics.setColor(fillC[1], fillC[2], fillC[3], a)
            love.graphics.rectangle('fill', x, y, w * item.get(), h)

            love.graphics.setFont(Theme.fonts.hint)
            love.graphics.setColor(c[1], c[2], c[3], a)
            -- item.format (optional) turns the 0..1 value into custom text
            -- (brightness shows DARK/BRIGHT at the ends); default = percent
            local valueText = item.format and item.format(item.get())
                or (math.floor(item.get() * 100 + 0.5) .. '%')
            love.graphics.print(valueText, x + w + 16, yy + 4)
            love.graphics.setFont(f)
        elseif item.type == 'keybind' then
            -- label left, key right. Amber = this key is bound to another
            -- action too; blood already means "selected" so it can't mean
            -- "clash". While capturing the key text blinks as [ ... ].
            love.graphics.setColor(c[1], c[2], c[3], a)
            local label = captionOf(item)
            local labelRight, keyX = keybindX(self, i)
            love.graphics.print(label, labelRight - f:getWidth(label), yy)

            local capturing = item.capturing and item.capturing()
            local text = item.value()
            local kc = c
            if capturing then
                kc = Theme.colors.blood
                text = (math.floor(love.timer.getTime() * 3) % 2 == 0)
                    and '[ ... ]' or '[     ]'
            elseif item.conflict and item.conflict() then
                kc = Theme.colors.conflict
            end
            love.graphics.setFont(Theme.fonts.hint)
            love.graphics.setColor(kc[1], kc[2], kc[3], a)
            love.graphics.print(text, keyX, yy + 4)
            love.graphics.setFont(f)
        else
            local text = captionOf(item)
            if item.type == 'cycle' then
                text = text .. ': ' .. item.value()
            end
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print(text, cx - f:getWidth(text) / 2, yy)
        end

        -- pulsing selector chevrons, hugging the item's actual content
        if isSel then
            local x0, x1 = itemBounds(self, i)
            local gap = TUNE.menu.chevronGap
            local pulse = (math.sin(love.timer.getTime() * TUNE.menu.pulseSpeed) + 1) * 3
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print('>', x0 - gap - f:getWidth('>') - pulse, yy)
            love.graphics.print('<', x1 + gap + pulse, yy)
        end

        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1)
end

return MenuList
