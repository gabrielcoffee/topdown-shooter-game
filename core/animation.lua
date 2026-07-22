local Assets = require('core.assets')
local Gif = require('core.gif')

local Animation = {}
Animation.__index = Animation

function Animation:new(quads, from, to, timeBetweenFrames, loop, image)
    local obj = {
        timeBetweenFrames = timeBetweenFrames,
        totalFrames = to - from + 1,
        from = from,
        to = to,
        quads = quads,
        image = image or Assets.spritesheet,
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

-- Build an animation straight from a .gif file: frames, image and per-frame
-- delays all come from the gif, so no spritesheet sequencing is needed.
-- Example: Animation:fromGif('assets/images/ak_held.gif')
function Animation:fromGif(path, loop)
    local g = Gif.load(path)
    local anim = Animation:new(g.quads, 1, g.frames, g.delays[1], loop, g.image)
    anim.delays = g.delays -- gif frames can each have their own delay
    return anim
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

    local frameTime = self.delays and self.delays[self.index] or self.timeBetweenFrames
    if self.timer > frameTime then
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
        self.image, self.quads[self.index],
        x, y,
        r,
        sx, sy,
        ox, oy
    )
end

return Animation