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
        dir = 1,
        pingpong = false,
        loop = loop == nil and true or loop,
        ended = false,
        paused = false
    }

    setmetatable(obj, Animation)
    return obj
end

-- Build an animation straight from a .gif file: frames, image and per-frame
-- delays all come from the gif, so no spritesheet sequencing is needed.
-- Example: Animation:fromGif('assets/images/guns/ak_reload.gif')
function Animation:fromGif(path, loop)
    local g = Gif.load(path)
    local anim = Animation:new(g.quads, 1, g.frames, g.delays[1], loop, g.image)
    anim.delays = g.delays -- gif frames can each have their own delay
    return anim
end

function Animation:pause()
    self.paused = true
end

-- Ping-pong: play 1..n then back n-1..2 instead of snapping to frame 1. For
-- 3-frame walk cycles this reads as a real gait; a hard loop pops every cycle.
function Animation:setPingPong(on)
    self.pingpong = on ~= false
    self.dir = 1
    return self
end

function Animation:restart()
    self.timer = 0
    self.index = self.from
    self.turn = 1
    self.dir = 1
    self.ended = false
end

-- Stretch/squeeze the whole animation to last `total` seconds (e.g. sync a
-- reload gif to the gun's tuned reload time).
-- A ping-pong cycle walks the interior frames twice (1,2,3,2 for n=3), so its
-- native length isn't just the sum of the delays.
function Animation:cycleFrames()
    if self.pingpong and self.totalFrames > 1 then
        return (self.totalFrames - 1) * 2
    end
    return self.totalFrames
end

function Animation:setDuration(total)
    if self.delays then
        self.nativeDelays = self.nativeDelays or self.delays
        local native = 0
        for _, d in ipairs(self.nativeDelays) do native = native + d end
        if self.pingpong then
            for i = self.from + 1, self.to - 1 do
                native = native + self.nativeDelays[i]
            end
        end
        local factor = total / native
        local scaled = {}
        for i, d in ipairs(self.nativeDelays) do scaled[i] = d * factor end
        self.delays = scaled
    else
        self.timeBetweenFrames = total / self:cycleFrames()
    end
end

function Animation:update(dt)
    self.timer = self.timer + dt

    if self.ended or self.paused then return end

    -- consume whole frames and carry the remainder — zeroing the timer made
    -- every animation run slower than its tuned duration (the reload gif
    -- lagged the actual reload timer by a few tenths of a second)
    local frameTime = self.delays and self.delays[self.index] or self.timeBetweenFrames
    while self.timer > frameTime do
        self.timer = self.timer - frameTime
        self.index = self.index + self.dir

        if self.pingpong and self.totalFrames > 2 then
            -- bounce off both ends without replaying the end frame twice
            if self.index > self.to then
                self.index, self.dir = self.to - 1, -1
            elseif self.index < self.from then
                if self.loop then
                    self.index, self.dir = self.from + 1, 1
                    self.turn = self.turn + 1
                else
                    self.index, self.dir = self.from, 1
                    self.ended = true
                    return
                end
            end
        elseif self.index > self.to then
            if self.loop then
                self.index = self.from
                self.turn = self.turn + 1
            else
                self.index = self.to
                self.ended = true
                return
            end
        end

        frameTime = self.delays and self.delays[self.index] or self.timeBetweenFrames
        if not frameTime or frameTime <= 0 then return end -- bad delay: don't spin
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