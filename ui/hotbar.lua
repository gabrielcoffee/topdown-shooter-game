-- Minecraft-style hotbar: 5 squares bottom-center at native resolution.
-- [1] gun A, [2] gun B, [3] knife, [4] grenades (count), [5] med kit.
-- Drawn from Player:drawHud, so it's outside the lighting pass.

local Assets = require('core.assets')

local Hotbar = {}

local function drawItemIcon(item, x, y, size)
    -- hotbar shows the bare item; in-hand sprite has the hands baked in
    local quad = item.icon or item.sprite
    local _, _, qw, qh = quad:getViewport()
    local scale = math.min((size - 12) / qw, (size - 12) / qh)
    love.graphics.draw(
        Assets.spritesheet, quad,
        math.floor(x + size/2), math.floor(y + size/2),
        0, scale, scale, qw/2, qh/2
    )
end

function Hotbar.draw(player)
    local t = TUNE.hotbar
    local size, gap = t.slotSize, t.gap
    local totalW = 5 * size + 4 * gap
    local x0 = math.floor((SCREENWIDTH - totalW) / 2)
    local y0 = SCREENHEIGHT - t.bottomMargin - size

    for i = 1, 5 do
        local x = x0 + (i - 1) * (size + gap)
        local item = player.items[i]
        local valid = player:slotValid(i)
        local selected = (i == player.itemIndex)

        -- slot background + border
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle('fill', x, y0, size, size, 3, 3)
        if selected then
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(1, 1, 1, 0.25)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle('line', x, y0, size, size, 3, 3)
        love.graphics.setLineWidth(1)

        -- use cooldown (throwables / med kits): 0..1 left, drives a dim + bar
        local cd = 0
        if i == 4 and player.throwTimer > 0 then
            cd = player.throwTimer / TUNE.throwables.useDelay
        elseif i == 5 and player.healTimer > 0 then
            cd = player.healTimer / TUNE.healthpack.useDelay
        end

        if item then
            -- greyed out when unusable (no grenades left) or still cooling down
            local a = valid and (cd > 0 and 0.45 or 1) or 0.25
            local tint = item.iconTint
            if tint then -- molotov placeholder: grenade art tinted orange
                love.graphics.setColor(tint[1], tint[2], tint[3], a)
            else
                love.graphics.setColor(1, 1, 1, a)
            end
            drawItemIcon(item, x, y0, size)

            -- corner counters: clip for guns, count for throwables
            local cntY = y0 + size - font:getHeight() - 4
            love.graphics.setColor(1, 1, 1, math.max(a, 0.5))
            if item.isGun then
                local txt = tostring(item.curClip)
                love.graphics.print(txt,
                    x + size - font:getWidth(txt) - 4, cntY)
            elseif item.isThrowable then
                local txt = tostring(player:throwableCount())
                love.graphics.print(txt,
                    x + size - font:getWidth(txt) - 4, cntY)
                -- the stowed throwable's count sits bottom-left, dimmed
                local other = player.throwableType == 'molotov'
                    and player.grenades or player.molotovs
                if other > 0 then
                    love.graphics.setColor(1, 1, 1, 0.35)
                    love.graphics.print(other, x + 4, cntY)
                end
            elseif item.isHealthPack then
                local txt = tostring(player.medkits)
                love.graphics.print(txt,
                    x + size - font:getWidth(txt) - 4, cntY)
            end

            -- full stack: "(MAX)" called out right above the slot
            local maxed
            if item.isThrowable then
                maxed = player.grenades + player.molotovs >= TUNE.throwables.maxCarry
            elseif item.isHealthPack then
                maxed = player.medkits >= TUNE.healthpack.maxCarry
            end
            if maxed then
                local txt = 'MAX' -- fits the slot width; "(MAX)" collided with +50HP
                love.graphics.setColor(1, 0.85, 0.3, 0.9)
                love.graphics.print(txt,
                    x + (size - font:getWidth(txt)) / 2, y0 - font:getHeight() - 4)
            end
        end

        -- cooldown sweep: a bar along the bottom edge filling back to full
        if cd > 0 then
            love.graphics.setColor(1, 1, 1, 0.7)
            love.graphics.rectangle('fill', x + 2, y0 + size - 3,
                (size - 4) * (1 - cd), 2)
        end

        -- slot number
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.print(tostring(i), x + 4, y0 + 3)
    end

    love.graphics.setColor(1, 1, 1)
end

return Hotbar
