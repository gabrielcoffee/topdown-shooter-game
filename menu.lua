Menu = {}
Menu.__index = Menu

local function getMenuButton(text, func)
    return {
        text = text,
        func = func,
        hot = false,
        now = false,
        last = false
    }
end

local font = love.graphics.newFont(24)

function Menu:new(name, bw, bh, margin, allowMouse)
    local obj = {
        name = name,
        bw = bw,
        bh = bh,
        margin = margin,
        allowMouse = allowMouse or false,
        
        buttons = {}
     }

    setmetatable(obj)
    return obj
end

function Menu:addButton(text, func)
    local button = getMenuButton(text, func)

    button.bx = (SCREENWIDTH / 2) - (self.bw / 2)
    button.by = (SCREENHEIGHT / 2) - (totalH / 2) + curY
    table.insert(self.buttons, button)
end

function Menu:update(dt)

    local totalH = (self.bh + self.margin) * #self.buttons
    local curY = 0

    for i, button in ipairs(self.buttons) do

        local mx, my = love.mouse.getPosition()

        button.hot = mx >= button.x and mx <= button.x + self.bw and
                     my >= button.y and my <= button.y + self.bh

        button.last = button.now
        button.now = love.mouse.isDown(1)

        if button.now and not button.last and button.hot then
            button.func()
        end
    end
end

function Menu:draw()

    local curY = 0

    for i, button in ipairs(self.buttons) do
        if button.hot then
            love.graphics.setColor(0.7, 0.7, 0.8)    
        else
            love.graphics.setColor(0.4, 0.4, 0.5)
        end

        love.graphics.rectangle('fill', button.x, button.y, self.bw, self.bh)

        love.graphics.setColor(0,0,0)
        local textW = font:getWidth(button.text)
        local textH = font:getHeight(button.text)
        love.graphics.print(button.text, font, button.x + (self.bw/2) - (textW/2) - 2, button.y + (button_height/2) - (textH/2))

        curY = curY + (self.bh + self.margin)

    end
end

return Menu