local Entity = require('entities.entity')
local Assets = require('core.assets')
local Color = require('core.color')
local Animation = require('core.animation')
local Audio = require('core.audio')

local Bullet = {}
Bullet.__index = Bullet
setmetatable(Bullet, Entity)


function Bullet:new(x, y, angle, damage, muzzleOffset, lifetime, econ, maxHits, showMuzzle, owner)
    local obj = Entity:new(x, y, 2, 4)

    obj.type = 'bullet' -- every other entity names itself; replication needs it
    obj.color = Color.white
    obj.speed = TUNE.bullet.speed
    obj.angle = angle
    obj.sprite = Assets.quads.bullet[1]
    obj.damage = damage
    obj.econ = econ             -- payout numbers, spent by Enemy:takeDamage
    obj.owner = owner           -- the player who fired: gets paid for the kill
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

    -- shotgun blasts pass showMuzzle=false for all but one pellet: 14 flash
    -- animations stacked on the same pixel were pure allocation waste
    obj.animMuzzle = (showMuzzle ~= false)
        and Animation:new(Assets.quads.muzzle, 1, 3, 0.017) or nil

    setmetatable(obj, Bullet)
    return obj
end

function Bullet:update(dt, world)
    -- The first update samples the spawn point (muzzle-touch kills keep
    -- working), plus a short tail BEHIND it (bullet.tailLen): the muzzle sits
    -- tipLen px out from the player, so a zombie pressed inside that gap was
    -- unhittable. The tail probes zombies only — never walls/crates, so a
    -- wall-hugging shooter can't have the shot eaten by the wall behind them.
    -- After that the flight is swept in <=8px substeps, so no wall, crate or
    -- small zombie can fit between two samples — at 540px/s a single
    -- point-check per frame skipped 21px fast zombies below ~26fps.
    local dist = (self.timer == 0) and 0 or self.speed * dt
    if self.timer == 0 then
        local d = TUNE.bullet.tailLen or 0
        while d > 0 and not self.toRemove do
            self:checkZombieHits(world, self.x - self.dx * d, self.y - self.dy * d)
            d = d - 8
        end
    end
    self.timer = self.timer + dt
    if self.animMuzzle then self.animMuzzle:update(dt) end

    repeat
        local step = math.min(dist, 8)
        self.x = self.x + self.dx * step
        self.y = self.y + self.dy * step
        dist = dist - step
        self:checkHits(world)
    until dist <= 0 or self.toRemove

    if not self.toRemove and self.timer >= self.lifetime then
        world:removeEntity(self)
    end
end

-- One collision pass at the current position: wall, then obstacles, then
-- zombies (with pierce)
function Bullet:checkHits(world)
    -- walls stop bullets (bullet_hit samples are wall-impact sounds)
    if world.map:isSolidAt(self.x, self.y) then
        world:removeEntity(self)
        world.vfx:wallHit(self.x, self.y, self.angle)
        Audio.playAt('bullet_hit', self.x, self.y, 1, TUNE.audio.pitchJitter, world)
        return
    end

    -- crates take damage, doors just stop bullets (sfx for both come later)
    for _, e in ipairs(world.entities) do
        if e.isObstacle and not e.toRemove
            and self.x > e.x and self.x < e.x + e.width
            and self.y > e.y and self.y < e.y + e.height then
            world:removeEntity(self)
            world.vfx:wallHit(self.x, self.y, self.angle)
            if e.type == 'crate' then
                e:hit(self.damage, world, self.econ, self.owner)
            end
            return
        end
    end

    self:checkZombieHits(world, self.x, self.y)
end

-- Zombie pass at an arbitrary sample point: the flight sweep samples the
-- bullet's own position, the first-frame tail probes behind it.
-- Pierce: every overlapping zombie is damaged once per bullet; the bullet
-- only dies after maxHits total. health > 0 guard: an already-dead enemy
-- can't pay twice (shotgun pellets), and corpses don't eat a pierce.
function Bullet:checkZombieHits(world, px, py)
    local bx, by = px + self.width / 2, py + self.height / 2
    for _, e in ipairs(world.entities) do
        if e.type == 'enemy' and not e.toRemove and e.health > 0
            and not self.hitEnemies[e] then
            local ex, ey = e:getCenter()
            local dx, dy = bx - ex, by - ey
            local r = self.radius + e.radius
            if dx*dx + dy*dy < r*r then
                self.hitEnemies[e] = true
                e:takeDamage(self.damage, world, self.econ, self.owner)
                world.vfx:bloodSplatter(bx, by, self.angle)
                Audio.playAt('flesh_hit', bx, by, 1, TUNE.audio.pitchJitter, world)

                self.hitsLeft = self.hitsLeft - 1
                if self.hitsLeft <= 0 then
                    world:removeEntity(self)
                    return
                end
            end
        end
    end
end

function Bullet:draw()
    love.graphics.setColor(Color.white())

    if self.animMuzzle and self.timer < 0.07 then

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