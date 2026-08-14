local Assets = require('core.assets')
local Bullet = require('entities.bullet')
local ShellCasing = require('entities.shell_casing')
local HandItem = require('hand_items.hand_item')
local Audio = require('core.audio')
local Animation = require('core.animation')
local Gif = require('core.gif')

-- Draw/pickup animation: the tail of the reload gif (mag slap + rack), spread
-- over the gun's drawTime, then the static held sprite takes over. The frames
-- share the held sprite's coordinate space, so the same pivot lines up.
local function pickupAnim(path, fromFrame, drawTime)
    local g = Gif.load(path)
    local frames = g.frames - fromFrame + 1
    return Animation:new(g.quads, fromFrame, g.frames,
        (drawTime or 0.4) / frames, false, g.image)
end

local Gun = {}
Gun.__index = Gun
setmetatable(Gun, HandItem)

-- Ordered list + factory by id: single source for chest, console, save restore
Gun.ids = { 'usp', 'ak47', 'm4a1', 'shotgun' }

-- Display names by id (chest toasts, wall-buy prompts, console output)
Gun.names = { usp = 'USP-45', ak47 = 'AK-47', m4a1 = 'M4A1', shotgun = 'Shotgun' }

function Gun.newById(id)
    if id == 'sawedoff' then id = 'shotgun' end -- pre-rename saves
    if id == 'usp' then return Gun:newUSP() end
    if id == 'ak47' then return Gun:newAk47() end
    if id == 'm4a1' then return Gun:newM4A1() end
    if id == 'shotgun' then return Gun:newShotgun() end
end

-- gun id -> spritesheet quad name (ids match except the pistol)
function Gun.quadName(id)
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
        kickAng = 0,     -- visual muzzle-rise, 1 = just fired -> 0
        -- shotgun pump-action (rack between shots + on reload-finish / pickup)
        pumpActive = false,
        pumpTimer = 0,      -- secs since the pump started
        pumpDidRack = false,-- rack SFX/eject already fired this pump
        pumpEject = false,  -- whether this pump throws a shell
        pumpAnimTimer = 0,  -- secs left of the pump pose
        reloadSettle = 0,   -- secs left of the ease from reload pose back to aim
        -- sprint pose (gun tucked, horizontal, bobbing) + swing back to aim
        runPose = false,    -- drawing the sprint pose / settling out of it
        runBobT = 0,        -- bob clock while sprinting
        runSettle = 0       -- secs left of the swing from run pose to aim
    }
end

-- Shortest-path angle interpolation (handles the +/-pi wrap).
local function lerpAngle(a, b, t)
    local d = (b - a + math.pi) % (2 * math.pi) - math.pi
    return a + d * t
end

-- All numbers come from tune.lua (t = one entry of TUNE.guns)
local function applyTune(obj, t)
    obj.maxClip = t.clip
    obj.curClip = t.clip
    obj.bulletsLeft = t.reserve or t.clip * 3
    obj.damage = t.damage
    obj.bulletLifeTime = t.bulletLife
    obj.reloadingTime = t.reloadTime
    obj.reloadAnimTime = t.reloadAnimTime -- gif pacing; nil = stretch to reloadTime
    obj.bulletDelay = t.bulletDelay
    obj.spread = t.spread
    obj.pellets = t.pellets
    -- payout numbers ride on every bullet; Enemy:takeDamage spends them
    obj.econ = { hitReward = t.hitReward, killReward = t.killReward,
                 killBonus = t.killBonus }
    obj.maxHits = t.maxHits or 1
    obj.baseSpread = t.baseSpread or 0
    obj.moveSpread = t.moveSpread or 0
    obj.recoilPerShot = t.recoilPerShot or 0
    obj.recoilMax = t.recoilMax or 0
    obj.recoilRecover = t.recoilRecover or 0
    obj.recoilDelay = t.recoilDelay or 0
    obj.drawTime = t.drawTime
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
    obj.pickSfx = 'usp_pick'
    obj.reloadAnim = Animation:fromGif('assets/images/guns/usp_reload.gif', false)
    obj.pickupAnim = pickupAnim('assets/images/guns/usp_reload.gif', 7, obj.drawTime)
    obj.shellQuad = Assets.quads.shell_pistol[1]
    obj.shellDrop = { 'pistol_shell' } -- casing-hit-ground SFX
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
    obj.pickSfx = 'ak47_pick'
    obj.shellQuad = Assets.quads.shell_rifle[1]
    obj.shellDrop = { 'rifle_shell' }
    obj.reloadAnim = Animation:fromGif('assets/images/guns/ak_reload.gif', false)
    obj.pickupAnim = pickupAnim('assets/images/guns/ak_reload.gif', 13, obj.drawTime)
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
    obj.pickSfx = 'm4a1_pick'
    obj.shellQuad = Assets.quads.shell_rifle[1]
    obj.shellDrop = { 'rifle_shell' }
    obj.reloadAnim = Animation:fromGif('assets/images/guns/m4_reload.gif', false)
    obj.pickupAnim = pickupAnim('assets/images/guns/m4_reload.gif', 13, obj.drawTime)
    obj.ox = 12 -- reload gif shares the held sprite's coordinate space, same pivot
    obj.oy = 16
    obj.tipLen = 44

    setmetatable(obj, Gun)
    return obj
end

function Gun:newShotgun()
    local obj = GunStateVariables(TUNE.guns.shotgun.clip)
    applyTune(obj, TUNE.guns.shotgun)

    obj.name = 'Shotgun'
    obj.id = 'shotgun'
    obj.sprite = Assets.quads.held_shotgun[1]
    obj.icon = Assets.quads.shotgun[1]
    obj.type = GUNTYPE.shotgun
    obj.shotSfx = 'shotgun_shot'
    -- no reloadSfx: the reload is just shells going in; the pump is the
    -- shotgun's pick sound (select) and also racks per shot + post-reload
    obj.pickSfx = 'shotgun_pump'
    -- looping shell-insert gif: one cycle per shell (re-synced as each lands)
    obj.reloadAnim = Animation:fromGif('assets/images/guns/shotgun_reload.gif', true)
    obj.shellSfx = { 'shell1', 'shell2', 'shell3' }
    obj.shellQuad = Assets.quads.shell_shotgun[1]
    obj.shellDrop = { 'shell1', 'shell2', 'shell3' } -- brass hull bounce
    obj.reloadOpenTime = TUNE.guns.shotgun.reloadOpenTime
    obj.ox = 12
    obj.oy = 16
    obj.tipLen = 28

    setmetatable(obj, Gun)
    return obj
end

-- Cooldowns that keep ticking even while the gun is holstered (called for
-- every gun the player carries): the fire gate and recoil recovery. The
-- timer carries its overshoot into the next interval — re-zeroing it rounded
-- every shot up to a whole frame and made real fire rate fps-dependent
-- (AK at 60fps fired ~8.6 rps instead of its tuned 10).
function Gun:tickCooldowns(dt)
    -- recoil holds while firing; recovery only starts recoilDelay after the
    -- last shot (otherwise recovery between shots eats every shot's gain)
    self.sinceShot = self.sinceShot + dt
    if self.sinceShot >= self.recoilDelay then
        self.recoil = math.max(0, self.recoil - self.recoilRecover * dt)
    end

    if not self.canShoot then
        self.timer = self.timer + dt
        if self.timer >= self.bulletDelay then
            self.canShoot = true
            self.timer = self.timer - self.bulletDelay
        end
    end
end

function Gun:update(dt, px, py, mx, my)
    HandItem.update(self, dt, px, py, mx, my)

    self:tickCooldowns(dt)

    -- visual kick decays: slide-back fast, muzzle-rise slower (both draw-only)
    local GK = TUNE.gunKick
    self.kickPos = math.max(0, self.kickPos - dt / GK.posTime)
    self.kickAng = math.max(0, self.kickAng - dt / GK.angTime)
    self.reloadSettle = math.max(0, self.reloadSettle - dt)

    -- pickup/draw animation plays out once, then the static sprite returns
    if self.drawingIn and self.pickupAnim then
        self.pickupAnim:update(dt)
        if self.pickupAnim.ended then self.drawingIn = false end
    end

    -- sprint pose (draw-only): while running the gun holds the tucked pose;
    -- once the sprint ends it swings to the real aim over run.settleTime
    if self.owner and self.owner.running then
        self.runPose = true
        self.runBobT = self.runBobT + dt
        self.runSettle = TUNE.run.settleTime
    elseif self.runPose then
        self.runSettle = math.max(0, self.runSettle - dt)
        if self.runSettle <= 0 then
            self.runPose = false
            self.runBobT = 0
        end
    end

    -- shotgun pump: a beat after it starts, play the rack SFX + pose (+ eject)
    if self.pumpActive then
        local SG = TUNE.guns.shotgun
        self.pumpTimer = self.pumpTimer + dt
        if not self.pumpDidRack and self.pumpTimer >= (SG.pumpDelay or 0) then
            self.pumpDidRack = true
            self.pumpAnimTimer = SG.pumpAnimTime or 0
            Audio.playAt('shotgun_pump', self.x, self.y, 1, TUNE.audio.pitchJitter, world)
            if self.pumpEject then self:ejectShell() end
        end
        if self.pumpDidRack then
            self.pumpAnimTimer = math.max(0, self.pumpAnimTimer - dt)
            if self.pumpAnimTimer <= 0 then self.pumpActive = false end
        end
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
                    -- shells start going in now: lock the gif to the cadence
                    if self.reloadAnim then self.reloadAnim:restart() end
                end
            elseif self.reloadTimer >= self.reloadingTime then
                self.reloadTimer = 0
                self.curClip = self.curClip + 1
                self.bulletsLeft = self.bulletsLeft - 1
                if self.reloadAnim then self.reloadAnim:restart() end
                Audio.playAt(self.shellSfx[love.math.random(#self.shellSfx)], self.x, self.y)
                if self.curClip >= self.maxClip or self.bulletsLeft <= 0 then
                    self.reloading = false
                    self.reloadSrc = nil -- done: cancelReload must not stop a later reuse
                    self.reloadSettle = TUNE.gunKick.reloadSettleTime
                    self:pump(false) -- chamber the first shell: rack SFX + pose, no eject
                end
            end
        elseif self.reloadTimer >= self.reloadingTime then
            local moved = math.min(self.maxClip - self.curClip, self.bulletsLeft)
            self.curClip = self.curClip + moved
            self.bulletsLeft = self.bulletsLeft - moved
            self.reloading = false
            self.reloadSrc = nil -- done: cancelReload must not stop a later reuse
            self.reloadTimer = 0
            self.reloadSettle = TUNE.gunKick.reloadSettleTime
        end
    end

    -- pick clack rides the reload SOUND: fires the moment it stops playing
    -- (not the gameplay reload timer). Dies with a swap or a re-reload.
    if self.pickPending then
        local src = self.pickWaitSrc
        if not src or not src:isPlaying() then
            self.pickPending = false
            self.pickWaitSrc = nil
            self:playPick()
        end
    end
end

function Gun:reload()
    if self.reloading or self.curClip >= self.maxClip or self.bulletsLeft <= 0 then
        return
    end
    self.drawingIn = false -- reload pose takes over from a mid-draw animation
    self:cutPick() -- gun goes down: no pick clack (playing or queued) survives
    self.reloading = true
    self.reloadTimer = 0
    self.reloadOpening = self.shellSfx ~= nil
    if self.reloadAnim then
        -- gif plays exactly once, paced by reloadAnimTime (matched to the
        -- reload SFX) when set — otherwise stretched over the reload time.
        -- A shorter gif holds its last frame until the reload actually ends.
        self.reloadAnim:setDuration(self.reloadAnimTime or self.reloadingTime)
        self.reloadAnim:restart()
    end
    if self.reloadSfx then
        self.reloadSrc = Audio.playAt(self.reloadSfx, self.x, self.y)
        -- queue the pick now, chained to the sound itself
        if self.pickSfx and self.reloadSrc then
            self.pickPending = true
            self.pickWaitSrc = self.reloadSrc
        end
    end
end

-- Magazine + reserve back to tuned full: chest refill, /ammo, wall-buy
-- ammo, max-ammo power-up all land here
function Gun:refill()
    self:cancelReload()
    self.curClip = self.maxClip
    self.bulletsLeft = TUNE.guns[self.id].reserve or self.maxClip * 3
end

-- Anything left to top up? (wall-buy refuses to charge for full ammo)
function Gun:ammoFull()
    local full = TUNE.guns[self.id].reserve or self.maxClip * 3
    return self.curClip >= self.maxClip and self.bulletsLeft >= full
end

-- Pick/raise handling sound: gun select, pickup, and after a reload ends.
-- Flat (own-body cue), not positional. Only one pick per gun plays at a time.
function Gun:playPick()
    if not self.pickSfx then return end
    self:cutPick()
    self.pickSrc = Audio.play(self.pickSfx, TUNE.audio.gunPickGain)
end

-- Swapping away kills the pick mid-clack and any pick still waiting on a
-- reload sound to finish
function Gun:cutPick()
    self.pickPending = false
    self.pickWaitSrc = nil
    if self.pickSrc then
        pcall(self.pickSrc.stop, self.pickSrc)
        self.pickSrc = nil
    end
end

function Gun:cancelReload()
    if self.reloading then self.reloadSettle = TUNE.gunKick.reloadSettleTime end
    self.reloading = false
    self.reloadOpening = false
    self.reloadTimer = 0
    -- the queued pick belongs to the reload sound; both die together
    -- (a pick already clacking is left alone — that's the hand's, not the reload's)
    self.pickPending = false
    self.pickWaitSrc = nil
    -- the reload SFX stops with the reload (it used to play out, and a
    -- re-reload layered a second copy on top)
    if self.reloadSrc then
        pcall(self.reloadSrc.stop, self.reloadSrc)
        self.reloadSrc = nil
    end
end

-- Kick a spent casing out of the breech (gun pivot, already near the player).
function Gun:ejectShell()
    if not self.shellQuad then return end
    -- eject "backwards" from the way the player faces: aim right -> shells fly
    -- left, aim left -> shells fly right (screen-horizontal, ignores aim pitch)
    local dirX = (math.cos(self.angle) >= 0) and -1 or 1
    world:addEntity(ShellCasing:new(self.x, self.y, dirX, self.shellQuad, self.shellDrop))
end

-- Deploy visual on select/pickup: replay the pickup animation. The shotgun
-- has no gif tail — it shows its rack pose instead, pose only (the pump SFX
-- already rides the pick sound, so no extra rack sound here).
function Gun:startDraw()
    if self.pickupAnim then
        self.pickupAnim:restart()
        self.drawingIn = true
    elseif self.id == 'shotgun' then
        local SG = TUNE.guns.shotgun
        self.pumpActive = true
        self.pumpTimer = 0
        self.pumpDidRack = true -- straight to the pose, skip the pump SFX beat
        self.pumpEject = false
        self.pumpAnimTimer = SG.pumpAnimTime or 0
    end
end

-- Shotgun rack: schedules the pump SFX + pose (and a shell eject if `ejectShell`)
-- a beat into the window. Used per shot, on reload-finish, and on pickup.
function Gun:pump(ejectShell)
    self.pumpActive = true
    self.pumpTimer = 0
    self.pumpDidRack = false
    self.pumpEject = ejectShell and true or false
    self.pumpAnimTimer = 0
end

function Gun:draw(facingLeft)
    local GK = TUNE.gunKick
    local sign = facingLeft and 1 or -1
    local dx, dy = 0, 0

    -- reload pose: aim squeezed into a ±reloadBandDeg window centered on
    -- reloadUpAngle above horizontal
    local up = math.rad(GK.reloadUpAngle)
    local center = facingLeft and (math.pi + up) or -up
    local frac = math.max(-1, math.min(1, -math.sin(self.angle))) -- +1 aim up, -1 down
    local poseAng = center + sign * math.rad(GK.reloadBandDeg) * frac

    -- normal aim with the per-shot kick (muzzle snaps up, always "up" per facing)
    local aimAng = self.angle + sign * math.rad(GK.angle) * self.kickAng

    local ang
    if self.reloading then
        ang = poseAng
    elseif self.reloadSettle > 0 then
        -- ease from the reload pose back to aim: fast start, gentle land
        local t = 1 - self.reloadSettle / GK.reloadSettleTime
        ang = lerpAngle(poseAng, aimAng, 1 - (1 - t) ^ 3)
    elseif self.runPose then
        -- sprint: horizontal, tucked back toward the player, 1px bob synced
        -- to the bob clock; on sprint end swing to the real aim (fast start)
        local R = TUNE.run
        local runAng = facingLeft and math.pi or 0
        local tuck = (facingLeft and 1 or -1) * R.backPx
        if self.owner and self.owner.running then
            ang = runAng
            dx = tuck
            dy = ((self.runBobT * R.bobHz) % 1 >= 0.5) and -1 or 0
        else
            local t = 1 - self.runSettle / R.settleTime
            local e = 1 - (1 - t) ^ 3
            ang = lerpAngle(runAng, aimAng, e)
            dx = tuck * (1 - e)
        end
    else
        ang = aimAng
        -- whole gun slides straight back along the barrel with the kick
        local back = GK.dist * self.kickPos
        dx = -math.cos(self.angle) * back
        dy = -math.sin(self.angle) * back
    end

    -- reload gif replaces the gun sprite; same transform so the art lines up
    local img, quad = Assets.spritesheet, self.sprite
    if self.reloading and self.reloadAnim then
        local a = self.reloadAnim
        img, quad = a.image, a.quads[a.index]
    elseif self.pumpDidRack and self.pumpAnimTimer > 0 then
        quad = Assets.quads.held_shotgun_pump[1] -- racked pose during the pump
    elseif self.drawingIn and self.pickupAnim and not self.pickupAnim.ended then
        local a = self.pickupAnim
        img, quad = a.image, a.quads[a.index]
    end

    love.graphics.draw(
        img, quad,
        math.floor(self.x + dx), math.floor(self.y + dy),
        ang, 1, facingLeft and -1 or 1, self.ox, self.oy
    )
end

-- 0..1 through the current reload beat (shotguns: the open, then each shell),
-- nil when not reloading
function Gun:reloadProgress()
    if not self.reloading then return nil end
    local dur = self.reloadOpening and (self.reloadOpenTime or 0) or self.reloadingTime
    if dur <= 0 then return 1 end
    return math.min(1, self.reloadTimer / dur)
end

function Gun:drawHud()
    local y = SCREENHEIGHT - 40
    local txt = T('hud.ammo', self.name, self.curClip, self.bulletsLeft)
    love.graphics.print(txt, 20, y)

    -- reloading: a filling bar right of the ammo count (no text swap, so the
    -- readout never jumps and you still see what's in the gun)
    local p = self:reloadProgress()
    if p then
        local H = TUNE.hud
        local x = 20 + font:getWidth(txt) + H.reloadBarGap
        local by = y + (font:getHeight() - H.reloadBarH) / 2
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.rectangle('fill', x, by, H.reloadBarW, H.reloadBarH)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle('fill', x, by, H.reloadBarW * p, H.reloadBarH)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle('line', x + 0.5, by + 0.5, H.reloadBarW - 1, H.reloadBarH - 1)
        love.graphics.setColor(1, 1, 1, 1)
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
        -- hammer clicks on the empty chamber, at the gun's own trigger
        -- cadence (semi: per click, auto: repeats while held, CS-style)
        if self.canShoot and (self.type == GUNTYPE.auto or leftReleased) then
            self.canShoot = false
            Audio.play('dry_fire', TUNE.audio.dryFireGain)
        end
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

        -- hugging a wall the muzzle pokes past it (M4's 44px tip beats a 32px
        -- wall): walk pivot->tip and pull the spawn + flash back to the near
        -- side of the first solid, so nothing fires from inside/behind walls
        local cosA, sinA = math.cos(self.angle), math.sin(self.angle)
        local d = 4
        while d <= gw do
            if world.map:isSolidAt(self.x + cosA * d, self.y + sinA * d) then
                gw = math.max(0, d - 4)
                break
            end
            d = d + 4
        end

        self.canShoot = false
        Audio.playAt(self.shotSfx, self.x, self.y) -- once per trigger pull, not per pellet

        -- low-ammo warning: the hammer click rides the last few shots
        local warn = TUNE.guns[self.id] and TUNE.guns[self.id].lowAmmoClicks
        if warn and self.curClip <= warn then
            Audio.play('dry_fire', TUNE.audio.lowAmmoClickGain)
        end

        -- muzzle juice: flash light + sparks
        local mx = self.x + cosA * gw
        local my = self.y + sinA * gw
        local mb = TUNE.lighting.muzzleBright
        world.lighting:flash(mx, my, mb, mb * 0.8, mb * 0.45,
            TUNE.lighting.muzzleRange, TUNE.lighting.muzzleTime)
        world.vfx:muzzleSparks(mx, my, self.angle)

        -- aim spread pushes the shot (or the whole pellet cone) off center
        local spread = self:currentSpread(self.owner and self.owner.moveFactor or 0)
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
                        self.econ,
                        self.maxHits,
                        i == 1, -- one muzzle-flash anim per blast, not 14 stacked
                        self.owner
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
                    self.econ,
                    self.maxHits,
                    true,
                    self.owner
                )
            )
        end
        self.recoil = math.min(self.recoilMax, self.recoil + self.recoilPerShot)
        self.sinceShot = 0
        self.kickPos = 1 -- slide-back kick on every gun
        if self.type ~= GUNTYPE.auto then -- muzzle-rise only on pistol + shotgun, not ak/m4
            self.kickAng = 1
        end
        self.curClip = self.curClip - 1

        -- casing eject: shotgun throws it on the pump beat, others auto-eject now
        if self.type == GUNTYPE.shotgun then
            self:pump(true)
        else
            self:ejectShell()
        end

        -- shotgun: barrels empty -> break open and reload right away
        if self.shellSfx and self.curClip <= 0 and self.bulletsLeft > 0 then
            self:reload()
        end
    end
end

return Gun