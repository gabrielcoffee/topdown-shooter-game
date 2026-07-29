local Player = require('entities.player')
local Color = require('core.color')
local Assets = require('core.assets')
local Map = require('core.map')
local Ldtk = require('core.ldtk')
local Audio = require('core.audio')
local Crate = require('entities.crate')
local Door = require('entities.door')
local Chest = require('entities.chest')
local GunWall = require('entities.gun_wall')
local PlayerSpawn = require('entities.player_spawn')
local Lighting = require('core.lighting')
local Vfx = require('core.vfx')
local Waves = require('core.waves')
local Crosshair = require('ui.crosshair')
local GrenadeAim = require('ui.grenade_aim')

local World = {}
World.__index = World

function World:new(opts)
    opts = opts or {}
    local levelDef = Ldtk.load('maps/level1.ldtk')

    local obj = {
        entities = {},
        camX = 0,
        camY = 0,
        map = Map:new(levelDef),
        rooms = levelDef.rooms,
        ambience = levelDef.ambience,
        transition = nil, -- set while the camera pans between rooms
        openedDoors = {}, -- door id -> true once bought (persists in saves)
        visitedRooms = {}, -- room name -> true once entered; gates spawn points
        -- timed power-up buffs, secs left (0 = off)
        buffs = { instakill = 0, freeze = 0, doublepoints = 0, firesale = 0 },
        crateSpawns = {}, -- original crate spots, for the carpenter power-up
        pickupToast = nil, -- { text, t } power-up pickup banner
        kills = 0,        -- zombies downed this run (death screen stat)
        gameOver = false
    }

    -- player starts centered in the first LDtk room
    local r1 = obj.rooms[1]
    obj.player = Player:new(r1.x + r1.w/2 - 16, r1.y + r1.h/2 - 16, 32, 32)
    obj.currentRoom = r1

    -- playable area is the union of every room
    obj.mapW = obj.map.pixelW
    obj.mapH = obj.map.pixelH

    obj.lighting = Lighting.new(obj.map) -- solid tiles + torches from the map
    obj.vfx = Vfx.new()

    table.insert(obj.entities, obj.player)

    setmetatable(obj, World)

    -- map entities from the level's object layer; crates and doors cast shadows
    local spawnPoints = {}
    for _, o in ipairs(levelDef.objects or {}) do
        if o.type == 'crate' then
            local crate = Crate:new(o.x, o.y)
            table.insert(obj.crateSpawns, { x = o.x, y = o.y })
            crate.originIndex = #obj.crateSpawns -- carpenter rebuilds by spot
            obj:addEntity(crate)
            obj.lighting:trackOccluder(crate)
        elseif o.type == 'door' then
            local door = Door:new(o.x, o.y, o.price, o.id, o.width, o.height)
            obj:addEntity(door)
            obj.lighting:trackOccluder(door)
        elseif o.type == 'chest' then
            local chest = Chest:new(o.x, o.y)
            obj:addEntity(chest)
            obj.lighting:trackOccluder(chest)
        elseif o.type == 'gunwall' then
            local wall = GunWall:new(o.x, o.y, o.gun, o.price)
            obj:addEntity(wall)
            obj.lighting:trackOccluder(wall)
        elseif o.type == 'spawn' then
            table.insert(spawnPoints, { x = o.x, y = o.y })
        elseif o.type == 'playerspawn' then
            obj.playerSpawn = PlayerSpawn:new(o.x, o.y)
        end
    end

    -- a PlayerSpawn marker overrides the default room-1-center start
    if obj.playerSpawn then
        obj.player.x, obj.player.y =
            obj.playerSpawn:playerPos(obj.player.width, obj.player.height)
        obj.currentRoom = obj:roomAt(obj.player:getCenter()) or obj.currentRoom
    end
    obj.visitedRooms[obj.currentRoom.name] = true

    -- each spawn point belongs to a room; only visited rooms spawn zombies
    local half = TUNE.tiles.size / 2
    for _, sp in ipairs(spawnPoints) do
        sp.roomName = obj:roomAt(sp.x + half, sp.y + half).name
    end

    obj.waves = Waves:new(spawnPoints)
    obj.waves:hold(TUNE.start.fadeTime, 1) -- banner waits out the run-start fade
    return obj
end

-- Camera centered on (px,py), clamped inside a room; rooms smaller than the
-- view get centered instead
function World:cameraFor(room, px, py)
    local viewW, viewH = SCREENWIDTH/SCALE, SCREENHEIGHT/SCALE
    local cx, cy = px - viewW/2, py - viewH/2
    if room.w <= viewW then cx = room.x + (room.w - viewW)/2
    else cx = math.max(room.x, math.min(cx, room.x + room.w - viewW)) end
    if room.h <= viewH then cy = room.y + (room.h - viewH)/2
    else cy = math.max(room.y, math.min(cy, room.y + room.h - viewH)) end
    return cx, cy
end

-- Fraction of a box's area inside a room
local function roomOverlap(room, bx, by, bw, bh)
    local ox = math.min(bx + bw, room.x + room.w) - math.max(bx, room.x)
    local oy = math.min(by + bh, room.y + room.h) - math.max(by, room.y)
    if ox <= 0 or oy <= 0 then return 0 end
    return (ox * oy) / (bw * bh)
end

-- Room containing a world point (fallback: first room)
function World:roomAt(x, y)
    for _, r in ipairs(self.rooms) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            return r
        end
    end
    return self.rooms[1]
end

-- Starts a Celeste-style transition once enough of the player's hitbox
-- (TUNE.rooms.enterFraction) is inside a room that isn't the current one.
-- Walking back needs the same fraction, so the check can't flip-flop.
function World:checkRoomTransition()
    local inset = TUNE.movement.collisionInset
    local p = self.player
    local bx, by = p.x + inset, p.y + inset
    local bw, bh = p.width - inset*2, p.height - inset*2

    for _, room in ipairs(self.rooms) do
        if room ~= self.currentRoom
            and roomOverlap(room, bx, by, bw, bh) >= TUNE.rooms.enterFraction then

            -- nudge along the player's heading; fallback: dominant axis
            -- toward the new room's center
            local nx, ny = p.vx, p.vy
            local len = math.sqrt(nx*nx + ny*ny)
            if len < 1 then
                nx = (room.x + room.w/2) - (p.x + p.width/2)
                ny = (room.y + room.h/2) - (p.y + p.height/2)
                if math.abs(nx) > math.abs(ny) then ny = 0 else nx = 0 end
                len = math.sqrt(nx*nx + ny*ny)
            end
            nx, ny = nx/len, ny/len

            local nudge = TUNE.rooms.nudgePx
            local toX, toY = self:cameraFor(room,
                p.x + p.width/2 + nx*nudge, p.y + p.height/2 + ny*nudge)

            self.transition = {
                t = 0, room = room,
                fromCamX = self.camX, fromCamY = self.camY,
                toCamX = toX, toCamY = toY,
                playerFromX = p.x, playerFromY = p.y,
                nudgeX = nx*nudge, nudgeY = ny*nudge,
            }
            return
        end
    end
end

-- Tiles blocked by obstacle entities (unopened doors, crates), keyed 'col,row'
-- (for A*). ignoreCrates: crate-breaking zombies path straight through crates
-- and smash whatever actually blocks them; doors/chests always block.
function World:blockedTiles(ignoreCrates)
    local ts = self.map.tileSize
    local blocked = {}
    for _, e in ipairs(self.entities) do
        if e.isObstacle and not e.toRemove
            and not (ignoreCrates and e.type == 'crate') then
            local c0, c1 = math.floor(e.x / ts) + 1, math.floor((e.x + e.width - 1) / ts) + 1
            local r0, r1 = math.floor(e.y / ts) + 1, math.floor((e.y + e.height - 1) / ts) + 1
            for row = r0, r1 do
                for col = c0, c1 do
                    blocked[col .. ',' .. row] = true
                end
            end
        end
    end
    return blocked
end

-- Crate an entity's wall-collision box (padded) is touching, if any.
-- Used by crate-breaking zombies to find what to smash.
function World:getTouchingCrate(ent, pad)
    local bx, by, bw, bh
    if ent.colW then
        bx, by, bw, bh = ent.x + ent.colOX, ent.y + ent.colOY, ent.colW, ent.colH
    else
        bx, by, bw, bh = ent.x, ent.y, ent.width, ent.height
    end
    for _, e in ipairs(self.entities) do
        if e.type == 'crate' and not e.toRemove
            and bx < e.x + e.width + pad and bx + bw > e.x - pad
            and by < e.y + e.height + pad and by + bh > e.y - pad then
            return e
        end
    end
end

-- Door the player's box (padded) is touching, if any
function World:getTouchingDoor(player)
    local pad = TUNE.door.interactPad
    for _, e in ipairs(self.entities) do
        if e.type == 'door' and not e.toRemove
            and player.x < e.x + e.width + pad and player.x + player.width > e.x - pad
            and player.y < e.y + e.height + pad and player.y + player.height > e.y - pad then
            return e
        end
    end
end

-- Chest the player's box (padded) is touching, if any
function World:getTouchingChest(player)
    local pad = TUNE.chest.interactPad
    for _, e in ipairs(self.entities) do
        if e.type == 'chest' and not e.toRemove
            and player.x < e.x + e.width + pad and player.x + player.width > e.x - pad
            and player.y < e.y + e.height + pad and player.y + player.height > e.y - pad then
            return e
        end
    end
end

-- Wall buy the player's box (padded) is touching, if any
function World:getTouchingGunWall(player)
    local pad = TUNE.wallbuy.interactPad
    for _, e in ipairs(self.entities) do
        if e.type == 'gunwall' and not e.toRemove
            and player.x < e.x + e.width + pad and player.x + player.width > e.x - pad
            and player.y < e.y + e.height + pad and player.y + player.height > e.y - pad then
            return e
        end
    end
end

-- Dropped gun the player's box (padded) is touching, if any
function World:getTouchingDroppedGun(player)
    local pad = TUNE.droppedGun.interactPad
    for _, e in ipairs(self.entities) do
        if e.type == 'dropped_gun' and not e.toRemove
            and player.x < e.x + e.width + pad and player.x + player.width > e.x - pad
            and player.y < e.y + e.height + pad and player.y + player.height > e.y - pad then
            return e
        end
    end
end

-- Carpenter power-up: rebuild destroyed crates at their original map spots.
-- Live crates (even pushed away) keep their spot claimed; a spot with a
-- player or zombie standing on it is skipped so nobody gets entombed.
-- Returns how many crates came back.
function World:rebuildCrates()
    local claimed = {}
    for _, e in ipairs(self.entities) do
        if e.type == 'crate' and not e.toRemove and e.originIndex then
            claimed[e.originIndex] = true
        end
    end

    local built = 0
    local ts = TUNE.crate.size
    for i, sp in ipairs(self.crateSpawns) do
        if not claimed[i] then
            local blocked = false
            for _, e in ipairs(self.entities) do
                if (e.type == 'enemy' or e.isPlayer) and not e.toRemove
                    and e.x < sp.x + ts and e.x + e.width > sp.x
                    and e.y < sp.y + ts and e.y + e.height > sp.y then
                    blocked = true
                    break
                end
            end
            if not blocked then
                local crate = Crate:new(sp.x, sp.y)
                crate.originIndex = i
                self:addEntity(crate)
                self.lighting:trackOccluder(crate)
                built = built + 1
            end
        end
    end
    return built
end

-- Buying a door: remember its id (activates linked spawn points), then remove it
function World:openDoor(door)
    if door.id then
        self.openedDoors[door.id] = true
    end
    self:removeEntity(door)
end

function World:addEntity(e)
    table.insert(self.entities, e)
end

function World:removeEntity(entity)
    entity.toRemove = true
end

function World:getEntityCollision(e, type)
    local t = type or 'default'
    for i = #self.entities, 1, -1 do
        if self.entities[i].type == t then
            if e:collidesWith(self.entities[i]) then
                return self.entities[i]
            end
        end
    end
end

-- Pushes two overlapping circle entities half the overlap apart each.
-- Corrections go through Entity:nudge, so walls and obstacles clip them:
-- an entity against a wall stays put and the pair just stays overlapped a
-- little longer, instead of one being shoved through the wall.
local function pushApart(world, a, b)
    local ax, ay = a:getCenter()
    local bx, by = b:getCenter()
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx*dx + dy*dy)
    local overlap = a.radius + b.radius - dist

    if overlap > 0 then
        local nx, ny = 1, 0
        if dist > 0 then nx, ny = dx/dist, dy/dist end
        local half = overlap / 2

        -- a takes its half first; whatever a couldn't move (wall behind it)
        -- is handed to b, so a wall-pinned entity pushes the free one the
        -- full distance instead of the pair sinking toward the wall
        local ax0, ay0 = a.x, a.y
        a:nudge(world, -nx*half, -ny*half)
        local movedA = (ax0 - a.x)*nx + (ay0 - a.y)*ny
        b:nudge(world, nx*(overlap - movedA), ny*(overlap - movedA))
    end
end

function World:update(dt)
    -- Room switch: gameplay freezes while the camera pans and the player
    -- drifts a few px into the new room (Celeste-style)
    if self.transition then
        local tr = self.transition
        tr.t = tr.t + dt
        local k = math.min(1, tr.t / TUNE.rooms.transitionTime)
        local e = 1 - (1 - k)^3 -- cubic ease-out

        self.camX = tr.fromCamX + (tr.toCamX - tr.fromCamX) * e
        self.camY = tr.fromCamY + (tr.toCamY - tr.fromCamY) * e
        self.player.x = tr.playerFromX + tr.nudgeX * e
        self.player.y = tr.playerFromY + tr.nudgeY * e

        self.lighting:update(dt, self) -- torches keep flickering during the pan
        if k >= 1 then
            self.currentRoom = tr.room
            self.visitedRooms[tr.room.name] = true
            self.transition = nil
        end
        return
    end

    -- knife hitstop: everything freezes for a few frames on impact
    if self.hitstop and self.hitstop > 0 then
        self.hitstop = self.hitstop - dt
        return
    end

    -- power-up buff timers run down in real time
    for k, v in pairs(self.buffs) do
        if v > 0 then self.buffs[k] = math.max(0, v - dt) end
    end
    if self.pickupToast then
        self.pickupToast.t = self.pickupToast.t - dt
        if self.pickupToast.t <= 0 then self.pickupToast = nil end
    end

    for _, entity in ipairs(self.entities) do
        entity:update(dt, self)
    end

    -- Zombies never overlap each other, or the player (unless falling)
    for i = 1, #self.entities do
        local a = self.entities[i]
        if a.type == 'enemy' then
            if not self.player.falling then
                pushApart(self, self.player, a)
            end
            for j = i + 1, #self.entities do
                local b = self.entities[j]
                if b.type == 'enemy' then
                    pushApart(self, a, b)
                end
            end
        end
    end

    -- Remove the entities marked toRemove
    for i = #self.entities, 1, -1 do
        if self.entities[i].toRemove == true then
            table.remove(self.entities, i)
        end
    end

    -- wave FSM runs after the sweep so kills count the same frame
    self.waves:update(dt, self)

    -- camera follows the player, locked to the current room; crossing into
    -- another room starts the frozen pan instead
    self:checkRoomTransition()
    if not self.transition then
        local pcx, pcy = self.player:getCenter()
        self.camX, self.camY = self:cameraFor(self.currentRoom, pcx, pcy)
    end

    self.vfx:update(dt)
    self.lighting:update(dt, self)
    Crosshair.update(dt, self)
    GrenadeAim.update(dt)

    -- ears follow the player; reverb adapts to nearby walls; stingers tick
    local lx, ly = self.player:getCenter()
    Audio.setListener(lx, ly, self)
    Audio.update(dt)

    -- player death ends the run
    if self.player.health <= 0 then
        self.gameOver = true
    end

    -- critical health: world ducks, heartbeat runs (off again on death)
    Audio.setLowHealth(self.player.health > 0
        and self.player.health <= TUNE.player.lowHealthThreshold)
end

function World:draw()

    -- Draws background color
    love.graphics.clear(Color.skyblue())

    local camX, camY = self.camX, self.camY
    self.lighting:setView(camX, camY, SCALE)

    -- scene drawn in world coords; lighting darkens + applies lights on top
    self.lighting:draw(function()
        self.map:draw(camX, camY)

        self.vfx:drawUnder() -- ground dust stays below everyone

        -- y-sorted draw: entities lower on screen (bigger sortY) render in
        -- front. Each entity's sortY is its depth anchor (see Entity:sortY).
        -- sortSerial breaks ties so equal-depth sprites don't flicker.
        local drawList = self.drawList or {}
        self.drawList = drawList
        local n = #self.entities
        for i = 1, n do drawList[i] = self.entities[i] end
        for i = #drawList, n + 1, -1 do drawList[i] = nil end
        table.sort(drawList, function(a, b)
            local ay, by = a:sortY(), b:sortY()
            if ay == by then return a.sortSerial < b.sortSerial end
            return ay < by
        end)
        for _, entity in ipairs(drawList) do
            entity:draw()
        end

        self.vfx:draw()

        -- Debug: collision circles on top of everything (H key)
        if showHitboxes then
            for _, entity in ipairs(self.entities) do
                entity:drawHitbox()
            end
            if self.playerSpawn then self.playerSpawn:drawHitbox() end
        end
    end)

    -- HUD DRAWING (native resolution, not pixel-scaled)
    for _, entity in ipairs(self.entities) do
        entity:drawHud()
    end

    -- round counter, top-right
    local round = T('hud.round', self.waves.wave)
    love.graphics.print(round, SCREENWIDTH - 20 - font:getWidth(round), 20)

    -- active power-up buffs stack down the top-left
    local by = 20
    for _, k in ipairs({ 'instakill', 'freeze', 'doublepoints', 'firesale' }) do
        if self.buffs[k] > 0 then
            love.graphics.setColor(1, 0.85, 0.3)
            love.graphics.print(
                T('hud.buff_timer', T('powerup.' .. k), math.ceil(self.buffs[k])),
                20, by)
            by = by + 28
        end
    end
    love.graphics.setColor(1, 1, 1)

    -- power-up pickup banner, fading out
    if self.pickupToast then
        local pt = self.pickupToast
        love.graphics.setColor(1, 0.85, 0.3, math.min(1, pt.t))
        love.graphics.print(pt.text,
            SCREENWIDTH / 2 - font:getWidth(pt.text) / 2, SCREENHEIGHT / 2 - 160)
        love.graphics.setColor(1, 1, 1)
    end

    self.waves:drawBanner()

    -- grenade targeting guides (dotted throw arc + blast circle, world-space)
    GrenadeAim.draw(self)

    -- CS-style crosshair replaces the mouse (opens with spread, see ui/crosshair)
    Crosshair.draw(self)
end

-- Save data for the single run slot: wave + player state.
-- Zombies aren't saved — the wave respawns fresh on load.
function World:serialize()
    return {
        wave = self.waves.wave,
        buffs = self.buffs,
        kills = self.kills,
        openedDoors = self.openedDoors,
        visitedRooms = self.visitedRooms,
        player = self.player:serialize(),
    }
end

function World:restore(data)
    self.kills = data.kills or 0
    if data.buffs then
        for k in pairs(self.buffs) do
            self.buffs[k] = data.buffs[k] or 0
        end
    end
    self.openedDoors = data.openedDoors or {}
    self.visitedRooms = data.visitedRooms or self.visitedRooms
    -- doors bought in the saved run stay open
    for _, e in ipairs(self.entities) do
        if e.type == 'door' and e.id and self.openedDoors[e.id] then
            e.toRemove = true
        end
    end
    self.waves:hold(TUNE.start.fadeTime, data.wave or 1)
    self.player:restore(data.player or {})
    -- saved runs can end in any room
    self.currentRoom = self:roomAt(self.player:getCenter())
    self.visitedRooms[self.currentRoom.name] = true
end

return World