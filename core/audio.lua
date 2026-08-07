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
    -- per-gun pick/raise handling: on select, on pickup, after a reload ends
    usp_pick       = 'assets/sounds/weapons/usp_pick.wav',
    ak47_pick      = 'assets/sounds/weapons/ak47_pick.wav',
    m4a1_pick      = 'assets/sounds/weapons/m4a1_pick.wav',
    grenade_draw   = 'assets/sounds/weapons/grenade_draw.wav',
    grenade_pull   = 'assets/sounds/weapons/grenade_pull.wav',  -- CS-style pin pull on deploy
    grenade_throw  = 'assets/sounds/weapons/grenade_throw.wav', -- arm whoosh on release
    -- reload handling
    usp_reload     = 'assets/sounds/weapons/usp_reload.wav',
    ak47_reload    = 'assets/sounds/weapons/ak47_reload.wav',
    m4a1_reload    = 'assets/sounds/weapons/m4a1_reload.wav',
    -- the one shotgun pump: per-shot rack, pickup/select, post-reload chamber
    -- (reload start itself is silent — you only hear shells going in)
    shotgun_pump   = 'assets/sounds/weapons/shotgun_pump.wav',
    -- empty-clip trigger pull: revolver-style hammer click, shared by every gun
    dry_fire       = 'assets/sounds/weapons/dry_fire.wav',
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
    medkit_heal    = 'assets/sounds/effects/medkit.mp3', -- Gabriel's new cue (old medkit_heal.wav kept on disk)
    molotov_break  = 'assets/sounds/effects/molotov_break.wav', -- bottle shatter + ignite
    door_unlock    = 'assets/sounds/effects/door_unlock.wav',   -- key click + bolt clunk on door buy
    spin_wheel     = 'assets/sounds/effects/spin_wheel.mp3',            -- mystery box item roulette
    crate_open     = 'assets/sounds/effects/crate_open.mp3',            -- mystery box lid opening
    fire_loop      = 'assets/sounds/effects/fire_loop.wav',     -- looped by FirePatch
    -- player pain (random via the 'player_damage' group; old hurt grunts
    -- retired to assets/(outdated)/)
    player_damage1 = 'assets/sounds/effects/player_damage1.mp3',
    player_damage2 = 'assets/sounds/effects/player_damage2.mp3',
    player_dead    = 'assets/sounds/effects/player_dead.mp3',   -- death: replaces the damage cue
    mother_fucker  = 'assets/sounds/effects/mother_fucker.mp3', -- rare damage easter egg
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
local srcWorld = {}   -- Source -> true: world one-shot (freezes with the pause)
setmetatable(srcWorld, { __mode = 'k' })
local pausedWorld = {} -- sources paused by the pause muffle, resumed on unpause
local loops = {}      -- looping world sounds owned by entities (fire patches)
local occlusionTimer = 0 -- loops re-check their wall occlusion on this timer
local muffled = false  -- pause-muffle state, read by applyVolumes (bed duck)
local muffleMult = 1   -- smoothed bed duck: eases toward muffleDuck / back to 1
local lowHealth = false -- ≤25hp state: ducks the world, runs the heartbeat
local heartbeat = nil   -- dedicated looping source, never ducked

-- world duck while at critical health (heartbeat stays full)
local function duckMult()
    return lowHealth and TUNE.audio.lowHealthDuck or 1
end

-- run-start fade-in: multiplies every gameplay volume, rises 0 -> 1 over dur
local fade = { mult = 1, t = 0, dur = 0 }

-- Menu music: one looping stream that never stops, only fades. target 1 =
-- audible (menu, pause), target 0 = silent (gameplay). Fade-in and fade-out
-- speeds differ (tune.audio.musicFadeInTime / musicFadeOutTime).
local menuMusic = { src = nil, vol = 1, target = 1 }

local effectsOk = false
local listener = { x = 0, y = 0 }        -- world px, for occlusion + stingers
local reverb = { wet = 0, decay = 0.5, timer = 0 }
local ambience = { bed = nil, set = nil, stingerTimer = 0 }

-- The web build ships every sound re-encoded to .ogg (see build.sh web), so a
-- path pointing at a .wav/.mp3 that isn't there falls back to the .ogg beside
-- it. Desktop always hits the first branch and never pays for this.
local function resolvePath(path)
    if love.filesystem.getInfo(path) then return path end
    local ogg = path:gsub('%.%w+$', '.ogg')
    if ogg ~= path and love.filesystem.getInfo(ogg) then return ogg end
    return nil
end

-- Streaming needs a decoder thread, and love.js has no threads -- every source
-- in the browser must be fully decoded up front. This is why the web build
-- ships short music/ambience loops instead of the full tracks.
local function longSourceType()
    return WEB and 'static' or 'stream'
end

local function registerGroup(name)
    local base = name:match('^(.-)%d+$')
    if base and base ~= '' then
        groups[base] = groups[base] or {}
        table.insert(groups[base], name)
    end
end

function Audio.load()
    for name, path in pairs(files) do
        local p = resolvePath(path)
        if p then
            pools[name] = { love.audio.newSource(p, 'static') }
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

-- Global voice budget. poolSize caps how many copies of ONE sound can overlap,
-- which says nothing about the total: 60 registered sounds each playing once
-- is 60 voices. Desktop OpenAL shrugs that off, OpenAL-wasm does not. Counted
-- on a timer rather than per play (isPlaying is a driver round-trip) and
-- nudged as voices are handed out, so it only has to be roughly right.
local liveVoices = 0
local voiceTimer = 0

local function countVoices()
    local n = 0
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() then n = n + 1 end
        end
    end
    return n + #loops
end

-- Stop the voice closest to finishing, anywhere. Losing the last 40ms of a
-- casing bounce is inaudible; losing the shot you just fired is not.
local function stealGlobal()
    local best, bestLeft
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() then
                local left = s:getDuration('seconds') - s:tell('seconds')
                if not bestLeft or left < bestLeft then best, bestLeft = s, left end
            end
        end
    end
    if best then best:stop() end
    return best
end

-- A new play must ALWAYS get a voice (rapid AK fire never goes silent).
-- Free source first, grow the pool to poolSize, then steal the play that's
-- closest to finishing — standard channel-stealing, what CS/Source does.
local function grabSource(name)
    local pool = pools[name]
    if not pool then return nil end

    -- over the global ceiling: free one before taking another
    if liveVoices >= TUNE.audio.maxVoices and stealGlobal() then
        liveVoices = liveVoices - 1
    end

    for _, s in ipairs(pool) do
        if not s:isPlaying() then
            liveVoices = liveVoices + 1
            return s
        end
    end
    if #pool < TUNE.audio.poolSize then
        local src = pool[1]:clone()
        table.insert(pool, src)
        liveVoices = liveVoices + 1
        return src
    end
    local best, bestLeft
    for _, s in ipairs(pool) do
        local left = s:getDuration('seconds') - s:tell('seconds')
        if not bestLeft or left < bestLeft then best, bestLeft = s, left end
    end
    best:stop() -- already counted as live; it stays live
    return best
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
    srcWorld[src] = nil
    src:setVolume(Audio.master * Audio.sfx * (gain or 1)
        * (noFade and 1 or fade.mult * duckMult()))
    src:play()
    return src
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
            and world.map:wallBetween(listener.x, listener.y, x, y) then
            src:setFilter({ type = 'lowpass', volume = 1, highgain = A.occlusionHighgain })
        else
            src:setFilter()
        end
        if effectsOk then pcall(src.setEffect, src, 'room') end
    end

    src:setPitch(jitter and (1 + (love.math.random() * 2 - 1) * jitter) or 1)
    srcGain[src] = gain or 1
    srcNoFade[src] = nil
    srcWorld[src] = true
    src:setVolume(Audio.master * Audio.sfx * (gain or 1) * fade.mult * duckMult())
    src:play()
    return src
end

-- Looping world sound owned by an entity (the molotov fire patch). Lives
-- outside the one-shot pools: the owner holds the handle and MUST stop it.
-- gain is live-settable so the owner can fade the loop in/out.
function Audio.loopAt(name, x, y, gain)
    local path = files[name] and resolvePath(files[name])
    if not path then return nil end
    local A = TUNE.audio
    local src = love.audio.newSource(path, 'static')
    src:setLooping(true)
    if src:getChannelCount() == 1 then
        src:setRelative(false)
        src:setPosition(x / A.pxPerUnit, y / A.pxPerUnit, 0)
        src:setAttenuationDistances(A.refDist, A.maxDist)
        if effectsOk then pcall(src.setEffect, src, 'room') end
    end
    local h = { src = src, gain = gain or 1, x = x, y = y }
    table.insert(loops, h)
    src:setVolume(Audio.master * Audio.sfx * h.gain * fade.mult * duckMult())
    src:play()
    return h
end

function Audio.setLoopGain(h, gain)
    if not h then return end
    h.gain = gain
    h.src:setVolume(Audio.master * Audio.sfx * gain * fade.mult * duckMult())
end

function Audio.stopLoop(h)
    if not h then return end
    h.src:stop()
    for i, other in ipairs(loops) do
        if other == h then table.remove(loops, i) break end
    end
end

-- Run teardown: a fire patch that dies with the run never stops its own loop
function Audio.stopAllLoops()
    for _, h in ipairs(loops) do h.src:stop() end
    loops = {}
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
    local path = resolvePath('assets/sounds/ambient/' .. set .. '_bed.ogg')
    if not path then return end
    ambience.set = set
    ambience.bed = love.audio.newSource(path, longSourceType())
    ambience.bed:setLooping(true)
    ambience.bed:setVolume(Audio.master * Audio.music * TUNE.audio.bedGain * fade.mult)
    ambience.bed:play()
    ambience.stingerTimer = love.math.random(TUNE.audio.stingerMin, TUNE.audio.stingerMax)
end

function Audio.stopAmbience()
    Audio.setLowHealth(false) -- leaving a run must kill the heartbeat + duck
    Audio.stopAllLoops()      -- ...and any fire still burning in the dead run
    -- ...and any long world one-shot still ringing (mystery box spin wheel).
    -- Listener-pinned sounds (menu clicks, the start cue) keep playing.
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if srcWorld[s] and s:isPlaying() then s:stop() end
        end
    end
    if ambience.bed then ambience.bed:stop() end
    ambience.bed, ambience.set = nil, nil
end

-- Re-apply every live volume from the current master/sfx/music + fade state
local function applyVolumes()
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() and not srcNoFade[s] then
                s:setVolume(Audio.master * Audio.sfx * (srcGain[s] or 1)
                    * fade.mult * duckMult())
            end
        end
    end
    if ambience.bed then
        -- the pause duck survives volume changes made from the pause menu
        ambience.bed:setVolume(Audio.master * Audio.music * TUNE.audio.bedGain * fade.mult
            * muffleMult * duckMult())
    end
    if heartbeat and heartbeat:isPlaying() then
        heartbeat:setVolume(Audio.master * Audio.sfx * TUNE.audio.heartbeatGain)
    end
    for _, h in ipairs(loops) do
        h.src:setVolume(Audio.master * Audio.sfx * h.gain * fade.mult * duckMult())
    end
end

-- Critical-health state, driven every frame by World:update. Entering it
-- ducks everything and starts the heartbeat loop; leaving restores.
function Audio.setLowHealth(on)
    if on == lowHealth then return end
    lowHealth = on
    if on then
        if not heartbeat then
            local path = resolvePath('assets/sounds/effects/heartbeat.wav')
            if path then
                heartbeat = love.audio.newSource(path, 'static')
                heartbeat:setLooping(true)
            end
        end
        if heartbeat then
            heartbeat:setVolume(Audio.master * Audio.sfx * TUNE.audio.heartbeatGain)
            heartbeat:play()
        end
    elseif heartbeat then
        heartbeat:stop()
    end
    applyVolumes()
end

-- Start the menu music at launch; keeps looping for the whole session
function Audio.startMusic()
    if menuMusic.src then return end
    local path = resolvePath('assets/music/no_birds.mp3')
    if not path then return end
    menuMusic.src = love.audio.newSource(path, longSourceType())
    menuMusic.src:setLooping(true)
    menuMusic.src:setVolume(Audio.master * Audio.music * TUNE.audio.menuMusicGain)
    menuMusic.src:play()
end

-- 1 = menu/pause (fade in), 0 = gameplay (fade out)
function Audio.setMusicTarget(t)
    menuMusic.target = t
end

-- Per-frame music fade toward the target (part of Audio.update below)
local function updateMusic(dt)
    local m = menuMusic
    if not m.src then return end
    local A = TUNE.audio
    if m.vol < m.target then
        m.vol = math.min(m.target, m.vol + dt / A.musicFadeInTime)
    elseif m.vol > m.target then
        m.vol = math.max(m.target, m.vol - dt / A.musicFadeOutTime)
    end
    m.src:setVolume(Audio.master * Audio.music * A.menuMusicGain * m.vol)
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

-- Per-frame audio upkeep: music fade, run-start fade, pause duck, loop
-- occlusion, ambience stingers. Called once from love.update — runs in every
-- state (menu music must fade while menus are up, ducks while paused).
function Audio.update(dt)
    updateMusic(dt)

    -- resync the voice count with reality; between resyncs it drifts high
    -- (finished sounds still counted), which errs toward stealing early
    voiceTimer = voiceTimer - dt
    if voiceTimer <= 0 then
        voiceTimer = 0.25
        liveVoices = countVoices()
    end
    if fade.mult < 1 and fade.dur > 0 then
        fade.t = fade.t + dt
        fade.mult = math.min(1, fade.t / fade.dur)
        applyVolumes()
    end

    -- pause duck eases toward its target instead of snapping (the pause
    -- state ticks this too, since world updates stop while paused)
    local target = muffled and TUNE.audio.muffleDuck or 1
    if math.abs(muffleMult - target) > 0.001 then
        local k = 1 - math.exp(-TUNE.audio.muffleFadeSpeed * dt)
        muffleMult = muffleMult + (target - muffleMult) * k
        applyVolumes()
    end

    if muffled then return end -- no stingers (and no loop retuning) while paused

    -- looping world sounds re-check the wall between them and the ear
    occlusionTimer = occlusionTimer - dt
    if occlusionTimer <= 0 and #loops > 0 then
        occlusionTimer = 0.2
        local A = TUNE.audio
        local w = _G.world
        for _, h in ipairs(loops) do
            if w and w.map and w.map:wallBetween(listener.x, listener.y, h.x, h.y) then
                pcall(h.src.setFilter, h.src,
                    { type = 'lowpass', volume = 1, highgain = A.occlusionHighgain })
            else
                pcall(h.src.setFilter, h.src)
            end
        end
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

-- GTA-style pause muffle. World one-shots (reloads, casings, growls) PAUSE
-- with the game — a 2.5s reload sound must not play out while its reload
-- timer is frozen — and resume where they stopped. The ambience bed keeps
-- running lowpassed + ducked so the pause still has a sound floor, and UI
-- sounds played after this (pause menu clicks) stay crisp.
function Audio.setMuffled(m)
    local A = TUNE.audio
    muffled = m
    if m then
        for _, pool in pairs(pools) do
            for _, s in ipairs(pool) do
                if s:isPlaying() then
                    if srcWorld[s] then
                        s:pause()
                        table.insert(pausedWorld, s)
                    else
                        pcall(s.setFilter, s, { type = 'lowpass', volume = 1, highgain = A.muffleHighgain })
                    end
                end
            end
        end
        for _, h in ipairs(loops) do h.src:pause() end -- fire freezes with the world
    else
        for _, s in ipairs(pausedWorld) do pcall(s.play, s) end
        pausedWorld = {}
        for _, h in ipairs(loops) do h.src:play() end
        for _, pool in pairs(pools) do
            for _, s in ipairs(pool) do
                if s:isPlaying() then pcall(s.setFilter, s) end
            end
        end
    end
    if ambience.bed then
        -- filter snaps, the volume duck fades (Audio.update eases muffleMult)
        if m then
            pcall(ambience.bed.setFilter, ambience.bed,
                { type = 'lowpass', volume = 1, highgain = A.muffleHighgain })
        else
            pcall(ambience.bed.setFilter, ambience.bed)
        end
        applyVolumes()
    end
end

function Audio.setVolumes(master, sfx, music)
    Audio.master = master or Audio.master
    Audio.sfx = sfx or Audio.sfx
    Audio.music = music or Audio.music
    applyVolumes()
end

return Audio
