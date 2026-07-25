-- Reusable vertical menu. Keyboard (arrows/WASD + Enter, handled via
-- keypressed) and mouse (hover selects, click activates/drags) both work.
-- Item shapes:
--   { label = 'menu.new_game', type = 'action', activate = fn }
--   { label = 'options.master', type = 'slider', get = fn, set = fn }  -- 0..1
--   { label = 'options.language', type = 'cycle', value = fn, cycle = fn(dir) }
-- Labels are i18n keys resolved with T() at draw time, so language
-- switches update every open menu instantly.

local Theme = require('ui.theme')
local Audio = require('core.audio')

local MenuList = {}
MenuList.__index = MenuList

local SLIDER_W = 240
local SLIDER_H = 12

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

local function itemY(self, i)
    return self.y + (i - 1) * self.spacing
end

-- Wide hover band centered on screen
local function itemHovered(self, i, mx, my)
    local yy = itemY(self, i)
    return mx > SCREENWIDTH / 2 - 340 and mx < SCREENWIDTH / 2 + 340
        and my >= yy - self.spacing / 2 + 10 and my < yy + self.spacing / 2 + 10
end

local function sliderRect(self, i)
    local x = SCREENWIDTH / 2 + 40
    local y = itemY(self, i) + Theme.fonts.item:getHeight() / 2 - SLIDER_H / 2
    return x, y, SLIDER_W, SLIDER_H
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
    if item.type == 'action' and item.activate then
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
                -- only clicks on the bar itself (small pad) grab it: the hover
                -- band spans the whole row, and a click on the label used to
                -- clamp to 0 and slam the volume to zero
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
    local cx = SCREENWIDTH / 2

    for i, item in ipairs(self.items) do
        local yy = itemY(self, i)
        local isSel = (i == self.selected)
        local disabled = item.enabled and not item.enabled()
        local c = disabled and Theme.colors.barBack
            or (isSel and Theme.colors.blood or Theme.colors.text)

        -- staggered slide-in: each row eases in from the left, delayed by index
        local p = math.min(1, math.max(0,
            (self.animT - (i - 1) * TUNE.fx.itemStagger) / TUNE.fx.itemInTime))
        local ease = 1 - (1 - p) ^ 3
        local a = ease
        local slide = (1 - ease) * -70

        love.graphics.push()
        love.graphics.translate(slide, 0)

        if item.type == 'slider' then
            -- label on the left, bar on the right
            love.graphics.setColor(c[1], c[2], c[3], a)
            local label = T(item.label)
            love.graphics.print(label, cx - 40 - f:getWidth(label), yy)

            local x, y, w, h = sliderRect(self, i)
            local bb = Theme.colors.barBack
            love.graphics.setColor(bb[1], bb[2], bb[3], a)
            love.graphics.rectangle('fill', x, y, w, h)
            local fillC = isSel and Theme.colors.blood or Theme.colors.textDim
            love.graphics.setColor(fillC[1], fillC[2], fillC[3], a)
            love.graphics.rectangle('fill', x, y, w * item.get(), h)

            love.graphics.setFont(Theme.fonts.hint)
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print(math.floor(item.get() * 100 + 0.5) .. '%', x + w + 16, yy + 4)
            love.graphics.setFont(f)
        else
            local text = T(item.label)
            if item.type == 'cycle' then
                text = text .. ': ' .. item.value()
            end
            local x = cx - f:getWidth(text) / 2
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print(text, x, yy)
        end

        -- pulsing selector chevron
        if isSel then
            local pulse = math.sin(love.timer.getTime() * TUNE.menu.pulseSpeed) * 6
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print('>', cx - 380 + pulse, yy)
            love.graphics.print('<', cx + 380 - f:getWidth('<') + -pulse, yy)
        end

        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1)
end

return MenuList
