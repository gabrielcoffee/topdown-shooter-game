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
local Decor = require('core.decor')
local Decals = require('core.decals')
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
        transition = nil, -- set while the LOCAL player's camera pans between rooms
        -- true once a LAN session owns this world. Kept separate from
        -- #players so a host sitting alone in a lobby already behaves like
        -- co-op instead of flipping rules the moment a friend joins.
        multiplayer = opts.multiplayer or false,
        openedDoors = {}, -- door id -> true once bought (persists in saves)
        visitedRooms = {}, -- room name -> true once entered; gates spawn points
        -- timed power-up buffs, secs left (0 = off)
        buffs = { instakill = 0, freeze = 0, doublepoints = 0, firesale = 0 },
        crateSpawns = {}, -- original crate spots, for the carpenter power-up
        pluggedTiles = {}, -- holes plugged by crates (map edits, saved with the run)
        pickupToast = nil, -- { text, t } power-up pickup banner
        kills = 0,        -- zombies downed this run (death screen stat)
        cheated = false,  -- a chat cheat ran this run: kills/wave records don't save
        gameOver = false
    }

    -- player starts centered in the first LDtk room.
    -- obj.players holds everyone in the run (co-op adds to it); obj.player is
    -- this machine's player, and stays the one the camera, HUD, crosshair and
    -- dev console follow. Solo: players == { player }.
    local r1 = obj.rooms[1]
    obj.player = Player:new(r1.x + r1.w/2 - 16, r1.y + r1.h/2 - 16, 32, 32)
    obj.players = { obj.player }
    obj.player.currentRoom = r1
    obj.currentRoom = r1

    -- playable area is the union of every room
    obj.mapW = obj.map.pixelW
    obj.mapH = obj.map.pixelH

    obj.lighting = Lighting.new(obj.map) -- solid tiles + torches from the map
    obj.decor = Decor.new(obj.map, obj.map.scenery) -- scattered props + torches
    obj.decals = Decals.new(obj.map) -- permanent blood splats on the floor
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
            -- manual id field wins (spawn gating links use it); otherwise the
            -- LDtk iid keeps the door identifiable across saves — without ANY
            -- id an opened door came back locked on Continue
            local door = Door:new(o.x, o.y, o.price, o.id or o.iid, o.width, o.height)
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
        obj.player.currentRoom = obj.currentRoom
    end
    obj.visitedRooms[obj.currentRoom.name] = true

    -- frame the spawn room before the first update, so the first frame's
    -- cursor->world mapping and draw don't use a camera still sitting at 0,0
    obj:snapCamera(obj.player)
    obj.camX, obj.camY = obj.player.camX, obj.player.camY

    -- each spawn point belongs to a room; only visited rooms spawn zombies
    local half = TUNE.tiles.size / 2
    for _, sp in ipairs(spawnPoints) do
        sp.roomName = obj:roomAt(sp.x + half, sp.y + half).name
    end

    obj.waves = Waves:new(spawnPoints)
    obj.waves:hold(TUNE.start.fadeTime, 1) -- banner waits out the run-start fade
    return obj
end

-- Adds a co-op player and puts them in the world. Phase 2 calls this when a
-- peer joins; the selftest uses it to stand up a second player.
function World:addPlayer(x, y)
    if #self.players >= (TUNE.net and TUNE.net.maxPlayers or 4) then return nil end
    local p = Player:new(x, y, 32, 32)
    p.currentRoom = self:roomAt(p:getCenter())
    self:snapCamera(p)
    table.insert(self.players, p)
    self:addEntity(p)
    return p
end

function World:removePlayer(p)
    for i, q in ipairs(self.players) do
        if q == p then table.remove(self.players, i) break end
    end
    p.toRemove = true
end

-- Two different questions, and co-op made them stop having the same answer.
--
--   "up"    = on their feet and able to act. Zombies chase these, waves spawn
--             around these, power-ups and the nightmare bonus pay these.
--   "alive" = up OR bleeding out on the floor. The run ends when this is
--             empty, because a downed player can still be saved.
--
-- Solo, and for anyone who never goes down, the two are identical.
local function isUp(p)
    return not p.toRemove and p.health > 0 and not p.downed and not p.dead
end

function World:upPlayers(out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    for _, p in ipairs(self.players) do
        if isUp(p) then table.insert(out, p) end
    end
    return out
end
World.livePlayers = World.upPlayers -- old name, same question

function World:anyoneAlive()
    for _, p in ipairs(self.players) do
        if not p.toRemove and (isUp(p) or p.downed) then return true end
    end
    return false
end

-- Closest player still on their feet, plus the distance to them. Zombie
-- targeting and contact damage both run off this; solo it always answers
-- with the only player there is. A downed player is deliberately not a
-- target — the horde walking off a body is what makes a revive possible.
function World:nearestPlayer(x, y)
    local best, bestD2
    for _, p in ipairs(self.players) do
        if isUp(p) then
            local px, py = p:getCenter()
            local dx, dy = px - x, py - y
            local d2 = dx*dx + dy*dy
            if not bestD2 or d2 < bestD2 then best, bestD2 = p, d2 end
        end
    end
    return best, bestD2 and math.sqrt(bestD2) or nil
end

-- A player on their feet picked at random (surprise spawns pick who to
-- appear near)
function World:randomLivePlayer()
    local live = self:upPlayers()
    if #live == 0 then return nil end
    return live[love.math.random(#live)]
end

-- A downed teammate within reach of `player`, for the revive hold. Same
-- padded-box shape as the getTouchingX helpers, using TUNE.revive.range.
function World:getNearbyDownedPlayer(player)
    if not player:isUp() then return nil end
    local pad = TUNE.revive.range
    local best, bestD2
    for _, p in ipairs(self.players) do
        if p ~= player and p.downed and not p.toRemove then
            local px, py = p:getCenter()
            local qx, qy = player:getCenter()
            local dx, dy = px - qx, py - qy
            local d2 = dx*dx + dy*dy
            if d2 <= pad*pad and (not bestD2 or d2 < bestD2) then
                best, bestD2 = p, d2
            end
        end
    end
    return best
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

-- Rooms you can walk into RIGHT NOW from the current room: flood the current
-- room's walkable tiles and collect whatever other room the flood spills into.
-- Unopened doors block the flood, so a room that is only geometrically next
-- door (Room_4 behind the $1000 door) does NOT count until it's bought.
-- Result is cached per room name (co-op: players stand in different rooms,
-- so one shared cache would answer for whoever asked first); door buys clear
-- the whole cache.
function World:adjacentRooms(room)
    room = room or self.currentRoom
    self.adjacentCache = self.adjacentCache or {}
    if self.adjacentCache[room.name] then return self.adjacentCache[room.name] end

    local map, ts = self.map, self.map.tileSize
    -- only unopened doors block: crates are temporary and get smashed, they
    -- must not make a room you already walked through look disconnected
    local blocked = {}
    for _, e in ipairs(self.entities) do
        if e.type == 'door' and not e.toRemove then
            local dc0, dc1 = math.floor(e.x / ts) + 1, math.floor((e.x + e.width - 1) / ts) + 1
            local dr0, dr1 = math.floor(e.y / ts) + 1, math.floor((e.y + e.height - 1) / ts) + 1
            for row = dr0, dr1 do
                for col = dc0, dc1 do blocked[col .. ',' .. row] = true end
            end
        end
    end

    -- room name for a tile (nil = void between rooms)
    local function roomNameAt(col, row)
        local x, y = (col - 0.5) * ts, (row - 0.5) * ts
        for _, r in ipairs(self.rooms) do
            if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
                return r.name
            end
        end
    end

    local function walkable(col, row)
        if col < 1 or col > map.cols or row < 1 or row > map.rows then return false end
        if blocked[col .. ',' .. row] then return false end
        local t = map.tileTypes[map.grid[row][col]] or 'ground'
        return t ~= 'solid' and t ~= 'void'
    end

    local c0 = math.floor(room.x / ts) + 1
    local r0 = math.floor(room.y / ts) + 1
    local c1 = math.floor((room.x + room.w - 1) / ts) + 1
    local r1 = math.floor((room.y + room.h - 1) / ts) + 1

    -- BFS seeded with every walkable tile of the current room; expansion stops
    -- at the first tile of another room (so 2-rooms-away never shows up)
    local found, seen, queue = {}, {}, {}
    for row = r0, r1 do
        for col = c0, c1 do
            if walkable(col, row) then
                seen[col .. ',' .. row] = true
                table.insert(queue, { col, row })
            end
        end
    end
    local head = 1
    while head <= #queue do
        local col, row = queue[head][1], queue[head][2]
        head = head + 1
        for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
            local nc, nr = col + d[1], row + d[2]
            local k = nc .. ',' .. nr
            if not seen[k] and walkable(nc, nr) then
                seen[k] = true
                local name = roomNameAt(nc, nr)
                if name and name ~= room.name then
                    found[name] = true -- neighbour room: mark, don't walk it
                end
            end
        end
    end

    self.adjacentCache[room.name] = found
    return found
end

-- Starts a Celeste-style transition once enough of the player's hitbox
-- (TUNE.rooms.enterFraction) is inside a room that isn't their current one.
-- Walking back needs the same fraction, so the check can't flip-flop.
--
-- Co-op: rooms and cameras belong to each player, not to the world. Two
-- players can stand in different rooms and each sees their own. The pan no
-- longer freezes the simulation either -- with independent cameras, one
-- player walking through a doorway would otherwise stop the game for
-- everyone, and leave them standing still in front of a zombie.
function World:checkRoomTransition(p)
    local inset = TUNE.movement.collisionInset
    local bx, by = p.x + inset, p.y + inset
    local bw, bh = p.width - inset*2, p.height - inset*2

    for _, room in ipairs(self.rooms) do
        if room ~= p.currentRoom
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

            p.transition = {
                t = 0, room = room,
                fromCamX = p.camX, fromCamY = p.camY,
                toCamX = toX, toCamY = toY,
                -- solo only: the scripted drift into the new room
                playerFromX = p.x, playerFromY = p.y,
                nudgeX = nx*nudge, nudgeY = ny*nudge,
            }
            return
        end
    end
end

-- Jump a player's camera straight to their room, no ease (spawn, respawn,
-- and restoring a save mid-room)
function World:snapCamera(p)
    p.currentRoom = p.currentRoom or self:roomAt(p:getCenter())
    p.transition = nil
    local pcx, pcy = p:getCenter()
    p.camX, p.camY = self:cameraFor(p.currentRoom, pcx, pcy)
end

-- How long a room pan lasts. Co-op halves it: the pan can't freeze the world
-- there, so a long one leaves the camera sliding while zombies close in.
function World:transitionTime()
    if self:isMultiplayer() then
        return TUNE.rooms.transitionTime * TUNE.rooms.coopTimeMult
    end
    return TUNE.rooms.transitionTime
end

-- More than one player in the run? Solo keeps the original frozen transition;
-- everything co-op-specific hangs off this.
function World:isMultiplayer()
    return self.multiplayer == true or #self.players > 1
end

-- Advance one player's transition. Returns true while it is still running.
function World:advanceTransition(dt, p)
    local tr = p.transition
    tr.t = tr.t + dt
    local k = math.min(1, tr.t / self:transitionTime())
    local e = 1 - (1 - k)^3 -- cubic ease-out, same curve as always
    p.camX = tr.fromCamX + (tr.toCamX - tr.fromCamX) * e
    p.camY = tr.fromCamY + (tr.toCamY - tr.fromCamY) * e
    if k >= 1 then
        p.currentRoom = tr.room
        self.visitedRooms[tr.room.name] = true -- progression stays shared
        self.adjacentCache = nil
        p.transition = nil
        return false
    end
    return true
end

-- One player's camera for this frame: either easing through a room change or
-- locked to their current room. Runs for every player, every frame.
function World:updatePlayerCamera(dt, p)
    if p.transition then
        self:advanceTransition(dt, p)
        return
    end

    self:checkRoomTransition(p)
    if not p.transition then
        local pcx, pcy = p:getCenter()
        p.camX, p.camY = self:cameraFor(p.currentRoom, pcx, pcy)
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

-- Buying a door: remember its id (activates linked spawn points), then remove
-- it — with an unlock clunk and a burst of dust/splinters where it stood
function World:openDoor(door)
    if door.id then
        self.openedDoors[door.id] = true
    end
    local cx, cy = door:getCenter()
    Audio.playAt('door_unlock', cx, cy, 0.9, TUNE.audio.pitchJitter, self)
    self.vfx:doorBurst(cx, cy, door.width / 2, door.height / 2)
    self:removeEntity(door)
    self.adjacentCache = nil -- a new room just became reachable
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
    -- SOLO room switch, unchanged from before co-op: the whole world freezes
    -- while the camera pans and the player drifts a few px into the new room
    -- (Celeste-style). Co-op cannot do this -- one player standing in a
    -- doorway would stop the game for everybody and leave them helpless -- so
    -- there the pan runs alongside the simulation, at coopTimeMult duration,
    -- and nobody gets nudged. See World:updatePlayerCamera.
    if not self:isMultiplayer() and self.player.transition then
        local tr = self.player.transition
        local running = self:advanceTransition(dt, self.player)
        local k = math.min(1, tr.t / self:transitionTime())
        local e = 1 - (1 - k)^3
        self.player.x = tr.playerFromX + tr.nudgeX * e
        self.player.y = tr.playerFromY + tr.nudgeY * e

        self.camX, self.camY = self.player.camX, self.player.camY
        self.currentRoom = self.player.currentRoom
        self.transition = running and tr or nil
        self.lighting:update(dt, self) -- torches keep flickering during the pan
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

    -- Zombies never overlap each other, or any player (unless that one is
    -- falling down a hole)
    for i = 1, #self.entities do
        local a = self.entities[i]
        if a.type == 'enemy' then
            for _, p in ipairs(self.players) do
                -- a downed player is still a body in the way; only a dead
                -- one (spectating until the next wave) stops colliding
                if not p.falling and (p:isUp() or p.downed) then
                    pushApart(self, p, a)
                end
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

    -- every player carries their own camera and room lock; the pan runs
    -- alongside the simulation instead of pausing it
    for _, p in ipairs(self.players) do
        self:updatePlayerCamera(dt, p)
    end
    -- world-level aliases for this machine's view: draw, lighting, audio and
    -- the cursor->world mapping all read these
    self.camX, self.camY = self.player.camX, self.player.camY
    self.currentRoom = self.player.currentRoom
    self.transition = self.player.transition

    self.vfx:update(dt)
    self.lighting:update(dt, self)
    Crosshair.update(dt, self)
    GrenadeAim.update(dt)

    -- ears follow the player; reverb adapts to nearby walls
    -- (Audio.update itself ticks globally from love.update)
    local lx, ly = self.player:getCenter()
    Audio.setListener(lx, ly, self)

    -- The run ends when nobody is left who could still be saved. Solo that
    -- is death at 0 HP; in co-op a player on the floor still counts, so the
    -- run only ends once the last of them has bled all the way out.
    if not self:anyoneAlive() then
        self.gameOver = true
    end

    -- critical health: world ducks, heartbeat runs, red rim stays on screen
    -- (all off again on death or heal)
    local me = self.player
    local critical = me.health > 0
        and me.health <= TUNE.player.lowHealthThreshold
    Audio.setLowHealth(critical or me.downed)
    local Fx = require('ui.fx')
    Fx.setLowHealth(critical)
    -- bleeding out: the rim closes in as the clock runs down, on top of
    -- whatever the hit pulse is doing
    if me.downed then
        local R = TUNE.revive
        local k = 1 - math.max(0, math.min(1, me.bleed / R.bleedOutTime))
        Fx.setBleedout(R.vignetteMin + (R.vignetteMax - R.vignetteMin) * k)
    else
        Fx.setBleedout(0)
    end
end

-- Black out everything outside the room the local player is in.
--
-- The logical canvas follows the window's aspect (see ui/screen.lua), so a
-- 16:9 window shows 853 world px across where 4:3 shows 640. Rooms wider than
-- that genuinely reveal more map, which is the point — but Room_0 is exactly
-- 640 wide, and without a mask a widescreen player would see over its walls
-- into Room_1. Mid-transition the mask spans both rooms, otherwise the room
-- being left would black out under the panning camera.
function World:drawRoomMask()
    local room = self.currentRoom
    if not room then return end

    local x0, y0 = room.x, room.y
    local x1, y1 = room.x + room.w, room.y + room.h
    local tr = self.transition
    if tr and tr.room then
        x0, y0 = math.min(x0, tr.room.x), math.min(y0, tr.room.y)
        x1 = math.max(x1, tr.room.x + tr.room.w)
        y1 = math.max(y1, tr.room.y + tr.room.h)
    end

    -- world -> screen, clamped to the canvas so the bars are never negative
    local sx0 = math.max(0, math.floor((x0 - self.camX) * SCALE))
    local sy0 = math.max(0, math.floor((y0 - self.camY) * SCALE))
    local sx1 = math.min(SCREENWIDTH, math.ceil((x1 - self.camX) * SCALE))
    local sy1 = math.min(SCREENHEIGHT, math.ceil((y1 - self.camY) * SCALE))

    love.graphics.setColor(Color.void())
    if sx0 > 0 then love.graphics.rectangle('fill', 0, 0, sx0, SCREENHEIGHT) end
    if sx1 < SCREENWIDTH then
        love.graphics.rectangle('fill', sx1, 0, SCREENWIDTH - sx1, SCREENHEIGHT)
    end
    if sy0 > 0 then
        love.graphics.rectangle('fill', sx0, 0, sx1 - sx0, sy0)
    end
    if sy1 < SCREENHEIGHT then
        love.graphics.rectangle('fill', sx0, sy1, sx1 - sx0, SCREENHEIGHT - sy1)
    end
    love.graphics.setColor(Color.white())
end

function World:draw()

    -- Whatever the scene doesn't cover. Void-black, never a color: the light
    -- passes are sized to the logical canvas and any mismatch used to show
    -- through here as a bright blue band along an edge.
    love.graphics.clear(Color.void())

    local camX, camY = self.camX, self.camY
    self.lighting:setView(camX, camY, SCALE)

    -- scene drawn in world coords; lighting darkens + applies lights on top
    self.lighting:draw(function()
        self.map:draw(camX, camY)
        self.decals:draw() -- dried blood sits on the dirt, under the grass
        self.decor:draw(self) -- grass, rocks, torches: above the dirt, under everyone

        self.vfx:drawUnder() -- ground dust stays below everyone

        -- y-sorted draw: entities lower on screen (bigger sortY) render in
        -- front. Each entity's sortY is its depth anchor (see Entity:sortY).
        -- sortSerial breaks ties so equal-depth sprites don't flicker.
        -- Only entities near the camera make the list: off-screen rooms
        -- neither sort nor draw.
        local m = TUNE.render.cullMargin
        local x0, y0 = camX - m, camY - m
        local x1 = camX + SCREENWIDTH / SCALE + m
        local y1 = camY + SCREENHEIGHT / SCALE + m
        local drawList = self.drawList or {}
        self.drawList = drawList
        local n = 0
        for i = 1, #self.entities do
            local e = self.entities[i]
            if e.x + e.width >= x0 and e.x <= x1
                and e.y + e.height >= y0 and e.y <= y1 then
                n = n + 1
                drawList[n] = e
            end
        end
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

    -- On a window wider than 4:3 the view is wider than some rooms, so without
    -- this you would see straight into the room next door through its wall.
    self:drawRoomMask()

    -- HUD DRAWING (native resolution, not pixel-scaled)
    for _, entity in ipairs(self.entities) do
        entity:drawHud()
    end

    -- round counter, top-right
    local round = T('hud.round', self.waves.wave)
    love.graphics.print(round, SCREENWIDTH - 20 - font:getWidth(round), 20)

    -- active power-up buffs stack down the top-left: icon, then the timer,
    -- text blinking through the buff's last seconds (icon holds steady)
    local P = TUNE.powerups
    local by = 20
    for _, k in ipairs({ 'instakill', 'freeze', 'doublepoints', 'firesale' }) do
        local v = self.buffs[k]
        if v > 0 then
            require('entities.powerup').drawIcon(
                k, 20 + 11, by + font:getHeight() / 2, 0.8)
            local blinkOff = v <= (P.hudBlinkTime or 0)
                and math.floor(v / (P.hudBlinkInterval or 0.25)) % 2 == 1
            if not blinkOff then
                love.graphics.setColor(1, 0.85, 0.3)
                love.graphics.print(
                    T('hud.buff_timer', T('powerup.' .. k), math.ceil(v)),
                    20 + 28, by)
            end
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

-- Save data for the single run slot: a full snapshot — wave FSM, player
-- (position included), live zombies, crates as they stand, chest mid-spin,
-- ground loot, burning fire and map edits. Loading puts the run back exactly
-- where it was. In-flight projectiles (bullets, thrown grenades) are the one
-- thing skipped: sub-second lifetimes, not worth the surface.
function World:serialize()
    local zombies, crates, chests = {}, {}, {}
    local droppedGuns, powerups, firePatches = {}, {}, {}
    for _, e in ipairs(self.entities) do
        if e.toRemove then
            -- dying this frame: not part of the snapshot
        elseif e.type == 'enemy' and e.health > 0 then
            table.insert(zombies, e:serialize())
        elseif e.type == 'crate' then
            table.insert(crates, {
                x = e.x, y = e.y, health = e.health, originIndex = e.originIndex,
            })
        elseif e.type == 'chest' then
            table.insert(chests, e:serialize())
        elseif e.type == 'dropped_gun' then
            table.insert(droppedGuns, {
                x = e.x, y = e.y, life = e.life,
                gun = { id = e.gun.id, curClip = e.gun.curClip,
                        bulletsLeft = e.gun.bulletsLeft },
            })
        elseif e.type == 'powerup' then
            local cx, cy = e:getCenter()
            table.insert(powerups, { x = cx, y = cy, kind = e.kind, life = e.life })
        elseif e.type == 'fire_patch' then
            local cx, cy = e:getCenter()
            table.insert(firePatches, { x = cx, y = cy, age = e.age,
                tickTimer = e.tickTimer })
        end
    end
    return {
        wave = self.waves.wave, -- kept so older builds can still read the file
        waves = self.waves:serialize(),
        buffs = self.buffs,
        kills = self.kills,
        cheated = self.cheated,
        openedDoors = self.openedDoors,
        visitedRooms = self.visitedRooms,
        pluggedTiles = self.pluggedTiles,
        zombies = zombies,
        crates = crates,
        chests = chests,
        droppedGuns = droppedGuns,
        powerups = powerups,
        firePatches = firePatches,
        chestBag = self.chestBag,
        player = self.player:serialize(),
    }
end

function World:restore(data)
    local Enemy = require('entities.enemy')
    local DroppedGun = require('entities.dropped_gun')
    local Powerup = require('entities.powerup')
    local FirePatch = require('entities.fire_patch')
    local Gun = require('hand_items.gun')

    self.kills = data.kills or 0
    self.cheated = data.cheated or false
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

    -- holes plugged by crates are ground again
    self.pluggedTiles = data.pluggedTiles or {}
    for _, t in ipairs(self.pluggedTiles) do
        self.map:setTile(t.col, t.row, self.map.groundFillId)
    end

    -- full-snapshot saves replace the map's default crates with the saved
    -- set: pushed crates keep their spot, chewed ones their health, smashed
    -- ones stay gone (old saves without the list keep the fresh layout)
    if data.crates then
        for _, e in ipairs(self.entities) do
            if e.type == 'crate' then e.toRemove = true end
        end
        for _, c in ipairs(data.crates) do
            local crate = Crate:new(c.x, c.y)
            crate.health = math.min(c.health or crate.health, crate.health)
            crate.originIndex = c.originIndex
            self:addEntity(crate)
            self.lighting:trackOccluder(crate)
        end
    end

    -- live zombies come back exactly where they stood
    local waveNum = (data.waves and data.waves.wave) or data.wave or 1
    for _, z in ipairs(data.zombies or {}) do
        self:addEntity(Enemy.fromSave(z, waveNum))
    end

    -- mystery-box card bag comes back as saved (no save-scum reshuffles);
    -- cards whose kind left the tune since are dropped, an emptied bag = fresh
    if data.chestBag and data.chestBag.cards then
        local cards = {}
        for _, kind in ipairs(data.chestBag.cards) do
            if TUNE.chest.bagCards[kind] then table.insert(cards, kind) end
        end
        if #cards > 0 then
            self.chestBag = { cards = cards, draws = data.chestBag.draws or 0 }
        end
    end

    -- chest mid-spin / gun-on-the-lid state (matched by map position)
    for _, cd in ipairs(data.chests or {}) do
        for _, e in ipairs(self.entities) do
            if e.type == 'chest' and e.x == cd.x and e.y == cd.y then
                e:restoreState(cd)
            end
        end
    end

    -- ground loot: dropped guns and power-up drops, lifetimes still ticking
    for _, d in ipairs(data.droppedGuns or {}) do
        local gun = d.gun and Gun.newById(d.gun.id)
        if gun then
            -- same clamp as the player's guns: never restore past current tune
            gun.curClip = math.max(0, math.min(d.gun.curClip or gun.curClip, gun.maxClip))
            gun.bulletsLeft = math.max(0, d.gun.bulletsLeft or gun.bulletsLeft)
            local dg = DroppedGun:new(d.x, d.y, gun)
            dg.life = math.min(d.life or dg.life, TUNE.droppedGun.lifetime)
            self:addEntity(dg)
        end
    end
    for _, p in ipairs(data.powerups or {}) do
        local pu = Powerup:new(p.x, p.y, p.kind)
        pu.life = math.min(p.life or pu.life, TUNE.powerups.lifetime)
        self:addEntity(pu)
    end

    -- molotov fire still burning (light + flames rebuild on first update)
    for _, f in ipairs(data.firePatches or {}) do
        local fp = FirePatch:new(f.x, f.y)
        fp.age = f.age or 0
        if f.tickTimer then fp.tickTimer = f.tickTimer end
        self:addEntity(fp)
    end

    -- wave FSM resumes mid-wave (state, timers, zombies still owed); old
    -- saves without the block restart their wave from the top
    if data.waves then
        self.waves:restore(data.waves)
    else
        self.waves:hold(TUNE.start.fadeTime, data.wave or 1)
    end

    self.player:restore(data.player or {})
    -- saved runs can end in any room
    self.currentRoom = self:roomAt(self.player:getCenter())
    self.player.currentRoom = self.currentRoom
    self:snapCamera(self.player)
    self.camX, self.camY = self.player.camX, self.player.camY
    self.visitedRooms[self.currentRoom.name] = true
    self.adjacentCache = nil
end

return World