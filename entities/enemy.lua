local Entity = require('entities.entity')
local Animation = require('core.animation')
local Color = require('core.color')
local Path = require('core.path')
local Audio = require('core.audio')

local Enemy = {}
Enemy.__index = Enemy
setmetatable(Enemy, Entity)

function Enemy:new(x, y, width, height)
    local obj = Entity:new(x, y, width, height)
    obj.health = 200
    obj.color = Color.red
    obj.speed = 20
    obj.type = 'enemy'
    obj.fillStyle = 'fill' -- enemies draw as full circles

    obj.damage = TUNE.zombies.contactDamage
    obj.attackCooldown = TUNE.zombies.contactCooldown
    obj.attackTimer = obj.attackCooldown

    -- A* state; random start staggers the horde's repath frames
    obj.path = nil
    obj.pathIndex = 1
    obj.repathTimer = love.math.random() * TUNE.zombies.repathTime
    obj.stuckTimer = 0

    -- knife shove, decays fast (separate from vx/vy so accel can't fight it)
    obj.kbx, obj.kby = 0, 0

    -- random growls; silent until zombie recordings exist in assets/sounds/zombies
    obj.growlTimer = TUNE.zombies.growlMin
        + love.math.random() * (TUNE.zombies.growlMax - TUNE.zombies.growlMin)

    setmetatable(obj, Enemy)
    return obj
end

-- Life grows linearly until lifeLinearUntil, compounds after, then type mult
local function waveLife(wave)
    local w = TUNE.waves
    local capped = math.min(wave, w.lifeLinearUntil)
    local life = w.lifeBase + w.lifePerWave * (capped - 1)
    if wave > w.lifeLinearUntil then
        life = life * w.lifeGrowth ^ (wave - w.lifeLinearUntil)
    end
    return life
end

-- All numbers come from tune.lua
local function newTyped(x, y, wave, kind, color)
    local t = TUNE.zombies[kind]
    local obj = Enemy:new(x, y, t.size, t.size)
    obj.kind = kind -- 'slow'|'normal'|'fast', needed to rebuild from a save
    obj.speed = t.speed
    obj.health = waveLife(wave or 1) * t.lifeMult
    obj.color = color
    obj.damage = t.damage or TUNE.zombies.contactDamage
    obj.breaksCrates = t.breaksCrates or false
    obj.losShortcut = t.losShortcut or false

    -- wall-collision box capped so big sprites (slow, 48px) still fit 1-tile
    -- gaps and can reach wall-adjacent waypoints; combat circle stays size/2
    local box = math.min(t.size - TUNE.movement.collisionInset * 2,
                         TUNE.zombies.colliderCap)
    obj.colW, obj.colH = box, box
    obj.colOX, obj.colOY = (t.size - box) / 2, (t.size - box) / 2
    return obj
end

-- Gif-driven body: feet on the bottom of the collision box, any extra sprite
-- height overhangs above it. pingpong = play the cycle forward-then-back
-- (1-2-3-2) instead of a plain repeating loop.
local function attachSprite(obj, path, animTime, pingpong)
    obj.anim = Animation:fromGif(path, true)
    if pingpong then obj.anim:setPingPong(true) end
    obj.anim:setDuration(animTime)
    -- desync the horde: random frame, and a random leg for ping-pong walkers
    obj.anim.index = love.math.random(1, obj.anim.totalFrames)
    if pingpong and love.math.random() < 0.5 then obj.anim.dir = -1 end
    local _, _, sw, sh = obj.anim.quads[1]:getViewport()
    obj.spriteW, obj.spriteH = sw, sh
    obj.faceX = 1
    return obj
end

function Enemy:newSlow(x, y, wave)
    local obj = newTyped(x, y, wave, 'slow', Color.red)
    -- 54x60 gif, 4 frames (normal sprite 1.5x, red palette): centered on the
    -- 48px collision circle on both axes
    attachSprite(obj, 'assets/slow_zombie.gif',
        TUNE.zombies.slow.animTime, false)
    obj.spriteCenterY = true
    return obj
end

function Enemy:newNormal(x, y, wave)
    local obj = newTyped(x, y, wave, 'normal', Color.magenta)
    -- 36x40 gif, 4 frames: sprite centered on the 32px collision circle on
    -- both axes (4px overhang above and below, 2px each side)
    attachSprite(obj, 'assets/normal_zombie.gif',
        TUNE.zombies.normal.animTime, false)
    obj.spriteCenterY = true
    return obj
end

function Enemy:newFast(x, y, wave)
    local obj = newTyped(x, y, wave, 'fast', Color.yellow)
    -- 16x24 gif: bottom 16px = the body (the collision circle), top 8px is
    -- head/shoulder overhang drawn above the hitbox
    return attachSprite(obj, 'assets/fast_zombie.gif',
        TUNE.zombies.fast.animTime, false)
end

-- Every player-weapon hit funnels through here: applies the damage, pays
-- money per hit (+ a bonus on the kill), honors the instakill power-up.
-- econ = the weapon's payout numbers { hitReward, killBonus }; nil
-- (spikes, holes) hurts without paying and without instakill.
-- Returns true if this hit killed. Call sites keep their own juice
-- (blood, knockback, hitstop) — this owns health, flash and money only.
function Enemy:takeDamage(amount, world, econ)
    if self.health <= 0 then return false end
    if econ and world.buffs and world.buffs.instakill > 0 then
        amount = self.health
    end
    self.health = self.health - amount
    self.flash = true
    -- sprite types hold the white flash for a few frames; a 1-frame boolean
    -- vanishes at 60fps on an animated body
    self.flashTimer = TUNE.zombies.hitFlashTime
    local killed = self.health <= 0
    if econ then
        local p = world.player
        p:addMoney(econ.hitReward or 0)
        if killed then p:addMoney(econ.killBonus or 0) end
    end
    return killed
end

-- Normalized direction toward a world point
local function dirTo(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    local length = math.sqrt(dx*dx + dy*dy)
    if length == 0 then return 0, 0, 0 end
    return dx / length, dy / length, length
end

-- LOS check: march a box of half-width halfW along the line in 8px steps
-- against solid tiles and obstacle entities. Runs only on repath ticks
-- (every repathTime), and a clear line SKIPS that tick's A* — net cheaper.
-- Two callers with different questions:
--   halfW = body    "can I physically walk this straight line?" (A* skip)
--   halfW = 0       "is a real blocker between us?" (beeline gate)
-- ignoreCrates: a zombie already committed to smashing treats crates as air.
local function losClear(world, x0, y0, x1, y1, halfW, ignoreCrates)
    local dx, dy = x1 - x0, y1 - y0
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 1 then return true end

    local obs = {}
    for _, e in ipairs(world.entities) do
        if e.isObstacle and not e.toRemove
            and not (ignoreCrates and e.type == 'crate') then
            table.insert(obs, e)
        end
    end

    local steps = math.ceil(dist / 8)
    for i = 0, steps do
        local px, py = x0 + dx * i / steps, y0 + dy * i / steps
        if world.map:isSolidAt(px - halfW, py - halfW)
            or world.map:isSolidAt(px + halfW, py - halfW)
            or world.map:isSolidAt(px - halfW, py + halfW)
            or world.map:isSolidAt(px + halfW, py + halfW) then
            return false
        end
        for _, e in ipairs(obs) do
            if px + halfW > e.x and px - halfW < e.x + e.width
                and py + halfW > e.y and py - halfW < e.y + e.height then
                return false
            end
        end
    end
    return true
end

function Enemy:followPlayer(dt, world)
    local ts = world.map.tileSize
    local cx, cy = self:getCenter()
    local pcx, pcy = world.player:getCenter()

    local myCol, myRow = math.floor(cx / ts) + 1, math.floor(cy / ts) + 1
    local pCol, pRow = math.floor(pcx / ts) + 1, math.floor(pcy / ts) + 1

    -- A*: recompute every repathTime; walls = solid tiles + closed doors +
    -- crates. Crate-breakers only drop crates from the walls list when the
    -- normal route fails outright — chewing is a last resort, not a habit.
    self.repathTimer = self.repathTimer - dt
    if self.repathTimer <= 0 then
        self.repathTimer = TUNE.zombies.repathTime
        -- body-width line: losShortcut types walk it and skip this tick's A*
        local bodyClear = losClear(world, cx, cy, pcx, pcy,
            (self.colW or self.width) / 2 + 1, false)
        if self.losShortcut and bodyClear then
            self.path = nil
            self.smashMode = false
        else
            local path = Path.find(world.map, world:blockedTiles(false),
                myCol, myRow, pCol, pRow)
            self.smashMode = false
            if not path and self.breaksCrates then
                -- nowhere to walk around: now crates become chewable, and the
                -- route runs straight through them
                path = Path.find(world.map, world:blockedTiles(true),
                    myCol, myRow, pCol, pRow)
                self.smashMode = path ~= nil
            end
            self.path = path
        end
        self.pathIndex = 1

        -- Path smoothing: aim at the FARTHEST early waypoint reachable in a
        -- straight body-width line. A fresh path starts at the zombie's own
        -- tile center — often slightly behind a body mid-turn, so every
        -- repath tick used to yank it back a step at wall corners (the
        -- corner stutter). Lookahead capped to bound the losClear cost.
        if self.path then
            local half = (self.colW or self.width) / 2 + 1
            for i = 1, math.min(#self.path, 6) do
                local wp = self.path[i]
                if losClear(world, cx, cy, (wp.col - 0.5) * ts, (wp.row - 0.5) * ts,
                    half, self.smashMode) then
                    self.pathIndex = i
                else
                    break
                end
            end
        end

        -- Beeline gate: a zero-width line, so only a real blocker (wall,
        -- closed door, crate) vetoes it. The body-width line used to gate
        -- this, which froze fat zombies a step short of a player hugging a
        -- wall — their own bulk clipped the wall the player was pressed on.
        self.beelineOK = bodyClear
            or losClear(world, cx, cy, pcx, pcy, 0, self.smashMode)

        -- Crate-breaker whose straight line is blocked ONLY by crates: walk
        -- it anyway and chew through. Without this, a player hiding behind a
        -- crate one tile away left the zombie frozen — adjacent tile means
        -- the A* route is unused, the beeline was vetoed by the crate, and
        -- smashMode never turned on ("forgot" it can chew).
        if not self.beelineOK and self.breaksCrates
            and losClear(world, cx, cy, pcx, pcy, 0, true) then
            self.beelineOK = true
            self.smashMode = true
        end
    end

    local nx, ny = 0, 0
    local nearPlayer = math.abs(myCol - pCol) <= 1 and math.abs(myRow - pRow) <= 1

    if nearPlayer or not self.path or self.pathIndex > #self.path then
        -- same/adjacent tile, or no route found: head straight at the
        -- player — but only when the line is actually clear. "No route"
        -- with a closed door in between used to fall through here and the
        -- zombie ground its face into the door; now it waits at it and
        -- keeps re-checking every repath tick.
        if self.beelineOK ~= false then
            nx, ny = dirTo(cx, cy, pcx, pcy)
        end
    else
        -- walk waypoint tile centers; a wall-pinned body can sit a few px off
        -- a wall-adjacent tile center, so the reach radius must absorb that
        local wp = self.path[self.pathIndex]
        local wx, wy = (wp.col - 0.5) * ts, (wp.row - 0.5) * ts
        local dist
        nx, ny, dist = dirTo(cx, cy, wx, wy)
        if dist < TUNE.zombies.waypointRadius then
            self.pathIndex = self.pathIndex + 1
        end
    end

    self.maxSpeed = self.speed
    self:accelToward(dt, nx, ny, world)

    -- knockback rides on top of normal velocity for the move, then comes off
    -- again so accel keeps working from the real speed
    local decay = math.exp(-TUNE.knife.knockbackDecay * dt)
    self.kbx, self.kby = self.kbx * decay, self.kby * decay
    self.vx, self.vy = self.vx + self.kbx, self.vy + self.kby
    self:moveAndCollide(dt, world)
    self.vx, self.vy = self.vx - self.kbx, self.vy - self.kby

    -- stuck watchdog: wants to move but the world isn't letting it (crate
    -- shoved onto a stale path, wall pin) -> stop waiting out repathTimer
    local mx, my = self.x - cx + self.width/2, self.y - cy + self.height/2
    if (nx ~= 0 or ny ~= 0)
        and mx*mx + my*my < (self.speed * dt * 0.25)^2 then
        self.stuckTimer = self.stuckTimer + dt
        if self.stuckTimer >= TUNE.zombies.stuckRepath then
            self.repathTimer = 0
            self.stuckTimer = 0
        end
    else
        self.stuckTimer = 0
    end
end

function Enemy:update(dt, world)
    -- hit flash runs on its own timer, before any early-out: a frozen or
    -- dying zombie still flashes white when it's shot
    if (self.flashTimer or 0) > 0 then
        self.flashTimer = self.flashTimer - dt
        self.flash = true
    end

    -- dead: stop acting immediately — no posthumous step or contact hit.
    -- Threshold matches the killReward checks (<= 0), so fractional spike
    -- damage can't strand a 0.x hp zombie between the two rules.
    if self.health <= 0 then
        if not self.toRemove then
            self.toRemove = true
            world.kills = (world.kills or 0) + 1 -- every death path lands here
            local dx, dy = self:getCenter()
            -- nukedSilent: a nuke wipe skips per-zombie SFX (audio pool
            -- flood) and carriers caught in it don't drop fresh power-ups
            if not self.nukedSilent then
                Audio.playAt('zombie_death', dx, dy, 1, TUNE.audio.pitchJitter, world)
                if self.carrier then
                    world:addEntity(
                        require('entities.powerup'):new(dx, dy, self.carrier))
                end
            end
        end
        return
    end

    -- freeze power-up: statues — no movement, no attacks, no growls.
    -- Knockback zeroed so a knife shove doesn't resume on thaw.
    if world.buffs and world.buffs.freeze > 0 then
        self.vx, self.vy = 0, 0
        self.kbx, self.kby = 0, 0
        return
    end

    self:followPlayer(dt, world)

    -- sprite types: run cycle + facing (frozen/dead returned above, so a
    -- statue or a corpse holds its frame)
    if self.anim then
        self.anim:update(dt)
        if self.vx > 5 then self.faceX = 1
        elseif self.vx < -5 then self.faceX = -1 end
    end

    -- spikes hurt, water/mud slow, holes kill
    self:applyTileEffects(dt, world)

    -- Contact damage on the player (not while falling/invincible).
    -- Separation keeps the circles just apart, so plain overlap would never
    -- trigger: attackRange pads the reach a few px past touching.
    local px, py = world.player:getCenter()
    local cx, cy = self:getCenter()
    local ddx, ddy = px - cx, py - cy
    local reach = self.radius + world.player.radius + TUNE.zombies.attackRange

    self.attackTimer = self.attackTimer + dt
    if self.attackTimer >= self.attackCooldown and ddx*ddx + ddy*ddy < reach*reach
        and not world.player.falling and world.player.invulnTimer <= 0
        and not world.player.godMode then
        world.player.health = world.player.health - self.damage
        world.player.flashTimer = TUNE.player.hitFlashTime
        -- brief post-hit invuln: an encircling pack can't stack 3-4 contact
        -- hits in the same beat and one-shot a full-health player
        world.player.invulnTimer = math.max(world.player.invulnTimer,
            TUNE.player.contactInvulnTime)
        self.attackTimer = 0
        Audio.playAt('zombie_attack', cx, cy, 1, TUNE.audio.pitchJitter, world)
    end

    -- crate smashing (breaksCrates types, and only while smashMode says the
    -- normal route is gone): their A* then walks through crate tiles, so when
    -- one physically blocks them they beat on it until it breaks.
    -- Shares attackTimer with the player hit — a zombie in reach of the
    -- player (checked above, resets the timer) always prefers the player.
    if self.breaksCrates and self.smashMode
        and self.attackTimer >= self.attackCooldown then
        local crate = world:getTouchingCrate(self, 2)
        if crate then
            crate.health = crate.health - TUNE.zombies.crateDamage
            crate.flash = true
            self.attackTimer = 0
            Audio.playAt('zombie_attack', cx, cy, 1, TUNE.audio.pitchJitter, world)
            if crate.health <= 0 then
                world:removeEntity(crate)
            end
        end
    end

    -- occasional growl (positional — you hear which side it comes from)
    self.growlTimer = self.growlTimer - dt
    if self.growlTimer <= 0 then
        self.growlTimer = TUNE.zombies.growlMin
            + love.math.random() * (TUNE.zombies.growlMax - TUNE.zombies.growlMin)
        Audio.playAt('zombie_growl', cx, cy, 1, TUNE.audio.pitchJitter, world)
    end

end

-- Keeps the sprite's alpha shape, paints every pixel white (hit flash)
local flashShader
local function whiteShader()
    flashShader = flashShader or love.graphics.newShader[[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            return vec4(1.0, 1.0, 1.0, Texel(tex, tc).a * color.a);
        }
    ]]
    return flashShader
end

-- Animated types: by default the sprite's feet sit on the bottom of the
-- collision box, extra height hangs above it. spriteCenterY types are
-- centered on the hitbox instead (overhang split top/bottom).
function Enemy:drawSprite()
    local a = self.anim
    local x = math.floor(self.x + self.width / 2)
    local y, oy
    if self.spriteCenterY then
        y = math.floor(self.y + self.height / 2)
        oy = self.spriteH / 2
    else
        y = math.floor(self.y + self.height)
        oy = self.spriteH
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(a.image, a.quads[a.index], x, y, 0,
        self.faceX, 1, self.spriteW / 2, oy)

    -- hit flash: the sprite's silhouette filled solid white (an additive pass
    -- barely showed up in a dark room)
    if self.flash then
        love.graphics.setShader(whiteShader())
        love.graphics.draw(a.image, a.quads[a.index], x, y, 0,
            self.faceX, 1, self.spriteW / 2, oy)
        love.graphics.setShader()
    end
    self.flash = false
end

function Enemy:draw()
    -- power-up carrier: pulsing gold glow under the body
    if self.carrier then
        local cx, cy = self:getCenter()
        local pulse = 1 + 0.15
            * math.sin(love.timer.getTime() * TUNE.powerups.carrierPulseSpeed)
        love.graphics.setBlendMode('add')
        love.graphics.setColor(1, 0.85, 0.25, 0.35)
        love.graphics.circle('fill', cx, cy, self.radius * 1.3 * pulse)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1)
    end

    if self.anim then self:drawSprite() else Entity.draw(self) end

    -- frozen: icy tint over the body
    if world and world.buffs and world.buffs.freeze > 0 then
        local cx, cy = self:getCenter()
        love.graphics.setColor(0.35, 0.75, 1, 0.45)
        love.graphics.circle('fill', cx, cy, self.radius)
        love.graphics.setColor(1, 1, 1)
    end

    -- Remaining health above the body -- debug readout only, so it rides the
    -- H hitbox overlay instead of cluttering the normal view
    if showHitboxes then
        local hp = math.ceil(self.health)
        local fontWidth = smallFont:getWidth(hp)
        local fontHeight = smallFont:getHeight()

        love.graphics.setFont(smallFont)
        love.graphics.setColor(Color.red())
        love.graphics.print(hp, self.x + self.width/2 - fontWidth/2, self.y - fontHeight)
        love.graphics.setColor(Color.white())
        love.graphics.setFont(font)
    end
end

return Enemy