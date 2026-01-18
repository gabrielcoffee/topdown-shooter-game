local Player = require('entities.player')
local Color = require('core.color')
local Assets = require('core.assets')

local World = {}
World.__index = World

function World:new()
    local obj = {
        entities = {},
        player = Player:new((SCREENWIDTH/2)/SCALE, (SCREENHEIGHT/2)/SCALE, 32, 32)
    }

    table.insert(obj.entities, obj.player)

    setmetatable(obj, World)
    return obj
end

function World:addEntity(e)
    table.insert(self.entities, e)
end

function World:removeEntity(entity)
    for i = #self.entities, 1, -1 do
        if self.entities[i] == entity then
            table.remove(self.entities, i)
            return
        end
    end
end

function World:update(dt)
    for _, entity in ipairs(self.entities) do
        entity:update(dt, self)
    end
end

function World:draw()
    love.graphics.clear(Color.skyblue())
    love.graphics.push()
    love.graphics.scale(SCALE, SCALE)

    for _, entity in ipairs(self.entities) do
        entity:draw()
    end

    local mx, my = love.mouse.getPosition()
    love.graphics.draw(Assets.spritesheet, Assets.quads.aim[1], (mx/SCALE) - 8, (my/SCALE) - 8)
    love.graphics.pop()
end

return World