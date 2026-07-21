local Assets = require('core.assets')
local Bullet = require('entities.bullet')
local HandItem = require('hand_items.hand_item')
local Audio = require('core.audio')

local Gun = {}
Gun.__index = Gun
setmetatable(Gun, HandItem)

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
        reloadTimer = 0
    }
end

-- All numbers come from tune.lua (t = one entry of TUNE.guns)
local function applyTune(obj, t)
    obj.maxClip = t.clip
    obj.curClip = t.clip
    obj.bulletsLeft = t.clip * 3
    obj.walkSpeed = t.walkSpeed
    obj.damage = t.damage
    obj.bulletLifeTime = t.bulletLife
    obj.reloadingTime = t.reloadTime
    obj.bulletDelay = t.bulletDelay
    obj.spread = t.spread
    obj.pellets = t.pellets
    obj.killReward = t.killReward
end

function Gun:newUSP()
    local obj = GunStateVariables(TUNE.guns.usp.clip)
    applyTune(obj, TUNE.guns.usp)

    obj.name = 'USP-45'
    obj.sprite = Assets.quads.pistol[1]
    obj.type = GUNTYPE.semi
    obj.shotSfx = 'mac10_shot' -- closest pistol-ish sample on disk
    obj.ox = 4
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newAk47()
    local obj = GunStateVariables(TUNE.guns.ak47.clip)
    applyTune(obj, TUNE.guns.ak47)

    obj.name = 'AK-47'
    obj.sprite = Assets.quads.ak47[1]
    obj.type = GUNTYPE.auto
    obj.shotSfx = 'ak47_shot'
    obj.ox = 12
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newM4A1()
    local obj = GunStateVariables(TUNE.guns.m4a1.clip)
    applyTune(obj, TUNE.guns.m4a1)

    obj.name = 'M4A1'
    obj.sprite = Assets.quads.m4a1[1]
    obj.type = GUNTYPE.auto
    obj.shotSfx = 'm4a1_shot'
    obj.ox = 12
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newShotgun()
    local obj = GunStateVariables(TUNE.guns.lupara.clip)
    applyTune(obj, TUNE.guns.lupara)

    obj.name = 'Lupara'
    obj.sprite = Assets.quads.shotgun[1]
    obj.type = GUNTYPE.shotgun
    obj.shotSfx = 'shotgun_shot'
    obj.reloadSfx = 'shotgun_reload' -- only reload sample on disk; other guns reload silent for now
    obj.ox = 12
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:update(dt, px, py, mx, my)
    HandItem.update(self, dt, px, py, mx, my)

    if self.canShoot == false then
        self.timer = self.timer + dt
    end

    if self.timer >= self.bulletDelay then
        self.canShoot = true
        self.timer = 0
    end

    if self.reloading then
        self.reloadTimer = self.reloadTimer + dt
        if self.reloadTimer >= self.reloadingTime then
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
    if self.reloadSfx then
        Audio.play(self.reloadSfx)
    end
end

function Gun:cancelReload()
    self.reloading = false
    self.reloadTimer = 0
end

function Gun:draw(facingLeft)
    HandItem.draw(self, facingLeft)
end

function Gun:drawHud()
    if self.reloading then
        love.graphics.print(T('hud.reloading', self.name), 20, 20)
    else
        love.graphics.print(T('hud.ammo', self.name, self.curClip, self.bulletsLeft), 20, 20)
    end
end

function Gun:fire(leftReleased)

    if self.reloading then
        return
    end

    if self.curClip <= 0 then
        self:reload()
        return
    end

    if not self.canShoot then
        return
    end

    if self.type == GUNTYPE.auto or leftReleased then

        local _, _, gw, gh = self.sprite:getViewport()
        gw = gw - self.ox

        self.canShoot = false
        Audio.play(self.shotSfx) -- once per trigger pull, not per pellet

        -- muzzle juice: flash light + sparks
        local mx = self.x + math.cos(self.angle) * gw
        local my = self.y + math.sin(self.angle) * gw
        local mb = TUNE.lighting.muzzleBright
        world.lighting:flash(mx, my, mb, mb * 0.8, mb * 0.45,
            TUNE.lighting.muzzleRange, TUNE.lighting.muzzleTime)
        world.vfx:muzzleSparks(mx, my, self.angle)

        if self.type == GUNTYPE.shotgun then
            for i = 1, self.pellets do
                local finalSpread = (love.math.random() * 2 - 1) * self.spread
                world:addEntity(
                    Bullet:new(
                        self.x, self.y,
                        self.angle + finalSpread, self.damage,
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
                    self.angle, self.damage,
                    gw,
                    self.bulletLifeTime,
                    self.killReward
                )
            )
        end
        self.curClip = self.curClip - 1
    end
end

return Gun