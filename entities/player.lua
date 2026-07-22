local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')
local Gun = require('hand_items.gun')
local Animation = require('core.animation')
local HandItem = require('hand_items.hand_item')
local ThrownGrenade = require('entities.thrown_grenade')
local Hotbar = require('ui.hotbar')
local Chat = require('ui.chat')

local Player = {}
Player.__index = Player
setmetatable(Player, Entity)

function Player:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.color = Color.green

    -- Fixed 5 slots: [1] gun A, [2] gun B, [3] knife, [4] grenades, [5] med kit.
    -- Slots 2 and 5 start empty; the slot-4 HandItem is the permanent held
    -- representation, obj.grenades is the actual count.
    obj.items = {
        [1] = Gun:newUSP(),
        [3] = HandItem:newKnife(),
        [4] = HandItem:newGrenade(),
    }
    obj.itemIndex = 1
    obj.lastGunSlot = 1
    obj.grenades = 0

    obj.maxHealth = TUNE.player.maxHealth
    obj.health = obj.maxHealth
    obj.radius = TUNE.player.bodyRadius -- circle vs zombies, smaller than the sprite
    obj.flashTimer = 0                  -- white flash when hit
    obj.hitboxColor = {0, 1, 1} -- cyan: stands out over the sprite

    obj.speed = TUNE.player.baseSpeed
    obj.money = TUNE.player.startMoney
    obj.isPlayer = true
    obj.lastGroundX, obj.lastGroundY = x, y
    obj.leftReleased = true
    obj.rReleased = true
    obj.eReleased = true

    obj.falling = false
    obj.fallTimer = 0
    obj.invulnTimer = 0
    obj.lockedInputs = {} -- buttons held when falling: dead until released

    obj.animState = 'idle'
    obj.animRun = Animation:new(Assets.quads.player, 2, 4, 0.1)

    setmetatable(obj, Player)
    return obj
end

-- Slots 1/2 need a gun in them, 4 needs grenades left, 5 needs a med kit.
-- Knife (3) is the permanent fallback and is always valid.
function Player:slotValid(i)
    if i == 3 then return true end
    if i == 4 then return self.grenades > 0 end
    return self.items[i] ~= nil
end

function Player:selectSlot(i)
    if i == self.itemIndex or not self:slotValid(i) then return end

    local outgoing = self.items[self.itemIndex]
    if outgoing and outgoing.isGun then
        outgoing:cancelReload()
    end
    self.itemIndex = i
    if i == 1 or i == 2 then self.lastGunSlot = i end

    -- switching to an empty gun starts its reload right away
    local newItem = self.items[i]
    if newItem.isGun and newItem.curClip <= 0 then
        newItem:reload()
    end
end

function Player:update(dt, world)

    -- FALLING INTO A HOLE: no input until back on ground
    if self.falling then
        self.fallTimer = self.fallTimer + dt
        if self.fallTimer >= TUNE.player.fallTime then
            self.falling = false
            if not self.godMode then
                self.health = self.health - TUNE.tiles.holeDamage
            end
            self.x, self.y = self.lastGroundX, self.lastGroundY
            self.vx, self.vy = 0, 0
            self.invulnTimer = TUNE.player.holeInvulnTime

            -- whatever was held going in must be released to work again
            self.lockedInputs = {}
            for _, k in ipairs({'w', 'a', 's', 'd'}) do
                if love.keyboard.isDown(k) then self.lockedInputs[k] = true end
            end
            if love.mouse.isDown(1) then self.lockedInputs.mouse1 = true end
        end
        return
    end

    if self.invulnTimer > 0 then
        self.invulnTimer = self.invulnTimer - dt
    end
    if self.flashTimer > 0 then
        self.flashTimer = self.flashTimer - dt
    end

    -- locked buttons free up once released
    for k in pairs(self.lockedInputs) do
        local held = (k == 'mouse1') and love.mouse.isDown(1) or love.keyboard.isDown(k)
        if not held then self.lockedInputs[k] = nil end
    end

    -- while the chat is open every gameplay input is dead (world keeps running)
    local typing = Chat.open
    local function keyDown(k)
        return not typing and love.keyboard.isDown(k) and not self.lockedInputs[k]
    end

    -- MOVEMENT
    local left = keyDown('a') and 1 or 0
    local right = keyDown('d') and 1 or 0
    local down = keyDown('s') and 1 or 0
    local up = keyDown('w') and 1 or 0

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

    -- Change item in hand (hotbar slots 1-5)
    for i = 1, 5 do
        if not typing and love.keyboard.isDown(tostring(i)) then
            self:selectSlot(i)
        end
    end

    -- mouse in world coords; the camera is clamped at map edges, so use it
    -- instead of assuming the player is centered on screen
    local mx, my = love.mouse.getPosition()
    mx, my = mx / SCALE, my / SCALE
    local worldMx = mx + world.camX
    local worldMy = my + world.camY

    -- INTERACTIONS
    local leftPressed = not typing and love.mouse.isDown(1)
        and not self.lockedInputs.mouse1
    local heldItem = self.items[self.itemIndex]

    if leftPressed and heldItem.isGun then
        heldItem:fire(self.leftReleased)
    elseif leftPressed and self.leftReleased and heldItem.isKnife then
        -- swing at the mouse; small lunge makes it aggressive (and risky)
        local pcx, pcy = self:getCenter()
        local aim = math.atan2(worldMy - pcy, worldMx - pcx)
        if heldItem:swing(aim, self, world) then
            self.vx = self.vx + math.cos(aim) * TUNE.knife.lungeSpeed
            self.vy = self.vy + math.sin(aim) * TUNE.knife.lungeSpeed
        end
    elseif leftPressed and self.leftReleased
        and heldItem.isThrowable and self.grenades > 0 then
        local cx, cy = self:getCenter()
        world:addEntity(ThrownGrenade:new(cx, cy, worldMx, worldMy))
        self.grenades = self.grenades - 1
        if self.grenades <= 0 then self:selectSlot(3) end
    elseif leftPressed and self.leftReleased and heldItem.isHealthPack
        and self.health < self.maxHealth then
        self.health = math.min(self.maxHealth, self.health + TUNE.healthpack.healAmount)
        self.items[5] = nil
        self:selectSlot(3)
    end

    self.leftReleased = not leftPressed

    -- Reload
    local rPressed = not typing and love.keyboard.isDown('r')
    if rPressed and self.rReleased and heldItem.isGun then
        heldItem:reload()
    end
    self.rReleased = not rPressed

    -- E interactions: chest > dropped gun > door when touching several
    self.touchingChest = world:getTouchingChest(self)
    self.touchingDroppedGun = (not self.touchingChest)
        and world:getTouchingDroppedGun(self) or nil
    self.touchingDoor = (not self.touchingChest and not self.touchingDroppedGun)
        and world:getTouchingDoor(self) or nil
    local ePressed = not typing and love.keyboard.isDown('e')
    if ePressed and self.eReleased then
        if self.touchingChest then
            self.touchingChest:interact(self, world)
        elseif self.touchingDroppedGun then
            local dg = self.touchingDroppedGun
            local old = self:giveGun(dg.gun)
            dg.toRemove = true
            self.touchingDroppedGun = nil
            if old then -- full slots: swap, old gun stays on the ground
                local DroppedGun = require('entities.dropped_gun')
                world:addEntity(DroppedGun:new(dg.x, dg.y, old))
            end
        elseif self.touchingDoor and self.money >= self.touchingDoor.price then
            self.money = self.money - self.touchingDoor.price
            world:openDoor(self.touchingDoor)
            self.touchingDoor = nil
        end
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
    self.facingLeft = worldMx < self.x + self.width/2

    self.items[self.itemIndex]:update(dt, self.x, self.y, worldMx, worldMy)

end

-- Sprites can't be whitened with a color tint (tints multiply), so the hit
-- flash swaps in a shader that mixes the texel toward pure white
local whiteShader
local function getWhiteShader()
    whiteShader = whiteShader or love.graphics.newShader([[
        extern float amount;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 p = Texel(tex, tc) * color;
            return vec4(mix(p.rgb, vec3(1.0), amount), p.a);
        }
    ]])
    return whiteShader
end

-- Falling in a hole: fall anim, then respawn at last ground tile (see update)
function Player:onFellInHole(world)
    if self.falling or self.invulnTimer > 0 then return end
    self.falling = true
    self.fallTimer = 0
    self.vx, self.vy = 0, 0
end


function Player:draw()
    local facingLeft = self.facingLeft

    -- falling: sprite shrinks into the hole
    if self.falling then
        local s = math.max(0, 1 - self.fallTimer / TUNE.player.fallTime)
        local cx, cy = self:getCenter()
        love.graphics.draw(
            Assets.spritesheet, Assets.quads.player[1],
            math.floor(cx), math.floor(cy),
            self.fallTimer * 6, -- spins as it goes down
            s * (facingLeft and -1 or 1), s,
            self.width/2, self.height/2
        )
        return
    end

    -- invincible: blink (skip draw on alternating intervals)
    if self.invulnTimer > 0
        and math.floor(self.invulnTimer / TUNE.player.blinkInterval) % 2 == 0 then
        return
    end

    local flashing = self.flashTimer > 0
    if flashing then
        local sh = getWhiteShader()
        sh:send('amount', 1)
        love.graphics.setShader(sh)
    end

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

    if flashing then
        love.graphics.setShader()
    end
end

function Player:drawHud()
    self.items[self.itemIndex]:drawHud()

    love.graphics.print(T('hud.hp', math.max(0, math.floor(self.health))), 20, 50)
    love.graphics.print(T('hud.money', math.floor(self.money)), 20, 80)

    Hotbar.draw(self)

    local prompt, red
    if self.touchingChest then
        local c = self.touchingChest
        if c.state == 'idle' then
            if self.money >= TUNE.chest.cost then
                prompt = T('hud.chest_spin', TUNE.chest.cost)
            else
                prompt = T('hud.chest_poor', TUNE.chest.cost)
                red = true
            end
        elseif c.state == 'offering' then
            prompt = T('hud.chest_take', c.result.name, math.ceil(c.takeTimer))
        end
    elseif self.touchingDroppedGun then
        prompt = T('hud.gun_pickup', self.touchingDroppedGun.gun.name)
    elseif self.touchingDoor then
        local d = self.touchingDoor
        prompt = T('hud.door_open', d.price)
        if self.money < d.price then
            prompt = T('hud.door_locked', d.price)
            red = true
        end
    end

    if prompt then
        if red then love.graphics.setColor(Color.red()) end
        love.graphics.print(prompt,
            SCREENWIDTH/2 - font:getWidth(prompt)/2, SCREENHEIGHT - 120)
        love.graphics.setColor(Color.white())
    end
end

-- Put a gun in the hotbar and hold it. Target slot: empty gun slot first
-- (2 then 1), else the gun in hand, else the last gun slot held.
-- Returns the gun that got replaced (nil if the slot was empty).
function Player:giveGun(gun)
    local target
    if not self.items[2] then target = 2
    elseif not self.items[1] then target = 1
    elseif self.itemIndex == 1 or self.itemIndex == 2 then target = self.itemIndex
    else target = self.lastGunSlot end

    local old = self.items[target]
    self.items[target] = gun
    self.itemIndex = target
    self.lastGunSlot = target
    return old
end

-- Run-save data: health, money, held slot, gun slots (by id + ammo),
-- grenade count and med kit flag
function Player:serialize()
    local gunSlots = {}
    for i = 1, 2 do
        local gun = self.items[i]
        if gun then
            gunSlots[i] = {
                id = gun.id,
                curClip = gun.curClip,
                bulletsLeft = gun.bulletsLeft,
            }
        end
    end
    return {
        health = self.health,
        money = self.money,
        itemIndex = self.itemIndex,
        lastGunSlot = self.lastGunSlot,
        grenades = self.grenades,
        hasHealthPack = self.items[5] ~= nil,
        gunSlots = gunSlots,
    }
end

function Player:restore(data)
    self.health = data.health or self.health
    self.money = data.money or self.money

    -- pre-hotbar saves only carry health/money; keep the default loadout
    if not data.gunSlots then return end

    for i = 1, 2 do
        local g = data.gunSlots[i]
        local gun = g and Gun.newById(g.id)
        if gun then
            gun.curClip = g.curClip or gun.curClip
            gun.bulletsLeft = g.bulletsLeft or gun.bulletsLeft
        end
        self.items[i] = gun or nil
    end
    self.items[5] = data.hasHealthPack and HandItem:newHealthPack() or nil
    self.grenades = data.grenades or 0
    self.lastGunSlot = data.lastGunSlot or 1

    self.itemIndex = 3 -- knife fallback, then try the saved slot
    local saved = data.itemIndex or 1
    if self:slotValid(saved) then self.itemIndex = saved end
end

return Player