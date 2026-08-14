-- A molotov flying toward the aim point. Same wall-clearing flight as the
-- grenade but no fuse: the bottle shatters where it lands and leaves a
-- FirePatch that does the actual damage over time.

local Entity = require('entities.entity')
local Assets = require('core.assets')
local Audio = require('core.audio')
local FirePatch = require('entities.fire_patch')

local ThrownMolotov = {}
ThrownMolotov.__index = ThrownMolotov
setmetatable(ThrownMolotov, Entity)

function ThrownMolotov:new(x, y, targetX, targetY, owner)
    local obj = Entity:new(x, y, 8, 8)
    obj.type = 'thrown_molotov'
    obj.owner = owner -- carried into the fire patch it leaves behind

    obj.dist = math.max(1, math.sqrt((targetX - x) ^ 2 + (targetY - y) ^ 2))
    obj.dx = (targetX - x) / obj.dist
    obj.dy = (targetY - y) / obj.dist
    obj.travelled = 0
    obj.age = 0
    obj.sprite = Assets.quads.molotov[1]

    setmetatable(obj, ThrownMolotov)
    return obj
end

function ThrownMolotov:update(dt, world)
    self.age = self.age + dt

    -- flies over walls like the grenade; the throw arc clears everything
    local step = TUNE.molotov.throwSpeed * dt
    self.x = self.x + self.dx * step
    self.y = self.y + self.dy * step
    self.travelled = self.travelled + step

    if self.travelled >= self.dist then
        self:shatter(world)
    end
end

function ThrownMolotov:shatter(world)
    world:addEntity(FirePatch:new(self.x, self.y, self.owner))
    -- glass shatter + ignite whoosh
    Audio.playAt('molotov_break', self.x, self.y, TUNE.molotov.breakGain,
        TUNE.audio.pitchJitter, world)
    world:removeEntity(self)
end

function ThrownMolotov:draw()
    local progress = math.min(1, self.travelled / self.dist)
    local arc = math.sin(progress * math.pi) * math.min(24, self.dist * 0.2)

    love.graphics.draw(
        Assets.spritesheet, self.sprite,
        math.floor(self.x), math.floor(self.y - arc),
        self.age * 10, 0.6, 0.6, 16, 16
    )
end

return ThrownMolotov
