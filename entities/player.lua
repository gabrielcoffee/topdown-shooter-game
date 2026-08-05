local Entity = require('entities.entity')
local Color = require('core.color')
local Assets = require('core.assets')
local Gun = require('hand_items.gun')
local Animation = require('core.animation')
local HandItem = require('hand_items.hand_item')
local ThrownGrenade = require('entities.thrown_grenade')
local Hotbar = require('ui.hotbar')
local Chat = require('ui.chat')
local Audio = require('core.audio')

local Player = {}
Player.__index = Player
setmetatable(Player, Entity)

function Player:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.color = Color.green

    -- Fixed 5 slots: [1] gun A, [2] gun B, [3] knife, [4] grenades, [5] med kit.
    -- Slot 2 starts empty; the slot-4 and slot-5 HandItems are permanent held
    -- representations, obj.grenades / obj.medkits are the actual counts.
    obj.items = {
        [1] = Gun:newUSP(),
        [3] = HandItem:newKnife(),
        [4] = HandItem:newGrenade(),
        [5] = HandItem:newHealthPack(),
    }
    obj.itemIndex = 1
    obj.lastGunSlot = 1
    obj.lastSlot = 3      -- slot the Q quick-knife swaps back to
    obj.grenades = 0
    obj.molotovs = 0
    obj.medkits = 0
    obj.throwableType = 'grenade' -- which throwable slot 4 shows ('grenade'|'molotov')

    obj.maxHealth = TUNE.player.maxHealth
    obj.health = obj.maxHealth
    obj.radius = TUNE.player.bodyRadius -- circle vs zombies, smaller than the sprite
    -- 16x16 AABB in the lower half of the 32px sprite (tiles/obstacles)
    obj.colOX, obj.colOY = TUNE.player.colOffsetX, TUNE.player.colOffsetY
    obj.colW, obj.colH = TUNE.player.colSize, TUNE.player.colSize
    obj.flashTimer = 0                  -- white flash when hit
    obj.dustTimer = 0                   -- next movement dust puff
    obj.hitboxColor = {0, 1, 1} -- cyan: stands out over the sprite

    obj.speed = TUNE.player.baseSpeed
    obj.money = TUNE.player.startMoney
    obj.earnedTotal = 0 -- lifetime run earnings = the score (spending doesn't shrink it)
    obj.isPlayer = true
    obj.lastGroundX, obj.lastGroundY = x, y
    obj.leftReleased = true
    obj.rReleased = true
    obj.eReleased = true
    obj.gReleased = true
    obj.qReleased = true

    obj.running = false   -- SPRINT state: shift held + moving, no aim/shoot
    obj.flying = false    -- god mode + shift: noclip fly instead of sprint

    obj.falling = false
    obj.fallTimer = 0
    obj.invulnTimer = 0
    obj.lockedInputs = {} -- buttons held when falling: dead until released
    -- the click that started this run (menu / retry button) can still be held
    -- when the world spawns — it must not become shot #1
    if love.mouse.isDown(1) then obj.lockedInputs.mouse1 = true end
    obj.slotHeld = {}     -- per-slot key state, so holding a number can't re-select
    obj.switchTimer = 0   -- deploy lockout after a weapon swap (blocks quick-switch)
    obj.throwTimer = 0    -- secs until the next throw is allowed (stacked grenades)
    obj.healTimer = 0     -- secs until the next med kit use is allowed

    obj.animState = 'idle'
    obj.animRun = Animation:new(Assets.quads.player, 2, 4, 0.1)

    setmetatable(obj, Player)
    return obj
end

-- Slots 1/2 need a gun in them, 4 needs any throwable left, 5 needs a med
-- kit. Knife (3) is the permanent fallback and is always valid.
function Player:slotValid(i)
    if i == 3 then return true end
    if i == 4 then return self.grenades > 0 or self.molotovs > 0 end
    if i == 5 then return self.medkits > 0 end
    return self.items[i] ~= nil
end

-- Count of the throwable currently out in slot 4
function Player:throwableCount()
    return self.throwableType == 'molotov' and self.molotovs or self.grenades
end

-- Slot 4 is one shared pool: grenades + molotovs vs TUNE.throwables.maxCarry
function Player:throwableSpace()
    return TUNE.throwables.maxCarry - (self.grenades + self.molotovs)
end

-- Room for one more of this kind? Shared pool AND the per-kind cap must agree
-- (4 total, never perKindMax+1 of one kind). 'molotov' counts molotovs,
-- anything else ('he'/'grenade') counts grenades.
function Player:canAddThrowable(kind)
    if self:throwableSpace() <= 0 then return false end
    local n = kind == 'molotov' and self.molotovs or self.grenades
    return n < TUNE.throwables.perKindMax
end

-- +1 of a kind if it fits. Returns true when it landed.
function Player:addThrowable(kind)
    if not self:canAddThrowable(kind) then return false end
    if kind == 'molotov' then self.molotovs = self.molotovs + 1
    else self.grenades = self.grenades + 1 end
    return true
end

-- +1 med kit if slot 5 has room. Returns true when it landed.
function Player:addMedkit()
    if self.medkits >= TUNE.healthpack.maxCarry then return false end
    self.medkits = self.medkits + 1
    return true
end

local function throwableItem(kind)
    return HandItem:newGrenade(kind == 'molotov' and 'molotov' or nil)
end

-- Pressing 4 while slot 4 is already out flips grenade <-> molotov
-- (only onto a type with ammo left)
function Player:cycleThrowable()
    local other = self.throwableType == 'grenade' and 'molotov' or 'grenade'
    local count = other == 'molotov' and self.molotovs or self.grenades
    if count <= 0 then return end
    self.throwableType = other
    self.items[4] = throwableItem(other)
    Audio.play('grenade_pull', 0.7) -- CS-style pin pull when the grenade comes out
end

-- Keep slot 4 pointing at a loaded throwable: if the current type ran dry
-- and the other has ammo, flip over (throwing the last one, chest rewards)
function Player:syncThrowable()
    if self:throwableCount() > 0 then return end
    local other = self.throwableType == 'grenade' and 'molotov' or 'grenade'
    local count = other == 'molotov' and self.molotovs or self.grenades
    if count > 0 then
        self.throwableType = other
        self.items[4] = throwableItem(other)
    end
end

-- fast = quick-knife swap (Q), which deploys quicker than a normal swap
function Player:selectSlot(i, fast)
    if i == self.itemIndex or not self:slotValid(i) then return end

    local outgoing = self.items[self.itemIndex]
    if outgoing and outgoing.isGun then
        outgoing:cancelReload()
        outgoing:cutPick() -- swap cuts the pick clack mid-play
    end
    self.lastSlot = self.itemIndex
    self.itemIndex = i
    -- deploy: can't act instantly. Guns bring their own draw time (pistol
    -- fast, shotgun slow); quick-knife stays the fastest swap in the kit.
    local newItem = self.items[i]
    if fast then
        self.switchTimer = TUNE.player.knifeSwapDelay
    elseif newItem.isGun and newItem.drawTime then
        self.switchTimer = newItem.drawTime
    else
        self.switchTimer = TUNE.player.switchDelay
    end
    if i == 1 or i == 2 then self.lastGunSlot = i end

    -- deploy visual: guns replay their pickup animation on the way up
    if newItem.isGun then newItem:startDraw() end

    -- CS-style deploy sound for whatever lands in hand. An empty gun skips
    -- straight into its reload sound (below) — its pick plays when that ends.
    if newItem.isGun then
        local willReload = newItem.curClip <= 0 and newItem.bulletsLeft > 0
        if willReload then
            -- reload sound carries the deploy
        elseif newItem.pickSfx then
            newItem:playPick()
        else
            Audio.play('gun_draw', 0.7) -- shotgun keeps the generic clack
        end
    elseif newItem.isKnife then
        Audio.play('knife_swing', 0.5)
    elseif newItem.isThrowable then
        Audio.play('grenade_pull', 0.7) -- CS-style pin pull when the grenade comes out
    end

    -- switching to an empty gun starts its reload right away
    if newItem.isGun and newItem.curClip <= 0 then
        newItem:reload()
    end
end

-- Q (or 3 while the knife is already out): flick to the knife and, pressed
-- again, straight back to whatever was in hand before — gun, grenade or med
-- kit. CoD quick-melee feel: shorter deploy than a normal swap both ways.
function Player:quickKnife()
    if self.itemIndex ~= 3 then
        self:selectSlot(3, true)
        return
    end
    local back = self.lastSlot
    if back == 3 or not self:slotValid(back) then
        -- what we came from is gone (gun dropped, last grenade thrown):
        -- fall back to a gun, then anything else usable
        back = nil
        for _, i in ipairs({ self.lastGunSlot, 1, 2, 4, 5 }) do
            if i ~= 3 and self:slotValid(i) then back = i break end
        end
    end
    if back then self:selectSlot(back, true) end
end

-- Mouse wheel: step to the next/prev valid slot, wrapping (Minecraft-style)
function Player:scrollSlot(dir)
    local i = self.itemIndex
    for _ = 1, 4 do
        i = (i - 1 + dir) % 5 + 1
        if self:slotValid(i) then
            self:selectSlot(i)
            return
        end
    end
end

function Player:update(dt, world)

    local pop = self.moneyPopup
    if pop then
        pop.t = pop.t + dt
        if pop.t >= TUNE.hud.popupTime then self.moneyPopup = nil end
    end
    local dpop = self.damagePopup
    if dpop then
        dpop.t = dpop.t + dt
        if dpop.t >= TUNE.hud.popupTime then self.damagePopup = nil end
    end

    -- any health drop (zombies, fire, spikes, holes) = red vignette + grunt.
    -- Cooldown so per-frame damage (spikes) can't machine-gun the cue.
    self.hurtCue = math.max(0, (self.hurtCue or 0) - dt)
    if self.lastHealth and self.health < self.lastHealth then
        -- the killing drop always cues — death must never go silent just
        -- because a hit half a second earlier used up the cooldown
        if self.hurtCue <= 0 or self.health <= 0 then
            require('ui.fx').damageVignette()
            if self.health <= 0 then
                Audio.play('player_dead', 0.9) -- death: only this, no damage grunt
            elseif love.math.random() < TUNE.audio.motherFuckerChance then
                Audio.play('mother_fucker', 0.9) -- rare easter egg on a hit
            else
                Audio.play('player_damage', 0.9)
            end
            self.hurtCue = TUNE.player.hurtCueCooldown
        end
        -- red "-n" over the HP readout. Per-frame damage (spikes, fire) adds
        -- into the live popup instead of spamming one popup per frame
        local lost = self.lastHealth - self.health
        if dpop then
            dpop.amount, dpop.t = dpop.amount + lost, 0
        else
            self.damagePopup = { amount = lost, t = 0 }
        end
    end
    self.lastHealth = self.health

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
    if self.switchTimer > 0 then
        self.switchTimer = self.switchTimer - dt
    end
    -- per-item use cooldowns: stacked throwables / med kits can't be spammed
    if self.throwTimer > 0 then
        self.throwTimer = self.throwTimer - dt
        -- cooldown over with another one in the bag: pin pull, CS-style, so
        -- the ear knows the next grenade is live
        if self.throwTimer <= 0 and self.itemIndex == 4 and self:throwableCount() > 0 then
            Audio.play('grenade_pull', 0.7)
        end
    end
    if self.healTimer > 0 then self.healTimer = self.healTimer - dt end

    -- locked buttons free up once released (no and/or here: false isDown(1)
    -- would fall through into keyboard.isDown('mouse1') and crash)
    for k in pairs(self.lockedInputs) do
        local held
        if k == 'mouse1' then held = love.mouse.isDown(1)
        else held = love.keyboard.isDown(k) end
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

    -- SHIFT = SPRINT: shift held + moving, always — no lockout after firing.
    -- While sprinting every item action (shoot/knife/throw/heal/reload) is
    -- blocked; only moving and switching what's in hand work.
    local shiftHeld = keyDown('lshift') or keyDown('rshift')
    self.running = shiftHeld and (moveX ~= 0 or moveY ~= 0)
    -- god mode turns the sprint into a fly: through walls, over tiles, no dust
    self.flying = (self.godMode and self.running) or false
    self.maxSpeed = self.speed * (self.flying and TUNE.dev.flySpeedMult
        or (self.running and TUNE.player.runSpeedMult or 1))
    self:accelToward(dt, moveX, moveY, world, self.flying)
    if self.flying then
        -- noclip: only the map edge clamps; stopping lands (and the normal
        -- collision pass next frame snaps out of anything solid)
        self.x = math.max(0, math.min(self.x + self.vx * dt, world.mapW - self.width))
        self.y = math.max(0, math.min(self.y + self.vy * dt, world.mapH - self.height))
    else
        self:moveAndCollide(dt, world)
    end

    -- CS-style movement accuracy: fully accurate below the floor (34% of run
    -- speed in CS), inaccuracy ramps linearly up to the ceiling (95%). Fast
    -- decel means stopping snaps back under the floor — counter-strafe feel.
    local spd = math.sqrt(self.vx * self.vx + self.vy * self.vy)
    local base = TUNE.player.baseSpeed
    local floor = base * TUNE.movement.spreadSpeedFloor
    local ceil = base * TUNE.movement.spreadSpeedCeil
    self.moveFactor = math.max(0, math.min(1, (spd - floor) / (ceil - floor)))

    -- spikes / water / mud / hole — flying passes over all of it
    if not self.flying then self:applyTileEffects(dt, world) end

    -- dust puffs around the feet while actually moving (lunge/shove included);
    -- walking kicks up a fraction of the sprint amount
    self.dustTimer = self.dustTimer - dt
    if self.dustTimer <= 0 and not self.flying
        and self.vx*self.vx + self.vy*self.vy > 400 then
        self.dustTimer = TUNE.fx.dustInterval
        local mult = self.running and 1 or TUNE.fx.dustWalkMult
        local count = math.max(1, math.floor(TUNE.fx.dustCount * mult + 0.5))
        world.vfx:footDust(self.x + self.width/2, self.y + self.height - 4, count)
    end

    -- footsteps: cadence follows actual speed, sound follows the tile material.
    -- Cadence factor clamped — at low speed the old open-ended formula pushed
    -- steps seconds apart, which read as "footsteps randomly missing"
    self.stepTimer = (self.stepTimer or 0) - dt
    local spd2 = self.vx*self.vx + self.vy*self.vy
    if self.stepTimer <= 0 and spd2 > 400 and not self.flying then
        local A = TUNE.audio
        local slower = math.min(TUNE.player.baseSpeed / math.sqrt(spd2), A.stepMaxStretch)
        self.stepTimer = A.stepInterval * slower
        local cx, cy = self:getCenter()
        Audio.playAt(world.map:surfaceAt(cx, cy), cx, cy, A.stepGain, A.pitchJitter, world)
    end

    -- a throwable type that ran dry flips slot 4 to the loaded one
    self:syncThrowable()

    -- Change item in hand (hotbar slots 1-5); edge-gated so a held key can't
    -- re-select every frame (deploy-sound spam + reload churn)
    for i = 1, 5 do
        local down = not typing and love.keyboard.isDown(tostring(i))
        if down and not self.slotHeld[i] then
            if i == 4 and self.itemIndex == 4 then
                self:cycleThrowable() -- 4 again = swap grenade/molotov
            elseif i == 3 then
                self:quickKnife()     -- 3 again = back to the last item
            else
                self:selectSlot(i)
            end
        end
        self.slotHeld[i] = down
    end

    -- Q: quick-knife toggle (knife <-> whatever was in hand)
    local qPressed = not typing and love.keyboard.isDown('q')
    if qPressed and self.qReleased then self:quickKnife() end
    self.qReleased = not qPressed

    -- mouse in world coords; the camera is clamped at map edges, so use it
    -- instead of assuming the player is centered on screen. getPosition is
    -- window-space — map through the scaler to logical canvas space first.
    local mx, my = require('ui.screen').mouse()
    mx, my = mx / SCALE, my / SCALE
    local worldMx = mx + world.camX
    local worldMy = my + world.camY

    -- INTERACTIONS
    local leftPressed = not typing and love.mouse.isDown(1)
        and not self.lockedInputs.mouse1
    local heldItem = self.items[self.itemIndex]

    -- sprinting cuts a reload dead. An EMPTY gun re-reloads by itself the
    -- moment the sprint ends (nothing to shoot otherwise); a manual top-up
    -- reload just dies and the player re-presses R.
    if self.running and heldItem.isGun and heldItem.reloading then
        heldItem:cancelReload()
    end
    if not self.running and self.wasRunning and heldItem.isGun
        and heldItem.curClip <= 0 then
        heldItem:reload() -- self-checks reserve ammo
    end
    self.wasRunning = self.running

    -- deploy lockout: right after a swap the new item can't act yet, so
    -- alternating two guns can't beat either gun's own fire rate. Sprinting
    -- blocks every item action — release shift (or stop) to act.
    local canAct = self.switchTimer <= 0 and not self.running

    -- fresh out of a sprint the item can still hold the run-direction angle
    -- (aim updates later in the frame): snap to the cursor so the first shot
    -- goes where the player is pointing
    if leftPressed and not self.running and heldItem.isGun then
        local pcx, pcy = self:getCenter()
        heldItem.angle = math.atan2(worldMy - pcy, worldMx - pcx)
    end

    if leftPressed and canAct and heldItem.isGun then
        heldItem:fire(self.leftReleased)
    elseif leftPressed and canAct and self.leftReleased and heldItem.isKnife then
        -- swing at the mouse; small lunge makes it aggressive (and risky)
        local pcx, pcy = self:getCenter()
        local aim = math.atan2(worldMy - pcy, worldMx - pcx)
        if heldItem:swing(aim, self, world) then
            self.vx = self.vx + math.cos(aim) * TUNE.knife.lungeSpeed
            self.vy = self.vy + math.sin(aim) * TUNE.knife.lungeSpeed
        end
    elseif leftPressed and canAct and self.leftReleased
        and heldItem.isThrowable and self:throwableCount() > 0
        and self.throwTimer <= 0 then
        local cx, cy = self:getCenter()
        -- lands exactly where the targeting preview says (cursor clamped to maxRange)
        local tx, ty = require('ui.grenade_aim').target(world)
        if self.throwableType == 'molotov' then
            world:addEntity(require('entities.thrown_molotov'):new(cx, cy, tx, ty))
            self.molotovs = self.molotovs - 1
        else
            world:addEntity(ThrownGrenade:new(cx, cy, tx, ty))
            self.grenades = self.grenades - 1
        end
        Audio.playAt('grenade_throw', cx, cy, 0.8, TUNE.audio.pitchJitter, world)
        self.throwTimer = TUNE.throwables.useDelay -- a full pool can't be dumped at once
        self:syncThrowable() -- last of this type: flip to the other if loaded
        if not self:slotValid(4) then self:selectSlot(3) end
    elseif leftPressed and canAct and self.leftReleased and heldItem.isHealthPack then
        self:useMedkit(world)
    end

    self.leftReleased = not leftPressed

    -- Reload
    local rPressed = not typing and love.keyboard.isDown('r')
    if rPressed and self.rReleased and heldItem.isGun and not self.running then
        heldItem:reload()
    end
    self.rReleased = not rPressed

    -- E interactions: chest > dropped gun > wall buy > door when touching several
    self.touchingChest = world:getTouchingChest(self)
    self.touchingDroppedGun = (not self.touchingChest)
        and world:getTouchingDroppedGun(self) or nil
    self.touchingGunWall = (not self.touchingChest and not self.touchingDroppedGun)
        and world:getTouchingGunWall(self) or nil
    self.touchingDoor = (not self.touchingChest and not self.touchingDroppedGun
        and not self.touchingGunWall) and world:getTouchingDoor(self) or nil
    local ePressed = not typing and love.keyboard.isDown('e')
    if ePressed and self.eReleased then
        if self.touchingChest then
            self.touchingChest:interact(self, world)
        elseif self.touchingGunWall then
            self.touchingGunWall:interact(self, world)
        elseif self.touchingDroppedGun then
            local dg = self.touchingDroppedGun
            local old = self:giveGun(dg.gun)
            dg.toRemove = true
            self.touchingDroppedGun = nil
            if old then -- full slots: swap, old gun stays on the ground
                local DroppedGun = require('entities.dropped_gun')
                world:addEntity(DroppedGun:new(dg.x, dg.y, old))
            end
        elseif self.touchingDoor and self:trySpend(self.touchingDoor.price) then
            world:openDoor(self.touchingDoor)
            self.touchingDoor = nil
        elseif heldItem.isHealthPack and canAct then
            self:useMedkit(world) -- E heals too when nothing else is in reach
        end
    end
    self.eReleased = not ePressed

    -- G drops the gun in hand (it lands in front and expires on the ground)
    local gPressed = not typing and love.keyboard.isDown('g')
    if gPressed and self.gReleased then self:dropHeldGun(world) end
    self.gReleased = not gPressed

    -- ANIMATIONS
    if moveX == 0 and moveY == 0 then
        self.animRun:restart()
        self.animState = 'idle'
    else
        local animMult = self.running and TUNE.player.runAnimMult or 1
        self.animRun:update(dt * animMult)
        self.animState = 'running'
    end

    -- ITEMS
    -- sprinting: the item points along the run direction (you can't aim at the
    -- cursor while running) and facing follows the run; otherwise aim at cursor
    local aimMx, aimMy = worldMx, worldMy
    if self.running then
        local pcx, pcy = self:getCenter()
        aimMx, aimMy = pcx + moveX * 64, pcy + moveY * 64
        if moveX ~= 0 then self.facingLeft = moveX < 0 end
    else
        self.facingLeft = worldMx < self.x + self.width/2
    end

    self.items[self.itemIndex]:update(dt, self.x, self.y, aimMx, aimMy)

    -- holstered guns keep cooling down (fire gate + recoil recovery), so
    -- swapping can't freeze a gun's timers in a favorable state
    for i, item in pairs(self.items) do
        if item.isGun and i ~= self.itemIndex then
            item:tickCooldowns(dt)
        end
    end
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
    self.items[self.itemIndex]:drawHud(self) -- bottom-left: held item + ammo

    -- bottom-right stack: HP on the bottom line, money right above it,
    -- earned "+$n" floating up above both
    local hp = T('hud.hp', math.max(0, math.floor(self.health)))
    local hpX = SCREENWIDTH - 20 - font:getWidth(hp)
    love.graphics.print(hp, hpX, SCREENHEIGHT - 40)

    -- red "-n" left of the HP readout (the money popup owns the space above)
    local dpop = self.damagePopup
    if dpop then
        local k = dpop.t / TUNE.hud.popupTime
        local txt = T('hud.health_loss', math.max(1, math.floor(dpop.amount + 0.5)))
        love.graphics.setColor(1, 0.25, 0.25, 1 - k * k)
        love.graphics.print(txt, hpX - 16 - font:getWidth(txt),
            SCREENHEIGHT - 40 - TUNE.hud.popupRise * k)
        love.graphics.setColor(Color.white())
    end

    local money = T('hud.money', math.floor(self.money))
    love.graphics.print(money, SCREENWIDTH - 20 - font:getWidth(money), SCREENHEIGHT - 70)

    local pop = self.moneyPopup
    if pop then
        local k = pop.t / TUNE.hud.popupTime
        local txt = T('hud.money_gain', math.floor(pop.amount))
        love.graphics.setColor(1, 0.85, 0.3, 1 - k * k)
        love.graphics.print(txt, SCREENWIDTH - 20 - font:getWidth(txt),
            SCREENHEIGHT - 94 - TUNE.hud.popupRise * k)
        love.graphics.setColor(Color.white())
    end

    Hotbar.draw(self)

    local prompt, red
    if self.touchingChest then
        local c = self.touchingChest
        if c.state == 'idle' then
            local cost = c:currentCost() -- fire sale discounts it
            if self.money >= cost then
                prompt = T('hud.chest_spin', cost)
            else
                prompt = T('hud.chest_poor', cost)
                red = true
            end
        elseif c.state == 'offering' then
            -- gun/refill rolls carry a name; item rolls resolve theirs from the
            -- locale by kind, so no roll can ever print as nil
            local name = c.result.name or T('item.' .. c.result.kind)
            prompt = T('hud.chest_take', name, math.ceil(c.takeTimer))
        end
    elseif self.touchingDroppedGun then
        prompt = T('hud.gun_pickup', self.touchingDroppedGun.gun.name)
    elseif self.touchingGunWall then
        local w = self.touchingGunWall
        local name = require('hand_items.gun').names[w.gunId] or w.gunId
        local owned = w:ownedGun(self)
        if owned then
            if owned:ammoFull() then
                prompt = T('hud.wallbuy_full', name)
            elseif self.money >= w.ammoPrice then
                prompt = T('hud.wallbuy_ammo', name, w.ammoPrice)
            else
                prompt = T('hud.wallbuy_poor', name, w.ammoPrice)
                red = true
            end
        elseif self.money >= w.price then
            prompt = T('hud.wallbuy_buy', name, w.price)
        else
            prompt = T('hud.wallbuy_poor', name, w.price)
            red = true
        end
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

-- One med kit down the hatch (left click or E with it in hand): heal, use
-- cooldown, pink puffs rising off the body, heal cue.
function Player:useMedkit(world)
    if self.health >= self.maxHealth or self.medkits <= 0
        or self.healTimer > 0 then return end
    local cx, cy = self:getCenter()
    self.health = math.min(self.maxHealth, self.health + TUNE.healthpack.healAmount)
    self.medkits = self.medkits - 1
    self.healTimer = TUNE.healthpack.useDelay
    world.vfx:healBurst(cx, cy)
    Audio.playAt('medkit_heal', cx, cy, 0.9, TUNE.audio.pitchJitter, world)
    -- one still in the bag: keep it out, otherwise fall back to the knife
    if not self:slotValid(5) then self:selectSlot(3) end
end

-- Cash in, cash out. Every gain funnels through here so the cap holds
-- everywhere (kills, chest, /money, which also takes negatives). Double
-- points multiplies every gain, CoD-style (kills, hits, even the nuke).
function Player:addMoney(n)
    if n > 0 and world and world.buffs and world.buffs.doublepoints > 0 then
        n = n * TUNE.powerups.doubleMult
    end
    local before = self.money
    self.money = math.max(0, math.min(self.money + n, TUNE.player.maxMoney))

    -- actual gain (post-double, post-cap) feeds the floating "+$n". Each
    -- earn shows on its own -- a new one replaces the old, never adds up
    local gained = self.money - before
    if gained > 0 then
        self.earnedTotal = self.earnedTotal + gained
        self.moneyPopup = { amount = gained, t = 0 }
    end
end

-- Every purchase funnels through here (doors, chest, wall buys)
function Player:trySpend(n)
    if self.money < n then return false end
    self.money = self.money - n
    return true
end

-- G: throw the held gun on the ground. Falls back to the other gun slot,
-- else the knife. The dropped gun keeps its ammo and expires on its own.
function Player:dropHeldGun(world)
    local slot = self.itemIndex
    if slot ~= 1 and slot ~= 2 then return end
    local gun = self.items[slot]
    if not gun then return end

    gun:cancelReload()
    require('entities.dropped_gun').dropNear(world, gun, self)
    self.items[slot] = nil

    local other = (slot == 1) and 2 or 1
    self:selectSlot(self.items[other] and other or 3)
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
    if old and old.isGun then
        old:cancelReload()
        old:cutPick() -- the gun leaving the hand takes its sounds with it
    end
    self.items[target] = gun
    self.itemIndex = target
    self.lastGunSlot = target
    -- pickup = a fresh draw: same lockout + pick sound as a swap
    self.switchTimer = gun.drawTime or TUNE.player.switchDelay
    gun:startDraw()
    if gun.id == 'shotgun' then
        gun:pump(false) -- shotgun racks on pickup (SFX + pose, no shell)
    elseif gun.pickSfx then
        gun:playPick()
    else
        Audio.play('gun_draw', 0.7) -- picked up = racked and in hand
    end
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
        x = self.x,
        y = self.y,
        health = self.health,
        money = self.money,
        earnedTotal = self.earnedTotal,
        itemIndex = self.itemIndex,
        lastGunSlot = self.lastGunSlot,
        grenades = self.grenades,
        molotovs = self.molotovs,
        throwableType = self.throwableType,
        medkits = self.medkits,
        gunSlots = gunSlots,
    }
end

function Player:restore(data)
    -- exact spot the run was saved at (old saves: keep the spawn position)
    if data.x and data.y then
        self.x, self.y = data.x, data.y
        self.lastGroundX, self.lastGroundY = data.x, data.y
    end
    self.health = data.health or self.health
    self.money = math.max(0, math.min(data.money or self.money, TUNE.player.maxMoney))
    self.earnedTotal = data.earnedTotal or self.money -- old saves: money is the best guess

    -- pre-hotbar saves only carry health/money; keep the default loadout
    if not data.gunSlots then return end

    for i = 1, 2 do
        local g = data.gunSlots[i]
        local gun = g and Gun.newById(g.id)
        if gun then
            -- clamp to the CURRENT tune values: a save written before a clip
            -- was shrunk in tune.lua must not restore 30 rounds into a 25 mag
            gun.curClip = math.max(0, math.min(g.curClip or gun.curClip, gun.maxClip))
            gun.bulletsLeft = math.max(0, g.bulletsLeft or gun.bulletsLeft)
        end
        self.items[i] = gun or nil
    end
    -- old saves carried a single hasHealthPack flag instead of a count
    self.medkits = math.min(TUNE.healthpack.maxCarry,
        data.medkits or (data.hasHealthPack and 1 or 0))
    self.grenades = data.grenades or 0
    self.molotovs = data.molotovs or 0
    -- saves written under per-type caps can total more than the shared cap:
    -- trim the stowed type first, the one in hand last
    self.throwableType = data.throwableType == 'molotov' and 'molotov' or 'grenade'
    local over = -self:throwableSpace()
    if over > 0 then
        local stowedIsMolotov = self.throwableType ~= 'molotov'
        local stowed = stowedIsMolotov and self.molotovs or self.grenades
        local cut = math.min(over, stowed)
        if stowedIsMolotov then self.molotovs = self.molotovs - cut
        else self.grenades = self.grenades - cut end
        over = over - cut
        if over > 0 then
            if stowedIsMolotov then self.grenades = math.max(0, self.grenades - over)
            else self.molotovs = math.max(0, self.molotovs - over) end
        end
    end
    self.items[4] = HandItem:newGrenade(
        self.throwableType == 'molotov' and 'molotov' or nil)
    self:syncThrowable()
    self.lastGunSlot = data.lastGunSlot or 1

    self.itemIndex = 3 -- knife fallback, then try the saved slot
    local saved = data.itemIndex or 1
    if self:slotValid(saved) then self.itemIndex = saved end
end

return Player