--[[
The MIT License (MIT)

Copyright (c) 2014 Marcus Ihde, Tim Anema

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
local _PACKAGE = string.gsub(...,"%.","/") or ""
if string.len(_PACKAGE) > 0 then _PACKAGE = _PACKAGE .. "/" end
local Light = require(_PACKAGE..'light')
local Body = require(_PACKAGE..'body')
local util = require(_PACKAGE..'util')
local PostShader = require(_PACKAGE..'postshader')

local light_world = {}
light_world.__index = light_world

light_world.image_mask       = util.loadShader(_PACKAGE.."/shaders/image_mask.glsl")
light_world.shadowShader     = util.loadShader(_PACKAGE.."/shaders/shadow.glsl")
-- Refraction and reflection are off in this game, and reflection.glsl loops to
-- a uniform bound, which GLSL ES forbids -- compiling it at require time took
-- the whole browser build down before the first frame. Compiled on first use
-- instead, which for us is never.
local function lazyShader(field, file)
  return function()
    light_world[field] = light_world[field] or util.loadShader(_PACKAGE.."/shaders/"..file)
    return light_world[field]
  end
end
local refractionShader = lazyShader('refractionShader', 'refraction.glsl')
local reflectionShader = lazyShader('reflectionShader', 'reflection.glsl')

local function new(options)
  local obj = {}
  obj.lights = {}
  obj.bodies = {}
  obj.visibleLights = {}
  obj.visibleBodies = {}
  obj.post_shader = PostShader()

  obj.l, obj.t, obj.s      =  0, 0, 1
  obj.ambient              = {0, 0, 0}
  obj.refractionStrength   = 8.0
  obj.reflectionStrength   = 16.0
  obj.reflectionVisibility = 1.0
  obj.shadowBlur           = 2.0
  obj.shadowScale          = 1.0 -- see setShadowScale
  obj.shadowBatch          = {}  -- reused vertex scratch, see drawShadows
  obj.glowBlur             = 1.0
  obj.glowTimer            = 0.0
  obj.glowDown             = false

  obj.disableGlow          = false
  obj.disableMaterial      = false
  obj.disableReflection    = true
  obj.disableRefraction    = true

  options = options or {}
  for k, v in pairs(options) do obj[k] = v end
  for i, v in ipairs(obj.ambient) do if v > 1 then obj.ambient[i] = v / 255 end end

  local world = setmetatable(obj, light_world)
  world:refreshScreenSize()

  return world
end

-- PATCH (chamber9): render the light passes at a fraction of the canvas size.
-- Every visible light costs a full-buffer clear, a stencil pass and a
-- full-buffer shader pass, and that was the entire frame budget in the
-- browser -- 15fps with lighting, a locked 60 without. Light falloff is smooth
-- and upscales cleanly, so the shadow buffers can run at half resolution for a
-- ~4x cut in fragment work. The scene itself (render_buffer) stays full res;
-- only the lighting is downsampled.
function light_world:setShadowScale(k)
  self.shadowScale = math.max(0.1, math.min(1, tonumber(k) or 1))
  if self.w and self.h then self:refreshScreenSize(self.w, self.h) end
end

function light_world:refreshScreenSize(w, h)
  w, h = w or love.graphics.getWidth(), h or love.graphics.getHeight()

  self.w, self.h        = w, h
  self.render_buffer    = love.graphics.newCanvas(w, h) -- the scene: always full res

  -- lighting buffers, possibly downsampled (setShadowScale)
  local k = self.shadowScale or 1
  local bw, bh = math.floor(w * k), math.floor(h * k)
  self.bufW, self.bufH  = bw, bh
  self.shadow_buffer    = love.graphics.newCanvas(bw, bh)
  self.normalMap        = love.graphics.newCanvas(bw, bh)
  self.shadowMap        = love.graphics.newCanvas(bw, bh)
  -- upscaled back to full res at the end of drawShadows; linear keeps the
  -- gradient smooth instead of showing the half-res grid
  self.shadow_buffer:setFilter('linear', 'linear')

  -- the normal map is only rebuilt when a body actually has normals; clear it
  -- once here so the shadow shader always samples something valid
  love.graphics.setCanvas(self.normalMap)
  love.graphics.clear()
  love.graphics.setCanvas()

  -- PATCH (chamber9): glow/material/refraction/reflection are all disabled in
  -- this game (core/lighting.lua), and each of these was a full-size canvas
  -- allocated to never be drawn. Created on demand instead.
  self.glowMap, self.refractionMap, self.reflectionMap = nil, nil, nil

  self.post_shader:refreshScreenSize(w, h)
end

function light_world:update(dt)
  self.visibleBodies = {}
  self.visibleLights = {}
  for i = 1, #self.bodies do
    local body = self.bodies[i]
    body.is_on_screen = body:inRange(-self.l,-self.t,self.w,self.h,self.s)
    if body:isVisible() then
      body:update(dt)
      table.insert(self.visibleBodies, body)
      if body.normalMesh then self.anyNormals = true end
    end
  end
  for i = 1, #self.lights do
    local light = self.lights[i]
    light.is_on_screen = light:inRange(self.l,self.t,self.w,self.h,self.s)
    if light.is_on_screen then
      table.insert(self.visibleLights, light)
    end
  end

  -- PATCH (chamber9): every visible light costs a buffer clear, a stencil pass
  -- and a full-buffer shader pass, so the frame cost is linear in light count.
  -- Keep the ones nearest the middle of the screen (where the player is) and
  -- drop the rest; a torch two rooms over contributes almost nothing.
  local maxLights = self.maxLights
  if maxLights and #self.visibleLights > maxLights then
    local cx, cy = (-self.l + self.w / 2) / self.s, (-self.t + self.h / 2) / self.s
    table.sort(self.visibleLights, function(a, b)
      local ax, ay = a.x - cx, a.y - cy
      local bx, by = b.x - cx, b.y - cy
      return (ax * ax + ay * ay) < (bx * bx + by * by)
    end)
    for i = #self.visibleLights, maxLights + 1, -1 do
      self.visibleLights[i] = nil
    end
  end
end

function light_world:setMaxLights(n)
  self.maxLights = (n and n > 0) and math.floor(n) or nil
end

function light_world:draw(cb)
  -- PATCH (chamber9): remember the caller's render target. The stock code
  -- presented to the screen via drawCanvasToCanvas(canvas, nil), which breaks
  -- when the caller draws inside another canvas chain (moonshine post-fx).
  local target = love.graphics.getCanvas()

  util.drawto(self.render_buffer, self.l, self.t, self.s, false, function()
    cb(self.l,self.t,self.w,self.h,self.s)
    _ = self.disableMaterial   or self:drawMaterial(      self.l,self.t,self.w,self.h,self.s)
    self:drawShadows( self.l,self.t,self.w,self.h,self.s)
    _ = self.disableGlow       or self:drawGlow(          self.l,self.t,self.w,self.h,self.s)
    _ = self.disableRefraction or self:drawRefraction(    self.l,self.t,self.w,self.h,self.s)
    _ = self.disableReflection or self:drawReflection(    self.l,self.t,self.w,self.h,self.s)
  end)

  -- PATCH (chamber9): present into the caller's target instead of the screen.
  -- post_shader effects are unused here; add them back before this draw if needed.
  love.graphics.setCanvas(target)
  love.graphics.push()
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.render_buffer, 0, 0)
  love.graphics.pop()
end

-- draw normal shading
function light_world:drawShadows(l,t,w,h,s)
  -- PATCH (chamber9): the lighting buffers may be smaller than the canvas
  -- (setShadowScale). Everything below draws through this scaled transform, so
  -- geometry, the shader's pixel-space uniforms and the stencil arcs all land
  -- in the same space automatically -- (light.x + lk/sk) * sk is just
  -- (light.x + l/s) * s * k.
  local k = self.shadowScale or 1
  local lk, tk, sk = l * k, t * k, s * k

  -- PATCH (chamber9): body:drawNormal() only draws when a body was given a
  -- normal image, and nothing in this game ever is -- the map is plain
  -- polygons. Rebuilding an always-empty buffer cost two framebuffer binds, a
  -- clear and a pass every frame. It is cleared once at allocation instead,
  -- and only rebuilt if a body with normals ever shows up.
  if self.anyNormals then
    love.graphics.setCanvas( self.normalMap )
    love.graphics.clear()
    love.graphics.setCanvas()
    util.drawto(self.normalMap, lk, tk, sk, false, function()
      for i = 1, #self.visibleBodies do
        self.visibleBodies[i]:drawNormal()
      end
    end)
  end

  self.shadowShader:send('normalMap', self.normalMap)
  self.shadowShader:send("invert_normal", self.normalInvert == true)

  love.graphics.setCanvas( self.shadow_buffer )
  love.graphics.clear()
  love.graphics.setCanvas()
  for i = 1, #self.visibleLights do
    local light = self.visibleLights[i]
    -- create shadow map for this light
    love.graphics.setCanvas( self.shadowMap )
    love.graphics.clear()
    love.graphics.setCanvas()

    util.drawto(self.shadowMap, lk, tk, sk, true, function()
      --I dont know if it uses both or just calls both
      love.graphics.stencil(function()
        local angle = light.direction - (light.angle / 2.0)
        love.graphics.arc("fill", light.x, light.y, light.range, angle, angle + light.angle)
      end)
      love.graphics.setStencilTest("greater",0)
      love.graphics.stencil(function()
        love.graphics.setShader(self.image_mask)
        for k = 1, #self.bodies do
          if self.bodies[k]:inLightRange(light) and self.bodies[k]:isVisible() then
            self.bodies[k]:drawStencil()
          end
        end
        love.graphics.setShader()
      end)
      love.graphics.setStencilTest("equal", 0)
      -- PATCH (chamber9): one mesh for every shadow this light casts, instead
      -- of a polygon() call per silhouette edge per body. This was the whole
      -- cost of lighting in the browser -- 95 draw calls a frame at two lights.
      local batch = self.shadowBatch
      for k = 1, #batch do batch[k] = nil end
      for k = 1, #self.bodies do
        if self.bodies[k]:inLightRange(light) and self.bodies[k]:isVisible() then
          self.bodies[k]:drawShadow(light, batch)
        end
      end
      if #batch > 0 then
        local mesh = self.shadowMesh
        if not mesh or mesh:getVertexCount() < #batch then
          -- grow in steps so a busy frame does not reallocate every time
          local size = math.max(256, 2 ^ math.ceil(math.log(#batch) / math.log(2)))
          mesh = love.graphics.newMesh(size, 'triangles', 'stream')
          self.shadowMesh = mesh
        end
        mesh:setVertices(batch)
        mesh:setDrawRange(1, #batch)
        love.graphics.setColor(1, 1, 1, 1) -- vertex colours carry the real one
        love.graphics.draw(mesh)
      end
    end)

    -- draw scene for this light using normals and shadowmap
    self.shadowShader:send('lightColor', {light.red, light.green, light.blue})
    self.shadowShader:send("lightPosition", {(light.x + lk/sk) * sk, (light.y + tk/sk) * sk, (light.z * 10) / 255})
    self.shadowShader:send('lightRange',light.range * sk)
    self.shadowShader:send("lightSmooth", light.smooth)
    self.shadowShader:send("lightGlow", {1.0 - light.glowSize, light.glowStrength})
    util.drawCanvasToCanvas(self.shadowMap, self.shadow_buffer, {
      blendmode = 'add',
      shader = self.shadowShader,
      stencil = function()
        local angle = light.direction - (light.angle / 2.0)
        love.graphics.arc(
          "fill", (light.x + lk/sk) * sk, (light.y + tk/sk) * sk, light.range * sk, angle, angle + light.angle
        )
      end
    })
  end

  -- add in ambient color
  local blur = self.shadowBlur * k
  util.drawto(self.shadow_buffer, lk, tk, sk, false, function()
    love.graphics.setBlendMode("add")
    love.graphics.setColor({self.ambient[1], self.ambient[2], self.ambient[3]})
    love.graphics.rectangle("fill", -l/s, -t/s, w/s,h/s)

    -- PATCH (chamber9): this buffer is about to be multiplied over the scene,
    -- so its alpha has to be 1 or the world is multiplied away. The blur pass
    -- used to supply that as a side effect of its `vec4(col.rgb, 1.0)`, which
    -- meant two full-buffer blits even at radius 0. With no blur to do, write
    -- the alpha channel directly: one untextured rect, nothing else touched.
    if blur <= 0 then
      love.graphics.setBlendMode("replace")
      love.graphics.setColorMask(false, false, false, true)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", -l/s, -t/s, w/s, h/s)
      love.graphics.setColorMask()
    end
  end)

  if blur > 0 then self.post_shader:drawBlur(self.shadow_buffer, {blur}) end
  util.drawCanvasToCanvas(self.shadow_buffer, self.render_buffer,
    {blendmode = "multiply", scale = 1 / k}) -- back up to full res
  love.graphics.setStencilTest()
end

-- draw material
function light_world:drawMaterial(l,t,w,h,s)
  for i = 1, #self.bodies do
    if self.bodies[i]:isVisible() then
      self.bodies[i]:drawMaterial()
    end
  end
end

-- draw glow
function light_world:drawGlow(l,t,w,h,s)
  if self.glowDown then
    self.glowTimer = math.max(0.0, self.glowTimer - love.timer.getDelta())
  else
    self.glowTimer = math.min(self.glowTimer + love.timer.getDelta(), 1.0)
  end

  if self.glowTimer == 1.0 or self.glowTimer == 0.0 then
    self.glowDown = not self.glowDown
  end

  local has_glow = false
  -- create glow map
  -- allocated on demand: this pass is disabled in this game, and a
  -- full-screen canvas per disabled pass is pure waste (see refreshScreenSize)
  self.glowMap = self.glowMap or love.graphics.newCanvas(self.w, self.h)
  love.graphics.setCanvas( self.glowMap )
  love.graphics.clear()
  love.graphics.setCanvas()
  util.drawto(self.glowMap, l, t, s, false, function()
    for i = 1, #self.bodies do
      if self.bodies[i]:isVisible() and self.bodies[i].glowStrength > 0.0 then
        has_glow = true
        self.bodies[i]:drawGlow()
      end
    end
  end)

  if has_glow then
    self.post_shader:drawBlur(self.glowMap, {self.glowBlur})
    util.drawCanvasToCanvas(self.glowMap, self.render_buffer, {blendmode = "add"})
  end
end
-- draw refraction
function light_world:drawRefraction(l,t,w,h,s)
  -- create refraction map
  -- allocated on demand: this pass is disabled in this game, and a
  -- full-screen canvas per disabled pass is pure waste (see refreshScreenSize)
  self.refractionMap = self.refractionMap or love.graphics.newCanvas(self.w, self.h)
  love.graphics.setCanvas( self.refractionMap )
  love.graphics.clear()
  love.graphics.setCanvas()
  util.drawto(self.refractionMap, l, t, s, false, function()
    for i = 1, #self.bodies do
      if self.bodies[i]:isVisible() then
        self.bodies[i]:drawRefraction()
      end
    end
  end)

  local shader = refractionShader()
  shader:send("backBuffer", self.render_buffer)
  shader:send("refractionStrength", self.refractionStrength)
  util.drawCanvasToCanvas(self.refractionMap, self.render_buffer, {shader = shader})
end

-- draw reflection
function light_world:drawReflection(l,t,w,h,s)
  -- create reflection map
  -- allocated on demand: this pass is disabled in this game, and a
  -- full-screen canvas per disabled pass is pure waste (see refreshScreenSize)
  self.reflectionMap = self.reflectionMap or love.graphics.newCanvas(self.w, self.h)
  love.graphics.setCanvas( self.reflectionMap )
  love.graphics.clear()
  love.graphics.setCanvas()
  util.drawto(self.reflectionMap, l, t, s, false, function()
    for i = 1, #self.bodies do
      if self.bodies[i]:isVisible() then
        self.bodies[i]:drawReflection()
      end
    end
  end)

  local shader = reflectionShader()
  shader:send("backBuffer", self.render_buffer)
  shader:send("reflectionStrength", self.reflectionStrength)
  shader:send("reflectionVisibility", self.reflectionVisibility)
  util.drawCanvasToCanvas(self.reflectionMap, self.render_buffer, {shader = shader})
end

-- new light
function light_world:newLight(x, y, red, green, blue, range)
  self.lights[#self.lights + 1] = Light(x, y, red, green, blue, range)
  return self.lights[#self.lights]
end

function light_world:clear()
  light_world:clearLights()
  light_world:clearBodies()
end

function light_world:setTranslation(l, t, s)
  self.l, self.t, self.s = l or self.l, t or self.t, s or self.s
end

function light_world:setScale(s) self.s = s end
function light_world:clearLights() self.lights = {} end
function light_world:clearBodies() self.bodies = {} end
function light_world:setAmbientColor(red, green, blue)
  self.ambient = {red, green, blue}
  for i, v in ipairs(self.ambient) do if v > 1 then self.ambient[i] = v / 255 end end
end
function light_world:setShadowBlur(blur) self.shadowBlur = blur end
function light_world:setGlowStrength(strength) self.glowBlur = strength end
function light_world:setRefractionStrength(strength) self.refractionStrength = strength end
function light_world:setReflectionStrength(strength) self.reflectionStrength = strength end
function light_world:setReflectionVisibility(visibility) self.reflectionVisibility = visibility end
function light_world:getBodyCount() return #self.bodies end
function light_world:getBody(n) return self.bodies[n] end
function light_world:getLightCount() return #self.lights end
function light_world:getLight(n) return self.lights[n] end
function light_world:newRectangle(...) return self:newBody("rectangle", ...) end
function light_world:newAnimationGrid(...) return self:newBody("animation", ...) end
function light_world:newCircle(...) return self:newBody("circle", ...) end
function light_world:newPolygon(...) return self:newBody("polygon", ...) end
function light_world:newImage(...) return self:newBody("image", ...) end

function light_world:newRefraction(...)
  self.disableRefraction = false
  return self:newBody("refraction", ...)
end
function light_world:newReflection(normal, ...)
  self.disableReflection = false
  return self:newBody("reflection", ...)
end

-- new body
function light_world:newBody(type, ...)
  local id = #self.bodies + 1
  self.bodies[id] = Body(id, type, ...)
  return self.bodies[#self.bodies]
end

function light_world:is_body(target)
  return target.type ~= nil
end

function light_world:is_light(target)
  return target.angle ~= nil
end

function light_world:remove(to_kill)
  if self:is_body(to_kill) then
    for i = 1, #self.bodies do
      if self.bodies[i] == to_kill then
        table.remove(self.bodies, i)
        return true
      end
    end
  elseif self:is_light(to_kill) then
    for i = 1, #self.lights do
      if self.lights[i] == to_kill then
        table.remove(self.lights, i)
        return true
      end
    end
  end

  -- failed to find it
  return false
end

return setmetatable({new = new}, {__call = function(_, ...) return new(...) end})
