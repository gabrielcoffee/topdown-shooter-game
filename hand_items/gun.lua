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
        curClip = maxClip,
        bulletsLeft = maxClip * 3
    }
end

function Gun:newUSP()
    local obj = GunStateVariables(15)
    
    obj.sprite = Assets.quads.pistol[1]
    obj.type = GUNTYPE.semi
    obj.walkSpeed = 120 -- APPLY TO PLAYER
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
    
    obj.sprite = Assets.quads.ak47[1]
    obj.type = GUNTYPE.auto
    obj.walkSpeed = 90 -- APPLY TO PLAYER
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
    
    obj.sprite = Assets.quads.m4a1[1]
    obj.type = GUNTYPE.auto
    obj.walkSpeed = 90 -- APPLY TO PLAYER
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
    
    obj.sprite = Assets.quads.shotgun[1]
    obj.type = GUNTYPE.shotgun
    obj.walkSpeed = 90 -- APPLY TO PLAYER
    obj.damage = 23
    obj.bulletLifeTime = 0.7
    obj.reloadingTime = 1
    obj.bulletDelay = 0.5
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
end

function Gun:drawInfo()
    love.graphics.print('Ammo: '..self.curClip, 20, 20)
end

function Gun:draw(facingLeft)
    HandItem.draw(self, facingLeft)
    self:drawInfo()
end

function Gun:fire(leftReleased)

    if not self.canShoot or self.curClip <= 0 then
        return
    end

    if self.type == GUNTYPE.auto or leftReleased then

        local _, _, gw, gh = self.sprite:getViewport()
        gw = gw - self.ox

        self.canShoot = false
        world:addEntity(
            Bullet:new(
                self.x, self.y,
                self.angle, self.damage,
                gw,
                self.bulletLifeTime
            )
        )
        self.curClip = self.curClip - 1
    end
end

return Gun