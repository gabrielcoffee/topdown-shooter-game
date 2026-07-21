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

    obj.maxHealth = TUNE.player.maxHealth
    obj.health = obj.maxHealth
    obj.hitboxColor = {0, 1, 1} -- cyan: stands out over the sprite

    obj.speed = TUNE.player.baseSpeed
    obj.money = TUNE.player.startMoney
    obj.isPlayer = true
    obj.lastGroundX, obj.lastGroundY = x, y
    obj.leftReleased = true
    obj.rReleased = true
    obj.eReleased = true

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

    -- normalize so diagonal isn't faster
    if moveX ~= 0 and moveY ~= 0 then
        local inv = 1 / math.sqrt(2)
        moveX, moveY = moveX * inv, moveY * inv
    end

    -- walk speed depends on held item; accel/decel + tile collision
    self.maxSpeed = self.items[self.itemIndex].walkSpeed or self.speed
    self:accelToward(dt, moveX, moveY, world)
    self:moveAndCollide(dt, world)

    -- spikes / water / mud / hole
    self:applyTileEffects(dt, world)

    -- Change imtem in hand
    for i = 1, #self.items do
        if love.keyboard.isDown(tostring(i)) and i ~= self.itemIndex then
            if self.items[self.itemIndex].isGun then
                self.items[self.itemIndex]:cancelReload()
            end
            self.itemIndex = i
        end
    end

    -- INTERACTIONS
    local leftPressed = love.mouse.isDown(1)
    local heldItem = self.items[self.itemIndex]

    if leftPressed and heldItem.isGun then
        heldItem:fire(self.leftReleased)
    end

    self.leftReleased = not leftPressed

    -- Reload
    local rPressed = love.keyboard.isDown('r')
    if rPressed and self.rReleased and heldItem.isGun then
        heldItem:reload()
    end
    self.rReleased = not rPressed
    
    -- Drop item

    -- Pick item?

    -- Open Door (buy with money, E key)
    self.touchingDoor = world:getTouchingDoor(self)
    local ePressed = love.keyboard.isDown('e')
    if ePressed and self.eReleased and self.touchingDoor
        and self.money >= self.touchingDoor.price then
        self.money = self.money - self.touchingDoor.price
        world:removeEntity(self.touchingDoor)
        self.touchingDoor = nil
    end
    self.eReleased = not ePressed

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

    -- world's camera is clamped at map edges, so use it instead of
    -- assuming the player is centered on screen
    local worldMx = mx + world.camX
    local worldMy = my + world.camY

    self.facingLeft = worldMx < self.x + self.width/2

    self.items[self.itemIndex]:update(dt, self.x, self.y, worldMx, worldMy)

end

-- Falling in a hole: back to the last ground tile, lose life
function Player:onFellInHole(world)
    self.health = self.health - TUNE.tiles.holeDamage
    self.x, self.y = self.lastGroundX, self.lastGroundY
    self.vx, self.vy = 0, 0
end


function Player:draw()
    local facingLeft = self.facingLeft

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

    love.graphics.print(T('hud.hp', math.max(0, math.floor(self.health))), 20, 50)
    love.graphics.print(T('hud.money', math.floor(self.money)), 20, 80)

    if self.touchingDoor then
        local d = self.touchingDoor
        local txt = T('hud.door_open', d.price)
        if self.money < d.price then
            txt = T('hud.door_locked', d.price)
            love.graphics.setColor(Color.red())
        end
        love.graphics.print(txt, SCREENWIDTH/2 - font:getWidth(txt)/2, SCREENHEIGHT - 60)
        love.graphics.setColor(Color.white())
    end
end

-- Run-save data: health, money, held slot, per-gun ammo
function Player:serialize()
    local guns = {}
    for i, item in ipairs(self.items) do
        if item.isGun then
            guns[i] = { curClip = item.curClip, bulletsLeft = item.bulletsLeft }
        end
    end
    return {
        health = self.health,
        money = self.money,
        itemIndex = self.itemIndex,
        guns = guns,
    }
end

function Player:restore(data)
    self.health = data.health or self.health
    self.money = data.money or self.money
    self.itemIndex = data.itemIndex or self.itemIndex
    for i, g in pairs(data.guns or {}) do
        local item = self.items[i]
        if item and item.isGun then
            item.curClip = g.curClip or item.curClip
            item.bulletsLeft = g.bulletsLeft or item.bulletsLeft
        end
    end
end

return Player