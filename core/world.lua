local Player = require('entities.player')
local Color = require('core.color')
local Assets = require('core.assets')
local Map = require('core.map')
local Crate = require('entities.crate')
local Door = require('entities.door')
local Chest = require('entities.chest')
local Lighting = require('core.lighting')
local Vfx = require('core.vfx')
local Waves = require('core.waves')

local World = {}
World.__index = World

function World:new()
    local levelDef = require('maps.level1')

    local obj = {
        entities = {},
        player = Player:new((SCREENWIDTH/2)/SCALE, (SCREENHEIGHT/2)/SCALE, 32, 32),
        camX = 0,
        camY = 0,
        map = Map:new(levelDef),
        openedDoors = {}, -- door id -> true once bought; gates spawn points
        gameOver = false
    }

    -- playable area comes from the level's CSV
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
            obj:addEntity(crate)
            obj.lighting:trackOccluder(crate)
        elseif o.type == 'door' then
            local door = Door:new(o.x, o.y, o.price, o.id)
            obj:addEntity(door)
            obj.lighting:trackOccluder(door)
        elseif o.type == 'chest' then
            local chest = Chest:new(o.x, o.y)
            obj:addEntity(chest)
            obj.lighting:trackOccluder(chest)
        elseif o.type == 'spawn' then
            table.insert(spawnPoints, { x = o.x, y = o.y, door = o.door })
        end
    end

    obj.waves = Waves:new(spawnPoints)
    obj.waves:startWave(1)
    return obj
end

-- Tiles blocked by unopened doors, keyed 'col,row' (for A*)
function World:blockedTiles()
    local ts = self.map.tileSize
    local blocked = {}
    for _, e in ipairs(self.entities) do
        if e.type == 'door' and not e.toRemove then
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

-- Pushes two overlapping circle entities half the overlap apart each
local function pushApart(a, b)
    local ax, ay = a:getCenter()
    local bx, by = b:getCenter()
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx*dx + dy*dy)
    local overlap = a.radius + b.radius - dist

    if overlap > 0 then
        local nx, ny = 1, 0
        if dist > 0 then nx, ny = dx/dist, dy/dist end
        local half = overlap / 2
        a.x, a.y = a.x - nx*half, a.y - ny*half
        b.x, b.y = b.x + nx*half, b.y + ny*half
    end
end

function World:update(dt)
    for _, entity in ipairs(self.entities) do
        entity:update(dt, self)
    end

    -- Zombies never overlap each other
    for i = 1, #self.entities do
        local a = self.entities[i]
        if a.type == 'enemy' then
            for j = i + 1, #self.entities do
                local b = self.entities[j]
                if b.type == 'enemy' then
                    pushApart(a, b)
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

    -- camera follows the player, clamped to the map edges
    local viewW, viewH = SCREENWIDTH/SCALE, SCREENHEIGHT/SCALE
    self.camX = self.player.x + self.player.width/2 - viewW/2
    self.camY = self.player.y + self.player.height/2 - viewH/2
    self.camX = math.max(0, math.min(self.camX, self.mapW - viewW))
    self.camY = math.max(0, math.min(self.camY, self.mapH - viewH))

    self.vfx:update(dt)
    self.lighting:update(dt, self)

    -- player death ends the run
    if self.player.health <= 0 then
        self.gameOver = true
    end
end

function World:draw()

    -- Draws background color
    love.graphics.clear(Color.skyblue())

    local camX, camY = self.camX, self.camY
    self.lighting:setView(camX, camY, SCALE)

    -- scene drawn in world coords; lighting darkens + applies lights on top
    self.lighting:draw(function()
        self.map:draw(camX, camY)

        for _, entity in ipairs(self.entities) do
            entity:draw()
        end

        self.vfx:draw()

        -- Debug: collision circles on top of everything (H key)
        if showHitboxes then
            for _, entity in ipairs(self.entities) do
                entity:drawHitbox()
            end
        end
    end)

    -- HUD DRAWING (native resolution, not pixel-scaled)
    for _, entity in ipairs(self.entities) do
        entity:drawHud()
    end

    self.waves:drawBanner()

    -- Draws the mouse (crosshair is pixel art, keeps SCALE)
    local mx, my = love.mouse.getPosition()
    love.graphics.draw(Assets.spritesheet, Assets.quads.aim[1], mx - 8*SCALE, my - 8*SCALE, 0, SCALE, SCALE)
end

-- Save data for the single run slot: wave + player state.
-- Zombies aren't saved — the wave respawns fresh on load.
function World:serialize()
    return {
        wave = self.waves.wave,
        openedDoors = self.openedDoors,
        player = self.player:serialize(),
    }
end

function World:restore(data)
    self.openedDoors = data.openedDoors or {}
    -- doors bought in the saved run stay open
    for _, e in ipairs(self.entities) do
        if e.type == 'door' and e.id and self.openedDoors[e.id] then
            e.toRemove = true
        end
    end
    self.waves:startWave(data.wave or 1)
    self.player:restore(data.player or {})
end

return World