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
        camY = 0
    }

    table.insert(obj.entities, obj.player)
    table.insert(obj.entities, Enemy:new(0, 0, 32, 32))

    setmetatable(obj, World)
    return obj
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

function World:update(dt)
    for _, entity in ipairs(self.entities) do
        entity:update(dt, self)
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

    -- HUD DRAWING
    love.graphics.push()
    love.graphics.scale(SCALE, SCALE)

    -- Draws all the HUD INFO
    for _, entity in ipairs(self.entities) do
        entity:drawHud()
    end

    -- Draws the mouse 
    local mx, my = love.mouse.getPosition()
    love.graphics.draw(Assets.spritesheet, Assets.quads.aim[1], (mx/SCALE) - 8, (my/SCALE) - 8)
    love.graphics.pop()
end

return World