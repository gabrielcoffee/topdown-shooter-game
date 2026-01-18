local Assets = require('core.assets')

local Animation = {}
Animation.__index = Animation

function Animation:new(quads, from, to, timeBetweenFrames, loop)
    local obj = {
        timeBetweenFrames = timeBetweenFrames,
        totalFrames = to - from + 1,
        from = from,
        to = to,
        quads = quads,
        index = from,
        timer = 0,
        turn = 1,
        loop = loop or true,
        ended = false,
        paused = false
    }

    setmetatable(obj, Animation)
    return obj
end

function Animation:pause()
    self.paused = true
end

function Animation:restart()
    self.timer = 0
    self.index = self.from
end

function Animation:update(dt)
    self.timer = self.timer + dt

    if self.ended or self.paused then return end
    
    if self.timer > self.timeBetweenFrames then
        self.timer = 0
        self.index = self.index + 1

        if self.index > self.to then
            
            if self.loop then
                self.index = self.from
                self.turn = self.turn + 1
            else
                self.index = self.totalFrames
                self.ended = true
            end
        end
    end
end

function Animation:draw(x, y, r, sx, sy, ox, oy)
    
    love.graphics.draw(
        Assets.spritesheet, self.quads[self.index],
        x, y,
        r,
        sx, sy,
        ox, oy
    )
end

return Animation