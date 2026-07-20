local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')
local Gun = require('hand_items.gun')
local Animation = require('core.animation')
local HandItem = require('hand_items.hand_item')

local Player = {}
Player.__index = Player
setmetatable(Player, Entity)

function Player:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.color = Color.green

    obj.items = {
        [1] = Gun:newUSP(),
        [2] = Gun:newAk47(),
        [3] = Gun:newM4A1(),
        [4] = Gun:newShotgun(),
        [5] = HandItem:newKnife(),
        [6] = HandItem:newGrenade()
    }
    obj.itemIndex = 1

    obj.maxHealth = 100 -- TUNE
    obj.health = obj.maxHealth

    obj.speed = 90
    obj.leftReleased = true

    obj.animState = 'idle'
    obj.animRun = Animation:new(Assets.quads.player, 2, 4, 0.1)

    setmetatable(obj, Player)
    return obj
end

function Player:update(dt, world)

    -- MOVEMENT
    local left = love.keyboard.isDown('a') and 1 or 0
    local right = love.keyboard.isDown('d') and 1 or 0
    local down = love.keyboard.isDown('s') and 1 or 0
    local up = love.keyboard.isDown('w') and 1 or 0

    local moveY = down - up
    local moveX = right - left

    -- walk speed depends on held item
    local speed = self.items[self.itemIndex].walkSpeed or self.speed
    self.x = self.x + (moveX * speed * dt)
    self.y = self.y + (moveY * speed * dt)

    -- Change imtem in hand
    for i = 1, #self.items do
        self.itemIndex = love.keyboard.isDown(tostring(i)) and i or self.itemIndex
    end

    -- INTERACTIONS
    local leftPressed = love.mouse.isDown(1)

    if leftPressed and (self.itemIndex == 1 or self.itemIndex == 2 or self.itemIndex == 3 or self.itemIndex == 4) then
        self.items[self.itemIndex]:fire(self.leftReleased)
    end

    self.leftReleased = not leftPressed
    
    -- Drop item

    -- Pick item?

    -- Open Door?

    -- Push crate

    -- ANIMATIONS
    if moveX == 0 and moveY == 0 then
        self.animRun:restart()
        self.animState = 'idle'
    elseif moveX ~= 0 or moveY ~= 0 then
        self.animRun:update(dt)
        self.animState = 'running'
    end

    -- ITEMS
    local mx, my = love.mouse.getPosition()
    mx, my = mx / SCALE, my / SCALE

    local camX = self.x - SCREENWIDTH/2/SCALE + 32/2
    local camY = self.y - SCREENHEIGHT/2/SCALE + 32/2

    local worldMx = mx + camX
    local worldMy = my + camY

    self.items[self.itemIndex]:update(dt, self.x, self.y, worldMx, worldMy)

end


function Player:draw()
    local facingLeft = love.mouse.getX()/SCALE < ((SCREENWIDTH/2 - self.width/2) / SCALE) + 6

    if self.animState == 'idle' then
        love.graphics.draw(
            Assets.spritesheet, Assets.quads.player[1],
            math.floor(self.x) + (facingLeft and self.width or 0), math.floor(self.y),
            0,
            facingLeft and -1 or 1, 1,
            0, 0
        )
    elseif self.animState == 'running' then
        self.animRun:draw(
            math.floor(self.x) + (facingLeft and self.width or 0), math.floor(self.y),
            0,
            facingLeft and -1 or 1, 1,
            0, 0
        )
    end

    self.items[self.itemIndex]:draw(facingLeft)
end

function Player:drawHud()
    self.items[self.itemIndex]:drawHud()

    love.graphics.print('HP: '..math.max(0, math.floor(self.health)), 20, 50)
end

return Player