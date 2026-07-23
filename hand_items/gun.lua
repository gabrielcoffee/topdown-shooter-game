local Assets = require('core.assets')
local Bullet = require('entities.bullet')
local HandItem = require('hand_items.hand_item')
local Audio = require('core.audio')
local Animation = require('core.animation')

local Gun = {}
Gun.__index = Gun
setmetatable(Gun, HandItem)

-- Ordered list + factory by id: single source for chest, console, save restore
Gun.ids = { 'usp', 'ak47', 'm4a1', 'sawedoff' }

function Gun.newById(id)
    if id == 'usp' then return Gun:newUSP() end
    if id == 'ak47' then return Gun:newAk47() end
    if id == 'm4a1' then return Gun:newM4A1() end
    if id == 'sawedoff' then return Gun:newShotgun() end
end

-- gun id -> spritesheet quad name (ids mostly match, two exceptions)
function Gun.quadName(id)
    if id == 'sawedoff' then return 'shotgun' end
    if id == 'usp' then return 'pistol' end
    return id
end

_G.GUNTYPE = {
    auto = 0,
    semi = 1,
    shotgun = 2
}

local function GunStateVariables(maxClip)
    return {
        x = 0,
        y = 0,
        angle = 0,
        timer = 0,
        canShoot = false,
        isGun = true,
        maxClip = maxClip,
        curClip = maxClip,
        bulletsLeft = maxClip * 3,
        reloading = false,
        reloadTimer = 0,
        recoil = 0,      -- spread added by firing, recovers after a pause
        sinceShot = 999, -- secs since the last shot (gates recoil recovery)
        kickPos = 0,     -- visual slide-back, 1 = just fired -> 0
        kickAng = 0      -- visual muzzle-rise, 1 = just fired -> 0
    }
end

-- All numbers come from tune.lua (t = one entry of TUNE.guns)
local function applyTune(obj, t)
    obj.maxClip = t.clip
    obj.curClip = t.clip
    obj.bulletsLeft = t.reserve or t.clip * 3
    obj.damage = t.damage
    obj.bulletLifeTime = t.bulletLife
    obj.reloadingTime = t.reloadTime
    obj.bulletDelay = t.bulletDelay
    obj.spread = t.spread
    obj.pellets = t.pellets
    obj.killReward = t.killReward
    obj.baseSpread = t.baseSpread or 0
    obj.moveSpread = t.moveSpread or 0
    obj.recoilPerShot = t.recoilPerShot or 0
    obj.recoilMax = t.recoilMax or 0
    obj.recoilRecover = t.recoilRecover or 0
    obj.recoilDelay = t.recoilDelay or 0
end

function Gun:newUSP()
    local obj = GunStateVariables(TUNE.guns.usp.clip)
    applyTune(obj, TUNE.guns.usp)

    obj.name = 'USP-45'
    obj.id = 'usp'
    obj.sprite = Assets.quads.held_pistol[1] -- in-hand: with-hands version
    obj.icon = Assets.quads.pistol[1]        -- hotbar: bare item
    obj.type = GUNTYPE.semi
    obj.shotSfx = 'usp_shot'
    obj.reloadSfx = 'usp_reload'
    obj.ox = 4
    obj.oy = 16
    obj.tipLen = 22 -- barrel tip distance from pivot (muzzle/bullet spawn)

    setmetatable(obj, Gun)
    return obj
end

function Gun:newAk47()
    local obj = GunStateVariables(TUNE.guns.ak47.clip)
    applyTune(obj, TUNE.guns.ak47)

    obj.name = 'AK-47'
    obj.id = 'ak47'
    obj.sprite = Assets.quads.held_ak47[1]
    obj.icon = Assets.quads.ak47[1]
    obj.type = GUNTYPE.auto
    obj.shotSfx = 'ak47_shot'
    obj.reloadSfx = 'ak47_reload'
    obj.reloadAnim = Animation:fromGif('assets/ak_reload.gif', false)
    obj.ox = 12 -- reload gif shares the held sprite's coordinate space, same pivot
    obj.oy = 16
    obj.tipLen = 36

    setmetatable(obj, Gun)
    return obj
end

function Gun:newM4A1()
    local obj = GunStateVariables(TUNE.guns.m4a1.clip)
    applyTune(obj, TUNE.guns.m4a1)

    obj.name = 'M4A1'
    obj.id = 'm4a1'
    obj.sprite = Assets.quads.held_m4a1[1]
    obj.icon = Assets.quads.m4a1[1]
    obj.type = GUNTYPE.auto
    obj.shotSfx = 'm4a1_shot'
    obj.reloadSfx = 'm4a1_reload'
    obj.ox = 12
    obj.oy = 16
    obj.tipLen = 44

    setmetatable(obj, Gun)
    return obj
end

function Gun:newShotgun()
    local obj = GunStateVariables(TUNE.guns.sawedoff.clip)
    applyTune(obj, TUNE.guns.sawedoff)

    obj.name = 'Sawed-Off'
    obj.id = 'sawedoff'
    obj.sprite = Assets.quads.held_shotgun[1]
    obj.icon = Assets.quads.shotgun[1]
    obj.type = GUNTYPE.shotgun
    obj.shotSfx = 'shotgun_shot'
    obj.reloadSfx = 'shotgun_reload' -- break-open + tick, plays before shells go in
    obj.shellSfx = { 'shell1', 'shell2', 'shell3' }
    obj.reloadOpenTime = TUNE.guns.sawedoff.reloadOpenTime
    obj.ox = 12
    obj.oy = 16
    obj.tipLen = 28

    setmetatable(obj, Gun)
    return obj
end

function Gun:update(dt, px, py, mx, my)
    HandItem.update(self, dt, px, py, mx, my)

    -- recoil holds while firing; recovery only starts recoilDelay after the
    -- last shot (otherwise recovery between shots eats every shot's gain)
    self.sinceShot = self.sinceShot + dt
    if self.sinceShot >= self.recoilDelay then
        self.recoil = math.max(0, self.recoil - self.recoilRecover * dt)
    end

    -- visual kick decays: slide-back fast, muzzle-rise slower (both draw-only)
    local GK = TUNE.gunKick
    self.kickPos = math.max(0, self.kickPos - dt / GK.posTime)
    self.kickAng = math.max(0, self.kickAng - dt / GK.angTime)

    if self.canShoot == false then
        self.timer = self.timer + dt
    end

    if self.timer >= self.bulletDelay then
        self.canShoot = true
        self.timer = 0
    end

    if self.reloading then
        self.reloadTimer = self.reloadTimer + dt
        if self.reloadAnim then
            self.reloadAnim:update(dt)
        end
        if self.shellSfx then
            -- per-shell reload: break-open first, then one shell per reloadTime
            if self.reloadOpening then
                if self.reloadTimer >= (self.reloadOpenTime or 0) then
                    self.reloadOpening = false
                    self.reloadTimer = 0
                end
            elseif self.reloadTimer >= self.reloadingTime then
                self.reloadTimer = 0
                self.curClip = self.curClip + 1
                self.bulletsLeft = self.bulletsLeft - 1
                Audio.playAt(self.shellSfx[love.math.random(#self.shellSfx)], self.x, self.y)
                if self.curClip >= self.maxClip or self.bulletsLeft <= 0 then
                    self.reloading = false
                end
            end
        elseif self.reloadTimer >= self.reloadingTime then
            local moved = math.min(self.maxClip - self.curClip, self.bulletsLeft)
            self.curClip = self.curClip + moved
            self.bulletsLeft = self.bulletsLeft - moved
            self.reloading = false
            self.reloadTimer = 0
        end
    end
end

function Gun:reload()
    if self.reloading or self.curClip >= self.maxClip or self.bulletsLeft <= 0 then
        return
    end
    self.reloading = true
    self.reloadTimer = 0
    self.reloadOpening = self.shellSfx ~= nil
    if self.reloadAnim then
        -- gif plays exactly once over the tuned reload time
        self.reloadAnim:setDuration(self.reloadingTime)
        self.reloadAnim:restart()
    end
    if self.reloadSfx then
        Audio.playAt(self.reloadSfx, self.x, self.y)
    end
end

function Gun:cancelReload()
    self.reloading = false
    self.reloadOpening = false
    self.reloadTimer = 0
end

function Gun:draw(facingLeft)
    local GK = TUNE.gunKick
    local ang = self.angle
    local dx, dy = 0, 0

    if self.reloading then
        -- fixed pose: barrel held ~30 deg up, pointing the way you face, ignores mouse
        local up = math.rad(GK.reloadUpAngle)
        ang = facingLeft and (math.pi + up) or -up
    else
        -- per-shot kick: muzzle snaps up (sign flips with facing so it's always
        -- "up"), whole gun slides straight back along the barrel
        local sign = facingLeft and 1 or -1
        ang = ang + sign * math.rad(GK.angle) * self.kickAng
        local back = GK.dist * self.kickPos
        dx = -math.cos(self.angle) * back
        dy = -math.sin(self.angle) * back
    end

    -- reload gif replaces the gun sprite; same transform so the art lines up
    local img, quad = Assets.spritesheet, self.sprite
    if self.reloading and self.reloadAnim then
        local a = self.reloadAnim
        img, quad = a.image, a.quads[a.index]
    end

    love.graphics.draw(
        img, quad,
        math.floor(self.x + dx), math.floor(self.y + dy),
        ang, 1, facingLeft and -1 or 1, self.ox, self.oy
    )
end

function Gun:drawHud()
    if self.reloading then
        love.graphics.print(T('hud.reloading', self.name), 20, 20)
    else
        love.graphics.print(T('hud.ammo', self.name, self.curClip, self.bulletsLeft), 20, 20)
    end
end

-- Total inaccuracy right now (radians): standing base + movement + recoil.
-- The crosshair maps this same number to its gap, so what you see is what
-- the bullets do.
function Gun:currentSpread(moveFactor)
    return self.baseSpread + self.moveSpread * (moveFactor or 0) + self.recoil
end

function Gun:fire(leftReleased)

    if self.reloading then
        -- per-shell reload can be interrupted to fire what's already loaded
        if self.shellSfx and self.curClip > 0 and not self.reloadOpening then
            self:cancelReload()
        else
            return
        end
    end

    if self.curClip <= 0 then
        self:reload()
        return
    end

    if not self.canShoot then
        return
    end

    if self.type == GUNTYPE.auto or leftReleased then

        -- barrel tip distance from the pivot; quad width no longer works since
        -- held cells are padded (64 wide) beyond the gun art
        local gw = self.tipLen

        self.canShoot = false
        Audio.playAt(self.shotSfx, self.x, self.y) -- once per trigger pull, not per pellet

        -- muzzle juice: flash light + sparks
        local mx = self.x + math.cos(self.angle) * gw
        local my = self.y + math.sin(self.angle) * gw
        local mb = TUNE.lighting.muzzleBright
        world.lighting:flash(mx, my, mb, mb * 0.8, mb * 0.45,
            TUNE.lighting.muzzleRange, TUNE.lighting.muzzleTime)
        world.vfx:muzzleSparks(mx, my, self.angle)

        -- aim spread pushes the shot (or the whole pellet cone) off center
        local spread = self:currentSpread(world.player.moveFactor)
        local shotAngle = self.angle + (love.math.random() * 2 - 1) * spread

        if self.type == GUNTYPE.shotgun then
            for i = 1, self.pellets do
                local finalSpread = (love.math.random() * 2 - 1) * self.spread
                world:addEntity(
                    Bullet:new(
                        self.x, self.y,
                        shotAngle + finalSpread, self.damage,
                        gw,
                        self.bulletLifeTime,
                        self.killReward
                    )
                )
            end
        else
            world:addEntity(
                Bullet:new(
                    self.x, self.y,
                    shotAngle, self.damage,
                    gw,
                    self.bulletLifeTime,
                    self.killReward
                )
            )
        end
        self.recoil = math.min(self.recoilMax, self.recoil + self.recoilPerShot)
        self.sinceShot = 0
        self.kickPos = 1 -- trigger visual kick (auto fire re-arms it every shot)
        self.kickAng = 1
        self.curClip = self.curClip - 1

        -- sawed-off: barrels empty -> break open and reload right away
        if self.shellSfx and self.curClip <= 0 and self.bulletsLeft > 0 then
            self:reload()
        end
    end
end

return Gun