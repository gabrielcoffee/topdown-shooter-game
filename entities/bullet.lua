local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Animation = require('core.animation')
local Audio = require('core.audio')

local Bullet = {}
Bullet.__index = Bullet
setmetatable(Bullet, Entity)


function Bullet:new(x, y, angle, damage, muzzleOffset, lifetime, killReward, maxHits)
    local obj = Entity:new(x, y, 2, 4)

    obj.color = Color.white
    obj.speed = TUNE.bullet.speed
    obj.angle = angle
    obj.sprite = Assets.quads.bullet[1]
    obj.damage = damage
    obj.killReward = killReward or 0
    obj.hitsLeft = maxHits or 1 -- zombies left to pierce before the bullet dies
    obj.hitEnemies = {}         -- each zombie takes this bullet's damage once
    obj.lifetime = lifetime
    obj.timer = 0
    obj.ox = 0
    obj.oy = 1
    obj.dx = math.cos(angle)
    obj.dy = math.sin(angle)

    obj.x = obj.x + (obj.dx * muzzleOffset)
    obj.y = obj.y + (obj.dy * muzzleOffset)

    obj.animMuzzle = Animation:new(Assets.quads.muzzle, 1, 3, 0.017)
    
    setmetatable(obj, Bullet)
    return obj
end

function Bullet:update(dt, world)
 
    if self.timer ~= 0 then
        self.x = self.x + ((self.dx * self.speed) * dt)
        self.y = self.y + ((self.dy * self.speed) * dt)
    end

    self.timer = self.timer + dt

    if self.timer >= self.lifetime then
        world:removeEntity(self)
    end

    self.animMuzzle:update(dt)

    -- walls stop bullets (bullet_hit samples are wall-impact sounds)
    if world.map:isSolidAt(self.x, self.y) then
        world:removeEntity(self)
        Audio.playAt('bullet_hit', self.x, self.y, 1, TUNE.audio.pitchJitter, world)
    end

    -- crates take damage, doors just stop bullets (sfx for both come later)
    for _, e in ipairs(world.entities) do
        if e.isObstacle and not e.toRemove
            and self.x > e.x and self.x < e.x + e.width
            and self.y > e.y and self.y < e.y + e.height then
            world:removeEntity(self)
            if e.type == 'crate' then
                e.health = e.health - self.damage
                e.flash = true
                if e.health <= 0 then
                    world:removeEntity(e)
                end
            end
            break
        end
    end

    -- already stopped by a wall/crate/door this frame
    if self.toRemove then return end

    -- pierce: every overlapping zombie is damaged once per bullet; the bullet
    -- only dies after maxHits total. health > 0 guard: an already-dead enemy
    -- can't pay twice (shotgun pellets), and corpses don't eat a pierce.
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and e.health > 0
            and not self.hitEnemies[e] and self:collidesWith(e) then
            self.hitEnemies[e] = true
            e.health = e.health - self.damage
            e.flash = true
            world.vfx:bloodSplatter(self.x, self.y, self.angle)
            Audio.playAt('flesh_hit', self.x, self.y, 1, TUNE.audio.pitchJitter, world)

            if e.health <= 0 then
                world.player.money = world.player.money + self.killReward
            end

            self.hitsLeft = self.hitsLeft - 1
            if self.hitsLeft <= 0 then
                world:removeEntity(self)
                break
            end
        end
    end
end

function Bullet:draw()
    love.graphics.setColor(Color.white())

    if self.timer < 0.07 then

        self.animMuzzle:draw(
            self.x, self.y,
            self.angle,
            1, 1,
            self.ox, self.oy+5
        )
    end

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y),
        self.angle,
        1, 1,
        self.ox, self.oy
    )

    love.graphics.setColor(Color.white())
end

return Bullet