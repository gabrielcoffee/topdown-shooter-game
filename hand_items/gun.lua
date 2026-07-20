local Assets = require('core.assets')
local Bullet = require('entities.bullet')
local HandItem = require('hand_items.hand_item')

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

function Gun:newUSP()
    local obj = GunStateVariables(15)
    
    obj.name = 'USP-45'
    obj.sprite = Assets.quads.pistol[1]
    obj.type = GUNTYPE.semi
    obj.walkSpeed = 120 -- TUNE
    obj.damage = 18
    obj.bulletLifeTime = 0.5
    obj.reloadingTime = 2
    obj.bulletDelay = 0.15
    obj.ox = 4
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newAk47()
    local obj = GunStateVariables(30)
    
    obj.name = 'AK-47'
    obj.sprite = Assets.quads.ak47[1]
    obj.type = GUNTYPE.auto
    obj.walkSpeed = 90 -- TUNE
    obj.damage = 25
    obj.bulletLifeTime = 0.7
    obj.reloadingTime = 2.7
    obj.bulletDelay = 0.1
    obj.ox = 12
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newM4A1()
    local obj = GunStateVariables(30)
    
    obj.name = 'M4A1'
    obj.sprite = Assets.quads.m4a1[1]
    obj.type = GUNTYPE.auto
    obj.walkSpeed = 90 -- TUNE
    obj.damage = 23
    obj.bulletLifeTime = 0.7
    obj.reloadingTime = 2.7
    obj.bulletDelay = 0.1
    obj.ox = 12
    obj.oy = 16

    setmetatable(obj, Gun)
    return obj
end

function Gun:newShotgun()
    local obj = GunStateVariables(7)
    
    obj.name = 'Lupara'
    obj.sprite = Assets.quads.shotgun[1]
    obj.type = GUNTYPE.shotgun
    obj.walkSpeed = 100 -- TUNE: sawed-off is light
    obj.damage = 23
    obj.bulletLifeTime = 0.7
    obj.reloadingTime = 1
    obj.bulletDelay = 0.5
    obj.ox = 12
    obj.oy = 16

    obj.spread = 0.05

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
        love.graphics.print(self.name..'  RELOADING...', 20, 20)
    else
        love.graphics.print(self.name..'  Ammo: '..self.curClip..'/'..self.bulletsLeft, 20, 20)
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
        if self.type == GUNTYPE.shotgun then
            for i = 1, 7 do
                local finalSpread = love.math.random(-self.spread, self.spread)

                print(finalSpread)
                world:addEntity(
                    Bullet:new(
                        self.x, self.y,
                        self.angle + finalSpread, self.damage,
                        gw,
                        self.bulletLifeTime
                    )
                )
            end
        else
            world:addEntity(
                Bullet:new(
                    self.x, self.y,
                    self.angle, self.damage,
                    gw,
                    self.bulletLifeTime
                )
            )
        end
        self.curClip = self.curClip - 1
    end
end

return Gun