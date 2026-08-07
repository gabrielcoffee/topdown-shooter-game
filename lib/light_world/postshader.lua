--[[
The MIT License (MIT)

Copyright (c) 2014 Marcus Ihde

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
--
-- Trimmed down from the upstream version, which scanned shaders/postshaders/
-- and compiled all 18 files at require time. Only the blur is ever used (soft
-- shadow edges), and one bad compile in any of the other 17 took the whole
-- game down at startup. Worse, the stock blurv/blurh looped to a *uniform*
-- bound, which GLSL ES 1.00 forbids -- fine on desktop, fails to compile on
-- WebGL, i.e. the browser build. The taps are now unrolled in Lua instead, so
-- the loop bound is gone entirely and the shader stays valid everywhere.
--
local _PACKAGE = (...):match("^(.+)[%./][^%./]+") or ""
local util = require(_PACKAGE..'/util')

local post_shader = {}
post_shader.__index = post_shader

-- One shader per (axis, radius). Radius comes from TUNE.lighting.shadowBlur and
-- can change when the tune file is reloaded, so build them on demand and keep
-- them; a run only ever touches one or two.
local blurCache = {}

local function blurShader(axis, steps)
  local key = axis .. steps
  if blurCache[key] then return blurCache[key] end

  -- offsets walk along x for 'v', along y for 'h' -- upstream naming, kept so
  -- the call sites below still read the same
  local taps = {}
  for i = 1, steps do
    local off = ('pSize.%s * %d.0'):format(axis == 'v' and 'x' or 'y', i)
    local minus = axis == 'v' and ('vec2(texture_coords.x - %s, texture_coords.y)'):format(off)
                              or  ('vec2(texture_coords.x, texture_coords.y - %s)'):format(off)
    local plus  = axis == 'v' and ('vec2(texture_coords.x + %s, texture_coords.y)'):format(off)
                              or  ('vec2(texture_coords.x, texture_coords.y + %s)'):format(off)
    taps[#taps + 1] = ('    col += Texel(texture, %s);'):format(minus)
    taps[#taps + 1] = ('    col += Texel(texture, %s);'):format(plus)
  end

  local src = ([[
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 pixel_coords) {
    vec2 pSize = vec2(1.0 / love_ScreenSize.x, 1.0 / love_ScreenSize.y);
    vec4 col = Texel(texture, texture_coords);
%s
    col = col / %d.0;
    return vec4(col.r, col.g, col.b, 1.0);
}
]]):format(table.concat(taps, '\n'), steps * 2 + 1)

  blurCache[key] = love.graphics.newShader(src)
  return blurCache[key]
end

local function new()
  local obj = {}
  local class = setmetatable(obj, post_shader)
  class:refreshScreenSize()
  return class
end

function post_shader:refreshScreenSize(w, h)
  w, h = w or love.graphics.getWidth(), h or love.graphics.getHeight()
  self.back_buffer = love.graphics.newCanvas(w, h)
end

-- args[1] = vertical radius in px, args[2] = horizontal (defaults to the same).
-- A radius of 0 is a no-op that still cost two full-screen passes upstream.
function post_shader:drawBlur(canvas, args)
  local v = math.floor(args[1] or 0)
  local h = math.floor(args[2] or args[1] or 0)
  if v > 0 then
    util.process(canvas, {shader = blurShader('v', v), blendmode = "alpha"})
  end
  if h > 0 then
    util.process(canvas, {shader = blurShader('h', h), blendmode = "alpha"})
  end
end

return setmetatable({new = new}, {__call = function(_, ...) return new(...) end})
