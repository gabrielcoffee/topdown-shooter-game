local Player = require('entities.player')
local Color = require('core.color')
local Assets = require('core.assets')
local Enemy = require('entities.enemy')

local World = {}
World.__index = World

function World:new()
    local obj = {
        entities = {},
        player = Player:new((SCREENWIDTH/2)/SCALE, (SCREENHEIGHT/2)/SCALE, 32, 32),
        secsForSpawn = 5,
        camX = 0,
        camY = 0,
        gameOver = false
    }

    table.insert(obj.entities, obj.player)

    setmetatable(obj, World)
    obj:spawnTestZombies()
    return obj
end

-- Debug/test: one of each zombie type around the player (Z key)
function World:spawnTestZombies()
    local px, py = self.player.x, self.player.y
    self:addEntity(Enemy:newSlow(px - 250, py))
    self:addEntity(Enemy:newFast(px + 250, py))
    self:addEntity(Enemy:newRunner(px, py - 200))
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
            return
        end
    end

    -- updates the camera position
    self.camX = self.player.x - SCREENWIDTH/2/SCALE + self.player.width/2
    self.camY = self.player.y - SCREENHEIGHT/2/SCALE + self.player.height/2

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

    -- Draws the background
    love.graphics.draw(Assets.bg_dust, Assets.quads.bg_dust[1], 0, 0)

    -- Draws all the entities
    for _, entity in ipairs(self.entities) do
        entity:draw()
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