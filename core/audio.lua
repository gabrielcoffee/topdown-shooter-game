-- Audio brain: pooled SFX + positional ("surround") playback + wall-driven
-- reverb + occlusion muffling + ambience beds with sparse stingers.
--
-- Positional rules (OpenAL via LÖVE):
--   * only MONO files pan/attenuate — every world sound ships mono
--   * Audio.playAt(name, x, y)  = world sound at a position
--   * Audio.play(name)          = UI/flat sound, pinned to the listener
-- Names that end in digits auto-form variation groups: flesh_hit1..3 can all
-- be played as 'flesh_hit' (random member). Files dropped into the scanned
-- dirs (footsteps/, ambient/, zombies/) register themselves by filename, so
-- Gabriel's future zombie recordings just need the right names.

local Audio = {}

Audio.master = 1
Audio.sfx = 1
Audio.music = 1

-- explicit registry (weapons/effects keep curated names)
local files = {
    -- gun shots: ONE sound per gun, no variations
    usp_shot       = 'assets/sounds/weapons/usp_shot.wav',
    ak47_shot      = 'assets/sounds/weapons/ak47_shot.wav',
    m4a1_shot      = 'assets/sounds/weapons/m4a1_shot.wav',
    shotgun_shot   = 'assets/sounds/weapons/shotgun_shot.wav',
    -- draw/pickup clicks (CS-style deploy)
    gun_draw       = 'assets/sounds/weapons/gun_draw.wav',
    grenade_draw   = 'assets/sounds/weapons/grenade_draw.wav',
    -- reload handling
    usp_reload     = 'assets/sounds/weapons/usp_reload.wav',
    ak47_reload    = 'assets/sounds/weapons/ak47_reload.wav',
    m4a1_reload    = 'assets/sounds/weapons/m4a1_reload.wav',
    shotgun_reload = 'assets/sounds/weapons/shotgun_reload.wav',
    shotgun_pump   = 'assets/sounds/weapons/shotgun_pump.wav',
    shell1         = 'assets/sounds/weapons/shell1.wav',
    shell2         = 'assets/sounds/weapons/shell2.wav',
    shell3         = 'assets/sounds/weapons/shell3.wav',
    rifle_shell    = 'assets/sounds/weapons/rifle_shell.wav',  -- ak/m4 casing hit
    pistol_shell   = 'assets/sounds/weapons/pistol_shell.wav', -- usp casing hit
    -- impacts
    bullet_hit1    = 'assets/sounds/effects/bullet_hit1.wav',
    bullet_hit2    = 'assets/sounds/effects/bullet_hit2.wav',
    flesh_hit1     = 'assets/sounds/effects/flesh_hit1.wav',
    flesh_hit2     = 'assets/sounds/effects/flesh_hit2.wav',
    flesh_hit3     = 'assets/sounds/effects/flesh_hit3.wav',
    knife_swing1   = 'assets/sounds/effects/knife_swing1.wav',
    knife_swing2   = 'assets/sounds/effects/knife_swing2.wav',
    knife_hit1     = 'assets/sounds/effects/knife_hit1.wav',
    knife_hit2     = 'assets/sounds/effects/knife_hit2.wav',
    grenade_blast  = 'assets/sounds/effects/grenade_blast.wav',
}

-- dirs scanned at load: every audio file registers by its bare name
local scanDirs = {
    'assets/sounds/footsteps',
    'assets/sounds/ambient',
    'assets/sounds/zombies',
}

local pools = {}      -- name -> { Source, ... }
local groups = {}     -- base name -> { member names } (name123 -> name)
local srcGain = {}    -- Source -> per-play gain (for live volume updates)
setmetatable(srcGain, { __mode = 'k' })
local srcNoFade = {}  -- Source -> true: this play ignores the run-start fade (UI cues)
setmetatable(srcNoFade, { __mode = 'k' })

-- run-start fade-in: multiplies every gameplay volume, rises 0 -> 1 over dur
local fade = { mult = 1, t = 0, dur = 0 }

local effectsOk = false
local listener = { x = 0, y = 0 }        -- world px, for occlusion + stingers
local reverb = { wet = 0, decay = 0.5, timer = 0 }
local ambience = { bed = nil, set = nil, stingerTimer = 0 }

local function registerGroup(name)
    local base = name:match('^(.-)%d+$')
    if base and base ~= '' then
        groups[base] = groups[base] or {}
        table.insert(groups[base], name)
    end
end

function Audio.load()
    for name, path in pairs(files) do
        if love.filesystem.getInfo(path) then
            pools[name] = { love.audio.newSource(path, 'static') }
            registerGroup(name)
        end
    end

    for _, dir in ipairs(scanDirs) do
        for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
            local name = file:match('^(.+)%.%w+$')
            local ext = file:match('%.(%w+)$')
            if name and (ext == 'ogg' or ext == 'wav' or ext == 'mp3')
                and not name:find('_bed') then -- beds are streamed on demand
                pools[name] = { love.audio.newSource(dir .. '/' .. file, 'static') }
                registerGroup(name)
            end
        end
    end

    love.audio.setDistanceModel('inverseclamped')

    -- reverb effect; every world sound sends into it. Guarded: game must run
    -- fine without OpenAL EFX
    effectsOk = love.audio.isEffectsSupported and love.audio.isEffectsSupported()
    if effectsOk then
        local A = TUNE.audio
        reverb.decay = A.reverbDecayMin
        reverb.wet = A.reverbGainMin
        effectsOk = pcall(love.audio.setEffect, 'room',
            { type = 'reverb', decaytime = reverb.decay, gain = reverb.wet })
    end
    print('[audio] EFX reverb: ' .. (effectsOk and 'on' or 'unsupported, skipping'))
end

-- group name -> random member; plain name -> itself
local function resolve(name)
    local g = groups[name]
    if g then return g[love.math.random(#g)] end
    return name
end

-- A new play must ALWAYS get a voice (rapid AK fire never goes silent).
-- Free source first, grow the pool to poolSize, then steal the play that's
-- closest to finishing — standard channel-stealing, what CS/Source does.
local function grabSource(name)
    local pool = pools[name]
    if not pool then return nil end
    for _, s in ipairs(pool) do
        if not s:isPlaying() then return s end
    end
    if #pool < TUNE.audio.poolSize then
        local src = pool[1]:clone()
        table.insert(pool, src)
        return src
    end
    local best, bestLeft
    for _, s in ipairs(pool) do
        local left = s:getDuration('seconds') - s:tell('seconds')
        if not bestLeft or left < bestLeft then best, bestLeft = s, left end
    end
    best:stop()
    return best
end

-- Straight walk over the tile grid: is a solid wall between a and b?
local function wallBetween(map, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return false end
    local steps = math.ceil(dist / 16) -- half-tile sampling
    for i = 1, steps - 1 do
        local t = i / steps
        if map:isSolidAt(ax + dx * t, ay + dy * t) then return true end
    end
    return false
end

-- Flat sound pinned to the listener (menus, own-body cues).
-- noFade: plays at full volume even during the run-start fade (start cue).
function Audio.play(name, gain, noFade)
    local src = grabSource(resolve(name))
    if not src then return end

    if src:getChannelCount() == 1 then
        src:setRelative(true)
        src:setPosition(0, 0, 0)
        src:setFilter()
    end
    src:setPitch(1)
    srcGain[src] = gain or 1
    srcNoFade[src] = noFade or nil
    src:setVolume(Audio.master * Audio.sfx * (gain or 1) * (noFade and 1 or fade.mult))
    src:play()
end

-- World sound at a position: pans, attenuates, echoes, muffles behind walls.
-- jitter (optional) randomizes pitch by ±jitter — keeps repeats organic.
function Audio.playAt(name, x, y, gain, jitter, world)
    local src = grabSource(resolve(name))
    if not src then return end
    local A = TUNE.audio

    if src:getChannelCount() == 1 then
        src:setRelative(false)
        src:setPosition(x / A.pxPerUnit, y / A.pxPerUnit, 0)
        src:setAttenuationDistances(A.refDist, A.maxDist)

        -- muffle when a wall stands between the sound and the ear
        world = world or _G.world
        if world and world.map
            and wallBetween(world.map, listener.x, listener.y, x, y) then
            src:setFilter({ type = 'lowpass', volume = 1, highgain = A.occlusionHighgain })
        else
            src:setFilter()
        end
        if effectsOk then pcall(src.setEffect, src, 'room') end
    end

    src:setPitch(jitter and (1 + (love.math.random() * 2 - 1) * jitter) or 1)
    srcGain[src] = gain or 1
    srcNoFade[src] = nil
    src:setVolume(Audio.master * Audio.sfx * (gain or 1) * fade.mult)
    src:play()
end

-- Once per frame from World:update: moves the ears + adapts the room reverb
-- to how boxed-in the surroundings are
function Audio.setListener(x, y, world)
    listener.x, listener.y = x, y
    local A = TUNE.audio
    love.audio.setPosition(x / A.pxPerUnit, y / A.pxPerUnit, A.listenerHeight)

    if not effectsOk then return end
    reverb.timer = reverb.timer - love.timer.getDelta()
    if reverb.timer > 0 then return end
    reverb.timer = A.reverbUpdateInterval

    -- wall density in a box around the listener
    local ts = world.map.tileSize
    local r = A.reverbRadius
    local solid, total = 0, 0
    for row = -r, r do
        for col = -r, r do
            total = total + 1
            if world.map:isSolidAt(x + col * ts, y + row * ts) then
                solid = solid + 1
            end
        end
    end
    local density = solid / total

    -- ease toward the target so rooms fade in, never snap
    local k = 1 - math.exp(-A.reverbSmooth * A.reverbUpdateInterval)
    local targetDecay = A.reverbDecayMin + (A.reverbDecayMax - A.reverbDecayMin) * density
    local targetWet = A.reverbGainMin + (A.reverbGainMax - A.reverbGainMin) * density
    reverb.decay = reverb.decay + (targetDecay - reverb.decay) * k
    reverb.wet = reverb.wet + (targetWet - reverb.wet) * k
    pcall(love.audio.setEffect, 'room',
        { type = 'reverb', decaytime = reverb.decay, gain = reverb.wet })
end

-- Looping background bed for the level ('cave', 'forest', 'desert')
function Audio.playAmbience(set)
    Audio.stopAmbience()
    local path = 'assets/sounds/ambient/' .. set .. '_bed.ogg'
    if not love.filesystem.getInfo(path) then return end
    ambience.set = set
    ambience.bed = love.audio.newSource(path, 'stream')
    ambience.bed:setLooping(true)
    ambience.bed:setVolume(Audio.master * Audio.music * TUNE.audio.bedGain * fade.mult)
    ambience.bed:play()
    ambience.stingerTimer = love.math.random(TUNE.audio.stingerMin, TUNE.audio.stingerMax)
end

function Audio.stopAmbience()
    if ambience.bed then ambience.bed:stop() end
    ambience.bed, ambience.set = nil, nil
end

-- Re-apply every live volume from the current master/sfx/music + fade state
local function applyVolumes()
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() and not srcNoFade[s] then
                s:setVolume(Audio.master * Audio.sfx * (srcGain[s] or 1) * fade.mult)
            end
        end
    end
    if ambience.bed then
        ambience.bed:setVolume(Audio.master * Audio.music * TUNE.audio.bedGain * fade.mult)
    end
end

-- Run-start fade: everything audible rises from silence over dur secs.
-- Sounds played mid-fade start at the faded volume and rise with the rest.
function Audio.fadeIn(dur)
    fade.t, fade.dur, fade.mult = 0, dur or 1, 0
    applyVolumes()
end

-- Back to instant full volume (menu return kills a half-done fade)
function Audio.cancelFade()
    fade.t, fade.dur, fade.mult = 0, 0, 1
end

-- Sparse one-shot stingers, placed in the world around the player so the
-- ambience feels alive without getting annoying
function Audio.update(dt)
    if fade.mult < 1 and fade.dur > 0 then
        fade.t = fade.t + dt
        fade.mult = math.min(1, fade.t / fade.dur)
        applyVolumes()
    end

    if not ambience.set then return end
    ambience.stingerTimer = ambience.stingerTimer - dt
    if ambience.stingerTimer > 0 then return end
    local A = TUNE.audio
    ambience.stingerTimer = A.stingerMin + love.math.random() * (A.stingerMax - A.stingerMin)

    if not groups[ambience.set .. '_st'] then return end
    local ang = love.math.random() * math.pi * 2
    local dist = (2 + love.math.random() * 4) * A.pxPerUnit -- just off-screen-ish
    Audio.playAt(ambience.set .. '_st',
        listener.x + math.cos(ang) * dist, listener.y + math.sin(ang) * dist,
        A.stingerGain, A.pitchJitter)
end

-- GTA-style pause muffle: lowpass + duck everything currently audible.
-- UI sounds played after this (pause menu clicks) stay crisp.
function Audio.setMuffled(m)
    local A = TUNE.audio
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() then
                if m then
                    pcall(s.setFilter, s, { type = 'lowpass', volume = 1, highgain = A.muffleHighgain })
                else
                    pcall(s.setFilter, s)
                end
            end
        end
    end
    if ambience.bed then
        if m then
            pcall(ambience.bed.setFilter, ambience.bed,
                { type = 'lowpass', volume = 1, highgain = A.muffleHighgain })
        else
            pcall(ambience.bed.setFilter, ambience.bed)
        end
        ambience.bed:setVolume(Audio.master * Audio.music * A.bedGain * fade.mult
            * (m and A.muffleDuck or 1))
    end
end

function Audio.setVolumes(master, sfx, music)
    Audio.master = master or Audio.master
    Audio.sfx = sfx or Audio.sfx
    Audio.music = music or Audio.music
    applyVolumes()
end

return Audio
