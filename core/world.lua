local Player = require('entities.player')
local Color = require('core.color')
local Assets = require('core.assets')
local Enemy = require('entities.enemy')
local Map = require('core.map')
local Crate = require('entities.crate')
local Door = require('entities.door')

local World = {}
World.__index = World

function World:new()
    local levelDef = require('maps.level1')

    local obj = {
        entities = {},
        player = Player:new((SCREENWIDTH/2)/SCALE, (SCREENHEIGHT/2)/SCALE, 32, 32),
        secsForSpawn = 5,
        camX = 0,
        camY = 0,
        map = Map:new(levelDef),
        wave = 1,
        gameOver = false
    }

    -- playable area comes from the level's CSV
    obj.mapW = obj.map.pixelW
    obj.mapH = obj.map.pixelH

    table.insert(obj.entities, obj.player)

    setmetatable(obj, World)

    -- map entities from the level's object layer
    for _, o in ipairs(levelDef.objects or {}) do
        if o.type == 'crate' then
            obj:addEntity(Crate:new(o.x, o.y))
        elseif o.type == 'door' then
            obj:addEntity(Door:new(o.x, o.y, o.price))
        end
    end

    obj:spawnTestZombies()
    return obj
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

-- Debug/test: one of each zombie type around the player (Z key)
function World:spawnTestZombies()
    local px, py = self.player.x, self.player.y
    self:addEntity(Enemy:newSlow(px - 250, py, self.wave))
    self:addEntity(Enemy:newFast(px + 250, py, self.wave))
    self:addEntity(Enemy:newRunner(px, py - 200, self.wave))
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

    -- camera follows the player, clamped to the map edges
    local viewW, viewH = SCREENWIDTH/SCALE, SCREENHEIGHT/SCALE
    self.camX = self.player.x + self.player.width/2 - viewW/2
    self.camY = self.player.y + self.player.height/2 - viewH/2
    self.camX = math.max(0, math.min(self.camX, self.mapW - viewW))
    self.camY = math.max(0, math.min(self.camY, self.mapH - viewH))

    -- player death ends the run
    if self.player.health <= 0 then
        self.gameOver = true
    end
end

function World:draw()

    -- Draws background color
    love.graphics.clear(Color.skyblue())
    love.graphics.push()
    love.graphics.scale(SCALE, SCALE)
    love.graphics.translate(-self.camX, -self.camY)

    -- Draws the tile map
    self.map:draw(self.camX, self.camY)

    -- Draws all the entities
    for _, entity in ipairs(self.entities) do
        entity:draw()
    end

    -- Debug: collision circles on top of everything (H key)
    if showHitboxes then
        for _, entity in ipairs(self.entities) do
            entity:drawHitbox()
        end
    end

    love.graphics.pop()

    -- HUD DRAWING (native resolution, not pixel-scaled)
    for _, entity in ipairs(self.entities) do
        entity:drawHud()
    end

    -- Draws the mouse (crosshair is pixel art, keeps SCALE)
    local mx, my = love.mouse.getPosition()
    love.graphics.draw(Assets.spritesheet, Assets.quads.aim[1], mx - 8*SCALE, my - 8*SCALE, 0, SCALE, SCALE)
end

return World